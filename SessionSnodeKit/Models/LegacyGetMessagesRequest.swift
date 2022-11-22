// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension SnodeAPI {
    /// This is the legacy unauthenticated message retrieval request
    public struct LegacyGetMessagesRequest: Encodable {
        enum CodingKeys: String, CodingKey {
            case pubkey
            case lastHash = "last_hash"
            case namespace
        }
        
        let pubkey: String
        let lastHash: String
        let namespace: SnodeAPI.Namespace?
        
        // MARK: - Coding
        
        public func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(pubkey, forKey: .pubkey)
            try container.encode(lastHash, forKey: .lastHash)
            try container.encodeIfPresent(namespace, forKey: .namespace)
        }
    }
}
