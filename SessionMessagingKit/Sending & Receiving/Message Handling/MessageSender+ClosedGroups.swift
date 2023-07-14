// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine
import GRDB
import Sodium
import Curve25519Kit
import SessionUtilitiesKit
import SessionSnodeKit

extension MessageSender {
    public static var distributingKeyPairs: Atomic<[String: [ClosedGroupKeyPair]]> = Atomic([:])
    
    public static func createClosedGroup(
        name: String,
        members: Set<String>
    ) -> AnyPublisher<SessionThread, Error> {
        Storage.shared
            .writePublisher { db -> (String, SessionThread, [MessageSender.PreparedSendData]) in
                let userPublicKey: String = getUserHexEncodedPublicKey(db)
                var members: Set<String> = members
                
                // Generate the group's public key
                let groupKeyPair: ECKeyPair = Curve25519.generateKeyPair()
                let groupPublicKey: String = KeyPair(
                    publicKey: groupKeyPair.publicKey.bytes,
                    secretKey: groupKeyPair.privateKey.bytes
                ).hexEncodedPublicKey // Includes the 'SessionId.Prefix.standard' prefix
                // Generate the key pair that'll be used for encryption and decryption
                let encryptionKeyPair: ECKeyPair = Curve25519.generateKeyPair()
                
                // Create the group
                members.insert(userPublicKey) // Ensure the current user is included in the member list
                let membersAsData: [Data] = members.map { Data(hex: $0) }
                let admins: Set<String> = [ userPublicKey ]
                let adminsAsData: [Data] = admins.map { Data(hex: $0) }
                let formationTimestamp: TimeInterval = (TimeInterval(SnodeAPI.currentOffsetTimestampMs()) / 1000)
                
                // Create the relevant objects in the database
                let thread: SessionThread = try SessionThread
                    .fetchOrCreate(db, id: groupPublicKey, variant: .legacyGroup, shouldBeVisible: true)
                try ClosedGroup(
                    threadId: groupPublicKey,
                    name: name,
                    formationTimestamp: formationTimestamp
                ).insert(db)
                
                // Store the key pair
                let latestKeyPairReceivedTimestamp: TimeInterval = (TimeInterval(SnodeAPI.currentOffsetTimestampMs()) / 1000)
                try ClosedGroupKeyPair(
                    threadId: groupPublicKey,
                    publicKey: encryptionKeyPair.publicKey,
                    secretKey: encryptionKeyPair.privateKey,
                    receivedTimestamp: latestKeyPairReceivedTimestamp
                ).insert(db)
                
                // Create the member objects
                try admins.forEach { adminId in
                    try GroupMember(
                        groupId: groupPublicKey,
                        profileId: adminId,
                        role: .admin,
                        isHidden: false
                    ).save(db)
                }
                
                try members.forEach { memberId in
                    try GroupMember(
                        groupId: groupPublicKey,
                        profileId: memberId,
                        role: .standard,
                        isHidden: false
                    ).save(db)
                }
                
                // Update libSession
                try SessionUtil.add(
                    db,
                    groupPublicKey: groupPublicKey,
                    name: name,
                    latestKeyPairPublicKey: encryptionKeyPair.publicKey,
                    latestKeyPairSecretKey: encryptionKeyPair.privateKey,
                    latestKeyPairReceivedTimestamp: latestKeyPairReceivedTimestamp,
                    disappearingConfig: DisappearingMessagesConfiguration.defaultWith(groupPublicKey),
                    members: members,
                    admins: admins
                )
                
                let memberSendData: [MessageSender.PreparedSendData] = try members
                    .map { memberId -> MessageSender.PreparedSendData in
                        try MessageSender.preparedSendData(
                            db,
                            message: ClosedGroupControlMessage(
                                kind: .new(
                                    publicKey: Data(hex: groupPublicKey),
                                    name: name,
                                    encryptionKeyPair: KeyPair(
                                        publicKey: encryptionKeyPair.publicKey.bytes,
                                        secretKey: encryptionKeyPair.privateKey.bytes
                                    ),
                                    members: membersAsData,
                                    admins: adminsAsData,
                                    expirationTimer: 0
                                ),
                                // Note: We set this here to ensure the value matches
                                // the 'ClosedGroup' object we created
                                sentTimestampMs: UInt64(floor(formationTimestamp * 1000))
                            ),
                            to: .contact(publicKey: memberId),
                            namespace: Message.Destination.contact(publicKey: memberId).defaultNamespace,
                            interactionId: nil
                        )
                    }
                
                return (userPublicKey, thread, memberSendData)
            }
            .flatMap { userPublicKey, thread, memberSendData in
                Publishers
                    .MergeMany(
                        // Send a closed group update message to all members individually
                        memberSendData
                            .map { MessageSender.sendImmediate(preparedSendData: $0) }
                            .appending(
                                // Notify the PN server
                                PushNotificationAPI.performOperation(
                                    .subscribe,
                                    for: thread.id,
                                    publicKey: userPublicKey
                                )
                            )
                    )
                    .collect()
                    .map { _ in thread }
            }
            .handleEvents(
                receiveOutput: { thread in
                    // Start polling
                    ClosedGroupPoller.shared.startIfNeeded(for: thread.id)
                }
            )
            .eraseToAnyPublisher()
    }

