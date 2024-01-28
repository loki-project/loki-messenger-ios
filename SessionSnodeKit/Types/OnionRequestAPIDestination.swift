// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.
//
// stringlint:disable

import Foundation
import SessionUtilitiesKit

public enum OnionRequestAPIDestination: CustomStringConvertible, Codable {
    case snode(Snode)
    case server(host: String, target: String, x25519PublicKey: String, scheme: String?, port: UInt16?, encType: OnionRequestEncryptionType)
    
    public var description: String {
        switch self {
            case .snode(let snode): return "Service node \(snode.ip):\(snode.port)"
            case .server(let host, _, _, _, _, _): return host
        }
    }
    
    public var encryptionType: OnionRequestEncryptionType {
        switch self {
            case .snode: return .aesgcm
            case .server(_, _, _, _, _, let encType): return encType
        }
    }
}
