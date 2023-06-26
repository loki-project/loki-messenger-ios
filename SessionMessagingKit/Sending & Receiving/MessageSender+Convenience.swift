// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine
import GRDB
import SessionUtilitiesKit

extension MessageSender {
    
    // MARK: - Durable
    
    public static func send(
        _ db: Database,
        interaction: Interaction,
        threadId: String,
        threadVariant: SessionThread.Variant,
        isSyncMessage: Bool = false
    ) throws {
        // Only 'VisibleMessage' types can be sent via this method
        guard interaction.variant == .standardOutgoing else { throw MessageSenderError.invalidMessage }
        guard let interactionId: Int64 = interaction.id else { throw StorageError.objectNotSaved }
        
        send(
            db,
            message: VisibleMessage.from(db, interaction: interaction),
            threadId: threadId,
            interactionId: interactionId,
            to: try Message.Destination.from(db, threadId: threadId, threadVariant: threadVariant),
            isSyncMessage: isSyncMessage
        )
    }
    
    public static func send(
        _ db: Database,
        message: Message,
        interactionId: Int64?,
        threadId: String,
        threadVariant: SessionThread.Variant,
        isSyncMessage: Bool = false
    ) throws {
        send(
            db,
            message: message,
            threadId: threadId,
            interactionId: interactionId,
            to: try Message.Destination.from(db, threadId: threadId, threadVariant: threadVariant),
            isSyncMessage: isSyncMessage
        )
    }
    
    public static func send(
        _ db: Database,
        message: Message,
        threadId: String?,
        interactionId: Int64?,
        to destination: Message.Destination,
        isSyncMessage: Bool = false
    ) {
        // If it's a sync message then we need to make some slight tweaks before sending so use the proper
        // sync message sending process instead of the standard process
        guard !isSyncMessage else {
            scheduleSyncMessageIfNeeded(
                db,
                message: message,
                destination: destination,
                threadId: threadId,
                interactionId: interactionId,
                isAlreadySyncMessage: false
            )
            return
        }
        
        JobRunner.add(
            db,
            job: Job(
                variant: .messageSend,
                threadId: threadId,
                interactionId: interactionId,
                details: MessageSendJob.Details(
                    destination: destination,
                    message: message,
                    isSyncMessage: isSyncMessage
                )
            )
        )
    }

    // MARK: - Non-Durable
    
    public static func preparedSendData(
        _ db: Database,
        interaction: Interaction,
        threadId: String,
        threadVariant: SessionThread.Variant
    ) throws -> PreparedSendData {
        // Only 'VisibleMessage' types can be sent via this method
        guard interaction.variant == .standardOutgoing else { throw MessageSenderError.invalidMessage }
        guard let interactionId: Int64 = interaction.id else { throw StorageError.objectNotSaved }

        return try MessageSender.preparedSendData(
            db,
            message: VisibleMessage.from(db, interaction: interaction),
            to: try Message.Destination.from(db, threadId: threadId, threadVariant: threadVariant),
            namespace: try Message.Destination
                .from(db, threadId: threadId, threadVariant: threadVariant)
                .defaultNamespace,
            interactionId: interactionId
        )
    }
    
    public static func performUploadsIfNeeded(preparedSendData: PreparedSendData) -> AnyPublisher<PreparedSendData, Error> {
        // We need an interactionId in order for a message to have uploads
        guard let interactionId: Int64 = preparedSendData.interactionId else {
            return Just(preparedSendData)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        let threadId: String = {
            switch preparedSendData.destination {
                case .contact(let publicKey): return publicKey
                case .closedGroup(let groupPublicKey): return groupPublicKey
                case .openGroup(let roomToken, let server, _, _, _):
                    return OpenGroup.idFor(roomToken: roomToken, server: server)
                
                case .openGroupInbox(_, _, let blindedPublicKey): return blindedPublicKey
            }
        }()
        
        return Storage.shared
            .readPublisher { db -> (attachments: [Attachment], openGroup: OpenGroup?) in
                let attachmentStateInfo: [Attachment.StateInfo] = (try? Attachment
                    .stateInfo(interactionId: interactionId, state: .uploading)
                    .fetchAll(db))
                    .defaulting(to: [])
                
                // If there is no attachment data then just return early
                guard !attachmentStateInfo.isEmpty else { return ([], nil) }
                
                // Otherwise fetch the open group (if there is one)
                return (
                    (try? Attachment
                        .filter(ids: attachmentStateInfo.map { $0.attachmentId })
                        .fetchAll(db))
                        .defaulting(to: []),
                    try? OpenGroup.fetchOne(db, id: threadId)
                )
            }
            .flatMap { attachments, openGroup -> AnyPublisher<[String?], Error> in
                guard !attachments.isEmpty else {
                    return Just<[String?]>([])
                        .setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                }
                
                return Publishers
                    .MergeMany(
                        attachments
                            .map { attachment -> AnyPublisher<String?, Error> in
                                attachment
                                    .upload(
                                        to: (
                                            openGroup.map { Attachment.Destination.openGroup($0) } ??
                                            .fileServer
                                        )
                                    )
                            }
                    )
                    .collect()
                    .eraseToAnyPublisher()
            }
            .map { results -> PreparedSendData in
                // Once the attachments are processed then update the PreparedSendData with
                // the fileIds associated to the message
                let fileIds: [String] = results.compactMap { result -> String? in result }
                
                return preparedSendData.with(fileIds: fileIds)
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Convenience
    
    internal static func getSpecifiedTTL(
        _ db: Database,
        threadId: String,
        message: Message,
        isSyncMessage: Bool
    ) -> UInt64? {
        guard
            let disappearingMessagesConfiguration = try? DisappearingMessagesConfiguration.fetchOne(db, id: threadId),
            disappearingMessagesConfiguration.isEnabled,
            (
                disappearingMessagesConfiguration.type == .disappearAfterSend ||
                isSyncMessage
            )
        else { return nil }
        
        return UInt64(disappearingMessagesConfiguration.durationSeconds * 1000)
    }
}