    /// Generates and distributes a new encryption key pair for the group with the given closed group. This sends an
    /// `ENCRYPTION_KEY_PAIR` message to the group. The message contains a list of key pair wrappers. Each key
    /// pair wrapper consists of the public key for which the wrapper is intended along with the newly generated key pair
    /// encrypted for that public key.
    ///
    /// The returned promise is fulfilled when the message has been sent to the group.
    private static func generateAndSendNewEncryptionKeyPair(
        targetMembers: Set<String>,
        userPublicKey: String,
        allGroupMembers: [GroupMember],
        closedGroup: ClosedGroup
    ) -> AnyPublisher<Void, Error> {
        guard allGroupMembers.contains(where: { $0.role == .admin && $0.profileId == userPublicKey }) else {
            return Fail(error: MessageSenderError.invalidClosedGroupUpdate)
                .eraseToAnyPublisher()
        }
        
        return Storage.shared
            .readPublisher { db -> (ClosedGroupKeyPair, MessageSender.PreparedSendData) in
                // Generate the new encryption key pair
                let legacyNewKeyPair: ECKeyPair = Curve25519.generateKeyPair()
                let newKeyPair: ClosedGroupKeyPair = ClosedGroupKeyPair(
                    threadId: closedGroup.threadId,
                    publicKey: legacyNewKeyPair.publicKey,
                    secretKey: legacyNewKeyPair.privateKey,
                    receivedTimestamp: (TimeInterval(SnodeAPI.currentOffsetTimestampMs()) / 1000)
                )
                
                // Distribute it
                let proto = try SNProtoKeyPair.builder(
                    publicKey: newKeyPair.publicKey,
                    privateKey: newKeyPair.secretKey
                ).build()
                let plaintext = try proto.serializedData()
                
                distributingKeyPairs.mutate {
                    $0[closedGroup.id] = ($0[closedGroup.id] ?? [])
                        .appending(newKeyPair)
                }
                
                let sendData: MessageSender.PreparedSendData = try MessageSender
                    .preparedSendData(
                        db,
                        message: ClosedGroupControlMessage(
                            kind: .encryptionKeyPair(
                                publicKey: nil,
                                wrappers: targetMembers.map { memberPublicKey in
                                    ClosedGroupControlMessage.KeyPairWrapper(
                                        publicKey: memberPublicKey,
                                        encryptedKeyPair: try MessageSender.encryptWithSessionProtocol(
                                            db,
                                            plaintext: plaintext,
                                            for: memberPublicKey
                                        )
                                    )
                                }
                            )
                        ),
                        to: try Message.Destination
                            .from(db, threadId: closedGroup.threadId, threadVariant: .legacyGroup),
                        namespace: try Message.Destination
                            .from(db, threadId: closedGroup.threadId, threadVariant: .legacyGroup)
                            .defaultNamespace,
                        interactionId: nil
                    )
                
                return (newKeyPair, sendData)
            }
            .flatMap { newKeyPair, sendData -> AnyPublisher<ClosedGroupKeyPair, Error> in
                MessageSender.sendImmediate(preparedSendData: sendData)
                    .map { _ in newKeyPair }
                    .eraseToAnyPublisher()
            }
            .handleEvents(
                receiveOutput: { newKeyPair in
                    /// Store it **after** having sent out the message to the group
                    Storage.shared.write { db in
                        try newKeyPair.insert(db)
                        
                        // Update libSession
                        try? SessionUtil.update(
                            db,
                            groupPublicKey: closedGroup.threadId,
                            latestKeyPair: newKeyPair,
                            members: allGroupMembers
                                .filter { $0.role == .standard || $0.role == .zombie }
                                .map { $0.profileId }
                                .asSet(),
                            admins: allGroupMembers
                                .filter { $0.role == .admin }
                                .map { $0.profileId }
                                .asSet()
                        )
                    }
                    
                    distributingKeyPairs.mutate {
                        if let index = ($0[closedGroup.id] ?? []).firstIndex(of: newKeyPair) {
                            $0[closedGroup.id] = ($0[closedGroup.id] ?? [])
                                .removing(index: index)
                        }
                    }
                }
            )
            .map { _ in () }
            .eraseToAnyPublisher()
    }
    
