// Copyright © 2025 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

/// This migration splits the old `key` structure used for `SnodeReceivedMessageInfo` into separate columns for more efficient querying
enum _007_SplitSnodeReceivedMessageInfo: Migration {
    static let target: TargetMigrations.Identifier = .snodeKit
    static let identifier: String = "SplitSnodeReceivedMessageInfo"
    static let minExpectedRunDuration: TimeInterval = 0.1
    static let fetchedTables: [(TableRecord & FetchableRecord).Type] = [
        _001_InitialSetupMigration.LegacySnodeReceivedMessageInfo.self
    ]
    static let createdOrAlteredTables: [(TableRecord & FetchableRecord).Type] = [SnodeReceivedMessageInfo.self]
    static let droppedTables: [(TableRecord & FetchableRecord).Type] = [
        _001_InitialSetupMigration.LegacySnodeReceivedMessageInfo.self
    ]
    
    static func migrate(_ db: Database, using dependencies: Dependencies) throws {
        typealias LegacyInfo = _001_InitialSetupMigration.LegacySnodeReceivedMessageInfo
        
        /// Fetch the existing values and then drop the table
        let existingValues: [LegacyInfo] = try LegacyInfo.fetchAll(db)
        try db.drop(table: LegacyInfo.self)
        
        /// Create the new table
        try db.create(table: SnodeReceivedMessageInfo.self) { t in
            t.column(.swarmPublicKey, .text)
                .notNull()
                .indexed()
            t.column(.snodeAddress, .text).notNull()
            t.column(.namespace, .integer).notNull()
                .indexed()
            t.column(.hash, .text)
                .notNull()
                .indexed()
            t.column(.expirationDateMs, .integer)
                .notNull()
                .indexed()
            t.column(.wasDeletedOrInvalid, .boolean)
                .notNull()
                .indexed()
            
            t.primaryKey([.swarmPublicKey, .snodeAddress, .namespace, .hash])
        }
        
        /// Convert the old data to the new structure and insert it
        let timestampNowMs: Int64 = Int64(dependencies.dateNow.timeIntervalSince1970 * 1000)
        let updatedValues: [SnodeReceivedMessageInfo] = existingValues.compactMap { info in
            /// The old key was a combination of `{snode address}.{publicKey}.{namespace}`
            let keyComponents: [String] = info.key.components(separatedBy: ".") // stringlint:ignore
            
            /// Because node addresses are likely ip addresses the `keyComponents` array above may have an inconsistent length
            /// as such we need to find the swarm public key and then split again based on that value
            let maybeSwarmPublicKey: String? = {
                /// Legacy versions only included the `publicKey` which isn't supported anymore
                /// so just ignore those
                guard keyComponents.count > 2 else { return nil }
                
                /// If this wasn't associated to a `namespace` the the last value will be the `swarmPublicKey`
                guard (try? SessionId(from: keyComponents[keyComponents.count - 1])) != nil else {
                    /// Otherwise it'll be the 2nd last value
                    guard (try? SessionId(from: keyComponents[keyComponents.count - 2])) != nil else {
                        return nil
                    }
                    
                    return keyComponents[keyComponents.count - 2]
                }
                
                return keyComponents[keyComponents.count - 1]
            }()
            
            /// There was a bug in an old version of the code where it wouldn't correctly prune expired hashes so we may as well
            /// exclude them here as they just take up space otherwise
            guard
                let swarmPublicKey: String = maybeSwarmPublicKey,
                info.expirationDateMs > timestampNowMs
            else { return nil }
            
            /// Split on the `swarmPublicKey`
            let swarmPublicKeySplitComponents: [String] = info.key
                .components(separatedBy: ".\(swarmPublicKey).") // stringlint:ignore
                .filter { !$0.isEmpty }
            
            guard !swarmPublicKeySplitComponents.isEmpty else { return nil }
            
            let targetNamespace: Int = {
                guard swarmPublicKeySplitComponents.count == 2 else {
                    return SnodeAPI.Namespace.default.rawValue
                }
                
                return (Int(swarmPublicKeySplitComponents[1]) ?? SnodeAPI.Namespace.default.rawValue)
            }()
            
            return SnodeReceivedMessageInfo(
                swarmPublicKey: swarmPublicKey,
                snodeAddress: swarmPublicKeySplitComponents[0],
                namespace: targetNamespace,
                hash: info.hash,
                expirationDateMs: info.expirationDateMs,
                wasDeletedOrInvalid: (info.wasDeletedOrInvalid == true)
            )
        }
        
        try updatedValues.forEach { _ = try $0.inserted(db) }
        
        Storage.update(progress: 1, for: self, in: target, using: dependencies)
    }
}
