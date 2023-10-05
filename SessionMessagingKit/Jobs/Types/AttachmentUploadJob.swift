// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine
import GRDB
import SignalCoreKit
import SessionUtilitiesKit

public enum AttachmentUploadJob: JobExecutor {
    public static var maxFailureCount: Int = 10
    public static var requiresThreadId: Bool = true
    public static let requiresInteractionId: Bool = true
    
    public static func run(
        _ job: Job,
        queue: DispatchQueue,
        success: @escaping (Job, Bool, Dependencies) -> (),
        failure: @escaping (Job, Error?, Bool, Dependencies) -> (),
        deferred: @escaping (Job, Dependencies) -> (),
        using dependencies: Dependencies
    ) {
        guard
            let threadId: String = job.threadId,
            let interactionId: Int64 = job.interactionId,
            let detailsData: Data = job.details,
            let details: Details = try? JSONDecoder(using: dependencies).decode(Details.self, from: detailsData),
            let attachment: Attachment = dependencies[singleton: .storage]
                .read({ db in try Attachment.fetchOne(db, id: details.attachmentId) })
        else {
            SNLog("[AttachmentUploadJob] Failed due to missing details")
            return failure(job, JobRunnerError.missingRequiredDetails, true, dependencies)
        }
        
        // If the original interaction no longer exists then don't bother uploading the attachment (ie. the
        // message was deleted before it even got sent)
        guard dependencies[singleton: .storage].read({ db in try Interaction.exists(db, id: interactionId) }) == true else {
            SNLog("[AttachmentUploadJob] Failed due to missing interaction")
            return failure(job, StorageError.objectNotFound, true, dependencies)
        }
        
        // If the attachment is still pending download the hold off on running this job
        guard attachment.state != .pendingDownload && attachment.state != .downloading else {
            SNLog("[AttachmentUploadJob] Deferred as attachment is still being downloaded")
            return deferred(job, dependencies)
        }
        
        // If this upload is related to sending a message then trigger the 'handleMessageWillSend' logic
        // as if this is a retry the logic wouldn't run until after the upload has completed resulting in
        // a potentially incorrect delivery status
        dependencies[singleton: .storage].write(using: dependencies) { db in
            guard
                let sendJob: Job = try Job.fetchOne(db, id: details.messageSendJobId),
                let sendJobDetails: Data = sendJob.details,
                let details: MessageSendJob.Details = try? JSONDecoder(using: dependencies)
                    .decode(MessageSendJob.Details.self, from: sendJobDetails)
            else { return }
            
            MessageSender.handleMessageWillSend(
                db,
                message: details.message,
                interactionId: interactionId,
                isSyncMessage: details.isSyncMessage
            )
        }
        
        // Note: In the AttachmentUploadJob we intentionally don't provide our own db instance to prevent
        // reentrancy issues when the success/failure closures get called before the upload as the JobRunner
        // will attempt to update the state of the job immediately
        dependencies[singleton: .storage]
            .writePublisher(using: dependencies) { db -> HTTP.PreparedRequest<String> in
                try attachment.preparedUpload(db, threadId: threadId, using: dependencies)
            }
            .flatMap { $0.send(using: dependencies) }
            .subscribe(on: queue, using: dependencies)
            .receive(on: queue, using: dependencies)
            .sinkUntilComplete(
                receiveCompletion: { result in
                    switch result {
                        case .failure(let error):
                            // If this upload is related to sending a message then trigger the
                            // 'handleFailedMessageSend' logic as we want to ensure the message
                            // has the correct delivery status
                            var didLogError: Bool = false
                            
                            dependencies[singleton: .storage].read(using: dependencies) { db in
                                guard
                                    let sendJob: Job = try Job.fetchOne(db, id: details.messageSendJobId),
                                    let sendJobDetails: Data = sendJob.details,
                                    let details: MessageSendJob.Details = try? JSONDecoder(using: dependencies)
                                        .decode(MessageSendJob.Details.self, from: sendJobDetails)
                                else { return }
                                
                                MessageSender.handleFailedMessageSend(
                                    db,
                                    message: details.message,
                                    with: MessageSenderError.other("[AttachmentUploadJob] Failed", error),
                                    interactionId: interactionId,
                                    isSyncMessage: details.isSyncMessage,
                                    using: dependencies
                                )
                                didLogError = true
                            }
                            
                            // If we didn't log an error above then log it now
                            if !didLogError { SNLog("[AttachmentUploadJob] Failed due to error: \(error)") }
                            failure(job, error, false, dependencies)
                        
                        case .finished: success(job, false, dependencies)
                    }
                }
            )
    }
}

// MARK: - AttachmentUploadJob.Details

extension AttachmentUploadJob {
    public struct Details: Codable {
        /// This is the id for the messageSend job this attachmentUpload job is associated to, the value isn't used for any of
        /// the logic but we want to mandate that the attachmentUpload job can only be used alongside a messageSend job
        ///
        /// **Note:** If we do decide to remove this the `_003_YDBToGRDBMigration` will need to be updated as it
        /// fails if this connection can't be made
        public let messageSendJobId: Int64
        
        /// The id of the `Attachment` to upload
        public let attachmentId: String
        
        public init(messageSendJobId: Int64, attachmentId: String) {
            self.messageSendJobId = messageSendJobId
            self.attachmentId = attachmentId
        }
    }
}
