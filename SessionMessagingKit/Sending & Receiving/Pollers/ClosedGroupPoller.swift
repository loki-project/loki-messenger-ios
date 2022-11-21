// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import SessionSnodeKit
import SessionUtilitiesKit

public final class ClosedGroupPoller: Poller {
    public static var namespaces: [SnodeAPI.Namespace] = [.legacyClosedGroup]
    
    // MARK: - Settings
    
    override var namespaces: [SnodeAPI.Namespace] { ClosedGroupPoller.namespaces }
    override var maxNodePollCount: UInt { 0 }
    
    private static let minPollInterval: Double = 2
    private static let maxPollInterval: Double = 30
    

    // MARK: - Initialization
    
    public static let shared = ClosedGroupPoller()

    // MARK: - Public API
    
    public func start() {
        // Fetch all closed groups (excluding any don't contain the current user as a
        // GroupMemeber as the user is no longer a member of those)
        Storage.shared
            .read { db in
                try ClosedGroup
                    .select(.threadId)
                    .joining(
                        required: ClosedGroup.members
                            .filter(GroupMember.Columns.profileId == getUserHexEncodedPublicKey(db))
                    )
                    .asRequest(of: String.self)
                    .fetchAll(db)
            }
            .defaulting(to: [])
            .forEach { [weak self] publicKey in
                self?.startIfNeeded(for: publicKey)
            }
    }
    
    // MARK: - Abstract Methods
    
    override func pollerName(for publicKey: String) -> String {
        return "closed group with public key: \(publicKey)"
    }
    
    override func nextPollDelay(for publicKey: String) -> TimeInterval {
        // Get the received date of the last message in the thread. If we don't have
        // any messages yet, pick some reasonable fake time interval to use instead
        let lastMessageDate: Date = Storage.shared
            .read { db in
                try Interaction
                    .filter(Interaction.Columns.threadId == publicKey)
                    .select(.receivedAtTimestampMs)
                    .order(Interaction.Columns.timestampMs.desc)
                    .asRequest(of: Int64.self)
                    .fetchOne(db)
            }
            .map { receivedAtTimestampMs -> Date? in
                guard receivedAtTimestampMs > 0 else { return nil }
                
                return Date(timeIntervalSince1970: (TimeInterval(receivedAtTimestampMs) / 1000))
            }
            .defaulting(to: Date().addingTimeInterval(-5 * 60))
        
        let timeSinceLastMessage: TimeInterval = Date().timeIntervalSince(lastMessageDate)
        let minPollInterval: Double = ClosedGroupPoller.minPollInterval
        let limit: Double = (12 * 60 * 60)
        let a: TimeInterval = ((ClosedGroupPoller.maxPollInterval - minPollInterval) / limit)
        let nextPollInterval: TimeInterval = a * min(timeSinceLastMessage, limit) + minPollInterval
        SNLog("Next poll interval for closed group with public key: \(publicKey) is \(nextPollInterval) s.")
        
        return nextPollInterval
    }
    
    override func getSnodeForPolling(
        for publicKey: String,
        on queue: DispatchQueue
    ) -> Promise<Snode> {
        return SnodeAPI.getSwarm(for: publicKey)
            .map(on: queue) { swarm -> Snode in
                guard let snode: Snode = swarm.randomElement() else { throw OnionRequestAPIError.insufficientSnodes }
                
                return snode
            }
    }
    
    override func handlePollError(_ error: Error, for publicKey: String) {
        SNLog("Polling failed for closed group with public key: \(publicKey) due to error: \(error).")
        
        // Try to restart the poller from scratch
        Threading.pollerQueue.async { [weak self] in
            self?.setUpPolling(for: publicKey)
        }
    }
}