    public static func update(
        groupPublicKey: String,
        with members: Set<String>,
        name: String
    ) -> AnyPublisher<Void, Error> {
        return Storage.shared
            .writePublisher { db -> (String, ClosedGroup, [GroupMember], Set<String>) in
                let userPublicKey: String = getUserHexEncodedPublicKey(db)
                
                // Get the group, check preconditions & prepare
                guard (try? SessionThread.exists(db, id: groupPublicKey)) == true else {
                    SNLog("Can't update nonexistent closed group.")
                    throw MessageSenderError.noThread
                }
                guard let closedGroup: ClosedGroup = try? ClosedGroup.fetchOne(db, id: groupPublicKey) else {
                    throw MessageSenderError.invalidClosedGroupUpdate
                }
                
                // Update name if needed
                if name != closedGroup.name {
                    // Update the group
                    _ = try ClosedGroup
                        .filter(id: closedGroup.id)
                        .updateAll(db, ClosedGroup.Columns.name.set(to: name))
                    
                    // Notify the user
                    let interaction: Interaction = try Interaction(
                        threadId: groupPublicKey,
                        authorId: userPublicKey,
                        variant: .infoClosedGroupUpdated,
                        body: ClosedGroupControlMessage.Kind
                            .nameChange(name: name)
                            .infoMessage(db, sender: userPublicKey),
                        timestampMs: SnodeAPI.currentOffsetTimestampMs()
                    ).inserted(db)
                    
                    guard let interactionId: Int64 = interaction.id else { throw StorageError.objectNotSaved }
                    
                    // Send the update to the group
                    try MessageSender.send(
                        db,
                        message: ClosedGroupControlMessage(kind: .nameChange(name: name)),
                        interactionId: interactionId,
                        threadId: groupPublicKey,
                        threadVariant: .legacyGroup
                    )
                    
                    // Update libSession
                    try? SessionUtil.update(
                        db,
                        groupPublicKey: closedGroup.threadId,
                        name: name
                    )
                }
                
                // Retrieve member info
                guard let allGroupMembers: [GroupMember] = try? closedGroup.allMembers.fetchAll(db) else {
                    throw MessageSenderError.invalidClosedGroupUpdate
                }
                
                let standardAndZombieMemberIds: [String] = allGroupMembers
                    .filter { $0.role == .standard || $0.role == .zombie }
                    .map { $0.profileId }
                let addedMembers: Set<String> = members.subtracting(standardAndZombieMemberIds)
                
                // Add members if needed
                if !addedMembers.isEmpty {
                    do {
                        try addMembers(
                            db,
                            addedMembers: addedMembers,
                            userPublicKey: userPublicKey,
                            allGroupMembers: allGroupMembers,
                            closedGroup: closedGroup
                        )
                    }
                    catch {
                        throw MessageSenderError.invalidClosedGroupUpdate
                    }
                }
                
                // Remove members if needed
                return (
                    userPublicKey,
                    closedGroup,
                    allGroupMembers,
                    Set(standardAndZombieMemberIds).subtracting(members)
                )
            }
            .flatMap { userPublicKey, closedGroup, allGroupMembers, removedMembers -> AnyPublisher<Void, Error> in
                guard !removedMembers.isEmpty else {
                    return Just(())
                        .setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                }
                
                return removeMembers(
                    removedMembers: removedMembers,
                    userPublicKey: userPublicKey,
                    allGroupMembers: allGroupMembers,
                    closedGroup: closedGroup
                )
                .catch { _ in Fail(error: MessageSenderError.invalidClosedGroupUpdate).eraseToAnyPublisher() }
                .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    

    /// Adds `newMembers` to the group with the given closed group. This sends a `MEMBERS_ADDED` message to the group, and a
    /// `NEW` message to the members that were added (using one-on-one channels).
    private static func addMembers(
        _ db: Database,
        addedMembers: Set<String>,
        userPublicKey: String,
        allGroupMembers: [GroupMember],
        closedGroup: ClosedGroup
    ) throws {
        guard let disappearingMessagesConfig: DisappearingMessagesConfiguration = try DisappearingMessagesConfiguration.fetchOne(db, id: closedGroup.threadId) else {
            throw StorageError.objectNotFound
        }
        guard let encryptionKeyPair: ClosedGroupKeyPair = try closedGroup.fetchLatestKeyPair(db) else {
            throw StorageError.objectNotFound
        }
        
        let groupMemberIds: [String] = allGroupMembers
            .filter { $0.role == .standard }
            .map { $0.profileId }
        let groupAdminIds: [String] = allGroupMembers
            .filter { $0.role == .admin }
            .map { $0.profileId }
        let members: Set<String> = Set(groupMemberIds).union(addedMembers)
        let membersAsData: [Data] = members.map { Data(hex: $0) }
        let adminsAsData: [Data] = groupAdminIds.map { Data(hex: $0) }
        
        // Notify the user
        let interaction: Interaction = try Interaction(
            threadId: closedGroup.threadId,
            authorId: userPublicKey,
            variant: .infoClosedGroupUpdated,
            body: ClosedGroupControlMessage.Kind
                .membersAdded(members: addedMembers.map { Data(hex: $0) })
                .infoMessage(db, sender: userPublicKey),
            timestampMs: SnodeAPI.currentOffsetTimestampMs()
        ).inserted(db)
        
        guard let interactionId: Int64 = interaction.id else { throw StorageError.objectNotSaved }
        
        // Update libSession
        try? SessionUtil.update(
            db,
            groupPublicKey: closedGroup.threadId,
            members: allGroupMembers
                .filter { $0.role == .standard || $0.role == .zombie }
                .map { $0.profileId }
                .asSet()
                .union(addedMembers),
            admins: allGroupMembers
                .filter { $0.role == .admin }
                .map { $0.profileId }
                .asSet()
        )
        
        // Send the update to the group
        try MessageSender.send(
            db,
            message: ClosedGroupControlMessage(
                kind: .membersAdded(members: addedMembers.map { Data(hex: $0) })
            ),
            interactionId: interactionId,
            threadId: closedGroup.threadId,
            threadVariant: .legacyGroup
        )
        
        try addedMembers.forEach { member in
            // Send updates to the new members individually
            try SessionThread.fetchOrCreate(db, id: member, variant: .contact, shouldBeVisible: nil)
            
            try MessageSender.send(
                db,
                message: ClosedGroupControlMessage(
                    kind: .new(
                        publicKey: Data(hex: closedGroup.id),
                        name: closedGroup.name,
                        encryptionKeyPair: KeyPair(
                            publicKey: encryptionKeyPair.publicKey.bytes,
                            secretKey: encryptionKeyPair.secretKey.bytes
                        ),
                        members: membersAsData,
                        admins: adminsAsData,
                        expirationTimer: (disappearingMessagesConfig.isEnabled ?
                            UInt32(floor(disappearingMessagesConfig.durationSeconds)) :
                            0
                        )
                    )
                ),
                interactionId: nil,
                threadId: member,
                threadVariant: .contact
            )
            
            // Add the users to the group
            try GroupMember(
                groupId: closedGroup.id,
                profileId: member,
                role: .standard,
                isHidden: false
            ).save(db)
        }
    }

    /// Removes `membersToRemove` from the group with the given `groupPublicKey`. Only the admin can remove members, and when they do
    /// they generate and distribute a new encryption key pair for the group. A member cannot leave a group using this method. For that they should use
    /// `leave(:using:)`.
    ///
    /// The returned promise is fulfilled when the `MEMBERS_REMOVED` message has been sent to the group AND the new encryption key pair has been
    /// generated and distributed.
    private static func removeMembers(
        removedMembers: Set<String>,
        userPublicKey: String,
        allGroupMembers: [GroupMember],
        closedGroup: ClosedGroup
    ) -> AnyPublisher<Void, Error> {
        guard !removedMembers.contains(userPublicKey) else {
            SNLog("Invalid closed group update.")
            return Fail(error: MessageSenderError.invalidClosedGroupUpdate)
                .eraseToAnyPublisher()
        }
        guard allGroupMembers.contains(where: { $0.role == .admin && $0.profileId == userPublicKey }) else {
            SNLog("Only an admin can remove members from a group.")
            return Fail(error: MessageSenderError.invalidClosedGroupUpdate)
                .eraseToAnyPublisher()
        }
        
        let groupMemberIds: [String] = allGroupMembers
            .filter { $0.role == .standard }
            .map { $0.profileId }
        let groupZombieIds: [String] = allGroupMembers
            .filter { $0.role == .zombie }
            .map { $0.profileId }
        let members: Set<String> = Set(groupMemberIds).subtracting(removedMembers)
        
        return Storage.shared
            .writePublisher { db in
                // Update zombie & member list
                try GroupMember
                    .filter(GroupMember.Columns.groupId == closedGroup.threadId)
                    .filter(removedMembers.contains(GroupMember.Columns.profileId))
                    .filter([ GroupMember.Role.standard, GroupMember.Role.zombie ].contains(GroupMember.Columns.role))
                    .deleteAll(db)
                
                let interactionId: Int64?
                
                // Notify the user if needed (not if only zombie members were removed)
                if !removedMembers.subtracting(groupZombieIds).isEmpty {
                    let interaction: Interaction = try Interaction(
                        threadId: closedGroup.threadId,
                        authorId: userPublicKey,
                        variant: .infoClosedGroupUpdated,
                        body: ClosedGroupControlMessage.Kind
                            .membersRemoved(members: removedMembers.map { Data(hex: $0) })
                            .infoMessage(db, sender: userPublicKey),
                        timestampMs: SnodeAPI.currentOffsetTimestampMs()
                    ).inserted(db)
                    
                    guard let newInteractionId: Int64 = interaction.id else { throw StorageError.objectNotSaved }
                    
                    interactionId = newInteractionId
                }
                else {
                    interactionId = nil
                }
                
                // Send the update to the group and generate + distribute a new encryption key pair
                return try MessageSender
                    .preparedSendData(
                        db,
                        message: ClosedGroupControlMessage(
                            kind: .membersRemoved(
                                members: removedMembers.map { Data(hex: $0) }
                            )
                        ),
                        to: try Message.Destination
                            .from(db, threadId: closedGroup.threadId, threadVariant: .legacyGroup),
                        namespace: try Message.Destination
                            .from(db, threadId: closedGroup.threadId, threadVariant: .legacyGroup)
                            .defaultNamespace,
                        interactionId: interactionId
                    )
            }
            .flatMap { MessageSender.sendImmediate(preparedSendData: $0) }
            .flatMap { _ -> AnyPublisher<Void, Error> in
                MessageSender.generateAndSendNewEncryptionKeyPair(
                    targetMembers: members,
                    userPublicKey: userPublicKey,
                    allGroupMembers: allGroupMembers,
                    closedGroup: closedGroup
                )
            }
            .eraseToAnyPublisher()
    }
    
    /// Leave the group with the given `groupPublicKey`. If the current user is the admin, the group is disbanded entirely. If the
    /// user is a regular member they'll be marked as a "zombie" member by the other users in the group (upon receiving the leave
    /// message). The admin can then truly remove them later.
    ///
    /// This function also removes all encryption key pairs associated with the closed group and the group's public key, and
    /// unregisters from push notifications.
    ///
    /// The returned promise is fulfilled when the `MEMBER_LEFT` message has been sent to the group.
    public static func leave(
        _ db: Database,
        groupPublicKey: String,
        deleteThread: Bool
    ) throws {
        let userPublicKey: String = getUserHexEncodedPublicKey(db)
        
        // Notify the user
        let interaction: Interaction = try Interaction(
            threadId: groupPublicKey,
            authorId: userPublicKey,
            variant: .infoClosedGroupCurrentUserLeaving,
            body: "group_you_leaving".localized(),
            timestampMs: SnodeAPI.currentOffsetTimestampMs()
        ).inserted(db)
        
        JobRunner.upsert(
            db,
            job: Job(
                variant: .groupLeaving,
                threadId: groupPublicKey,
                interactionId: interaction.id,
                details: GroupLeavingJob.Details(
                    deleteThread: deleteThread
                )
            )
        )
    }
    
    public static func sendLatestEncryptionKeyPair(
        _ db: Database,
        to publicKey: String,
        for groupPublicKey: String
    ) {
        guard let thread: SessionThread = try? SessionThread.fetchOne(db, id: groupPublicKey) else {
            return SNLog("Couldn't send key pair for nonexistent closed group.")
        }
        guard let closedGroup: ClosedGroup = try? thread.closedGroup.fetchOne(db) else {
            return
        }
        guard let allGroupMembers: [GroupMember] = try? closedGroup.allMembers.fetchAll(db) else {
            return
        }
        guard allGroupMembers.contains(where: { $0.role == .standard && $0.profileId == publicKey }) else {
            return SNLog("Refusing to send latest encryption key pair to non-member.")
        }
        
        // Get the latest encryption key pair
        var maybeKeyPair: ClosedGroupKeyPair? = distributingKeyPairs.wrappedValue[groupPublicKey]?.last
        
        if maybeKeyPair == nil {
            maybeKeyPair = try? closedGroup.fetchLatestKeyPair(db)
        }
        
        guard let keyPair: ClosedGroupKeyPair = maybeKeyPair else { return }
        
        // Send it
        do {
            let proto = try SNProtoKeyPair.builder(
                publicKey: keyPair.publicKey,
                privateKey: keyPair.secretKey
            ).build()
            let plaintext = try proto.serializedData()
            let thread: SessionThread = try SessionThread
                .fetchOrCreate(db, id: publicKey, variant: .contact, shouldBeVisible: nil)
            let ciphertext = try MessageSender.encryptWithSessionProtocol(
                db,
                plaintext: plaintext,
                for: publicKey
            )
            
            SNLog("Sending latest encryption key pair to: \(publicKey).")
            try MessageSender.send(
                db,
                message: ClosedGroupControlMessage(
                    kind: .encryptionKeyPair(
                        publicKey: Data(hex: groupPublicKey),
                        wrappers: [
                            ClosedGroupControlMessage.KeyPairWrapper(
                                publicKey: publicKey,
                                encryptedKeyPair: ciphertext
                            )
                        ]
                    )
                ),
                interactionId: nil,
                threadId: thread.id,
                threadVariant: thread.variant
            )
        }
        catch {}
    }
}
