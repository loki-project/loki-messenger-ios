import SessionUtilitiesKit
import Sodium

public final class ClosedGroupControlMessage : ControlMessage {
    public var kind: Kind?

    public override var ttl: UInt64 {
        switch kind {
        case .encryptionKeyPair: return 14 * 24 * 60 * 60 * 1000
        default: return 14 * 24 * 60 * 60 * 1000
        }
    }
    
    public override var isSelfSendValid: Bool { true }
    
    // MARK: Kind
    public enum Kind : CustomStringConvertible {
        case new(publicKey: Data, name: String, x25519KeyPair: ECKeyPair, members: [Data], admins: [Data], expirationTimer: UInt32, ed25519KeyPair: Sign.KeyPair?)
        /// The group x25519 and ed25519 encryption key pairs encrypted for each member individually.
        ///
        /// - Note: `publicKey` is only set when an encryption key pair is sent in a one-to-one context (i.e. not in a group).
        case encryptionKeyPair(publicKey: Data?, wrappers: [KeyPairWrapper])
        case nameChange(name: String)
        case membersAdded(members: [Data])
        case membersRemoved(members: [Data])
        case memberLeft
        case encryptionKeyPairRequest

        public var description: String {
            switch self {
            case .new: return "new"
            case .encryptionKeyPair: return "encryptionKeyPair"
            case .nameChange: return "nameChange"
            case .membersAdded: return "membersAdded"
            case .membersRemoved: return "membersRemoved"
            case .memberLeft: return "memberLeft"
            case .encryptionKeyPairRequest: return "encryptionKeyPairRequest"
            }
        }
    }

    // MARK: Key Pair Wrapper
    @objc(SNKeyPairWrapper)
    public final class KeyPairWrapper : NSObject, NSCoding { // NSObject/NSCoding conformance is needed for YapDatabase compatibility
        public var publicKey: String?
        public var encryptedX25519KeyPair: Data?
        public var encryptedED25519KeyPair: Data?

        public var isValid: Bool { publicKey != nil && encryptedX25519KeyPair != nil }

        public init(publicKey: String, encryptedX25519KeyPair: Data, encryptedED25519KeyPair: Data?) {
            self.publicKey = publicKey
            self.encryptedX25519KeyPair = encryptedX25519KeyPair
            self.encryptedED25519KeyPair = encryptedED25519KeyPair
        }

        public required init?(coder: NSCoder) {
            if let publicKey = coder.decodeObject(forKey: "publicKey") as! String? { self.publicKey = publicKey }
            if let encryptedX25519KeyPair = coder.decodeObject(forKey: "encryptedKeyPair") as! Data? { self.encryptedX25519KeyPair = encryptedX25519KeyPair }
            if let encryptedED25519KeyPair = coder.decodeObject(forKey: "encryptedED25519KeyPair") as! Data? { self.encryptedED25519KeyPair = encryptedED25519KeyPair }
        }

        public func encode(with coder: NSCoder) {
            coder.encode(publicKey, forKey: "publicKey")
            coder.encode(encryptedX25519KeyPair, forKey: "encryptedKeyPair")
            coder.encode(encryptedED25519KeyPair, forKey: "encryptedED25519KeyPair")
        }

        public static func fromProto(_ proto: SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper) -> KeyPairWrapper? {
            return KeyPairWrapper(publicKey: proto.publicKey.toHexString(), encryptedX25519KeyPair: proto.x25519, encryptedED25519KeyPair: proto.ed25519)
        }

        public func toProto() -> SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper? {
            guard let publicKey = publicKey, let encryptedX25519KeyPair = encryptedX25519KeyPair else { return nil }
            let result = SNProtoDataMessageClosedGroupControlMessageKeyPairWrapper.builder(publicKey: Data(hex: publicKey), x25519: encryptedX25519KeyPair)
            if let encryptedED25519KeyPair = encryptedED25519KeyPair { result.setEd25519(encryptedED25519KeyPair) }
            do {
                return try result.build()
            } catch {
                SNLog("Couldn't construct key pair wrapper proto from: \(self).")
                return nil
            }
        }
    }

    // MARK: Initialization
    public override init() { super.init() }

    internal init(kind: Kind) {
        super.init()
        self.kind = kind
    }

    // MARK: Validation
    public override var isValid: Bool {
        guard super.isValid, let kind = kind else { return false }
        switch kind {
        case .new(let publicKey, let name, let encryptionKeyPair, let members, let admins, _, _):
            return !publicKey.isEmpty && !name.isEmpty && !encryptionKeyPair.publicKey.isEmpty
                && !encryptionKeyPair.privateKey.isEmpty && !members.isEmpty && !admins.isEmpty
        case .encryptionKeyPair: return true
        case .nameChange(let name): return !name.isEmpty
        case .membersAdded(let members): return !members.isEmpty
        case .membersRemoved(let members): return !members.isEmpty
        case .memberLeft: return true
        case .encryptionKeyPairRequest: return true
        }
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        guard let rawKind = coder.decodeObject(forKey: "kind") as? String else { return nil }
        switch rawKind {
        case "new":
            guard let publicKey = coder.decodeObject(forKey: "publicKey") as? Data,
                let name = coder.decodeObject(forKey: "name") as? String,
                let x25519KeyPair = coder.decodeObject(forKey: "encryptionKeyPair") as? ECKeyPair,
                let members = coder.decodeObject(forKey: "members") as? [Data],
                let admins = coder.decodeObject(forKey: "admins") as? [Data] else { return nil }
            let expirationTimer = coder.decodeObject(forKey: "expirationTimer") as? UInt32 ?? 0
            let ed25519KeyPair = coder.decodeObject(forKey: "ed25519KeyPair") as? Sign.KeyPair
            self.kind = .new(publicKey: publicKey, name: name, x25519KeyPair: x25519KeyPair, members: members, admins: admins, expirationTimer: expirationTimer, ed25519KeyPair: ed25519KeyPair)
        case "encryptionKeyPair":
            let publicKey = coder.decodeObject(forKey: "publicKey") as? Data
            guard let wrappers = coder.decodeObject(forKey: "wrappers") as? [KeyPairWrapper] else { return nil }
            self.kind = .encryptionKeyPair(publicKey: publicKey, wrappers: wrappers)
        case "nameChange":
            guard let name = coder.decodeObject(forKey: "name") as? String else { return nil }
            self.kind = .nameChange(name: name)
        case "membersAdded":
            guard let members = coder.decodeObject(forKey: "members") as? [Data] else { return nil }
            self.kind = .membersAdded(members: members)
        case "membersRemoved":
            guard let members = coder.decodeObject(forKey: "members") as? [Data] else { return nil }
            self.kind = .membersRemoved(members: members)
        case "memberLeft":
            self.kind = .memberLeft
        case "encryptionKeyPairRequest":
            self.kind = .encryptionKeyPairRequest
        default: return nil
        }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        guard let kind = kind else { return }
        switch kind {
        case .new(let publicKey, let name, let encryptionKeyPair, let members, let admins, let expirationTimer, let ed25519KeyPair):
            coder.encode("new", forKey: "kind")
            coder.encode(publicKey, forKey: "publicKey")
            coder.encode(name, forKey: "name")
            coder.encode(encryptionKeyPair, forKey: "encryptionKeyPair")
            coder.encode(members, forKey: "members")
            coder.encode(admins, forKey: "admins")
            coder.encode(expirationTimer, forKey: "expirationTimer")
            coder.encode(ed25519KeyPair, forKey: "ed25519KeyPair")
        case .encryptionKeyPair(let publicKey, let wrappers):
            coder.encode("encryptionKeyPair", forKey: "kind")
            coder.encode(publicKey, forKey: "publicKey")
            coder.encode(wrappers, forKey: "wrappers")
        case .nameChange(let name):
            coder.encode("nameChange", forKey: "kind")
            coder.encode(name, forKey: "name")
        case .membersAdded(let members):
            coder.encode("membersAdded", forKey: "kind")
            coder.encode(members, forKey: "members")
        case .membersRemoved(let members):
            coder.encode("membersRemoved", forKey: "kind")
            coder.encode(members, forKey: "members")
        case .memberLeft:
            coder.encode("memberLeft", forKey: "kind")
        case .encryptionKeyPairRequest:
            coder.encode("encryptionKeyPairRequest", forKey: "kind")
        }
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> ClosedGroupControlMessage? {
        guard let closedGroupControlMessageProto = proto.dataMessage?.closedGroupControlMessage else { return nil }
        let kind: Kind
        switch closedGroupControlMessageProto.type {
        case .new:
            guard let publicKey = closedGroupControlMessageProto.publicKey, let name = closedGroupControlMessageProto.name,
                let x25519KeyPairAsProto = closedGroupControlMessageProto.x25519 else { return nil }
            let expirationTimer = closedGroupControlMessageProto.expirationTimer
            do {
                let x25519KeyPair = try ECKeyPair(publicKeyData: x25519KeyPairAsProto.publicKey.removing05PrefixIfNeeded(), privateKeyData: x25519KeyPairAsProto.privateKey)
                var ed25519KeyPair: Sign.KeyPair? = nil
                if let ed25519 = closedGroupControlMessageProto.ed25519 {
                    ed25519KeyPair = Sign.KeyPair(publicKey: Bytes(ed25519.publicKey), secretKey: Bytes(ed25519.privateKey))
                }
                kind = .new(publicKey: publicKey, name: name, x25519KeyPair: x25519KeyPair,
                    members: closedGroupControlMessageProto.members, admins: closedGroupControlMessageProto.admins, expirationTimer: expirationTimer, ed25519KeyPair: ed25519KeyPair)
            } catch {
                SNLog("Couldn't parse key pair.")
                return nil
            }
        case .encryptionKeyPair:
            let publicKey = closedGroupControlMessageProto.publicKey
            let wrappers = closedGroupControlMessageProto.wrappers.compactMap { KeyPairWrapper.fromProto($0) }
            kind = .encryptionKeyPair(publicKey: publicKey, wrappers: wrappers)
        case .nameChange:
            guard let name = closedGroupControlMessageProto.name else { return nil }
            kind = .nameChange(name: name)
        case .membersAdded:
            kind = .membersAdded(members: closedGroupControlMessageProto.members)
        case .membersRemoved:
            kind = .membersRemoved(members: closedGroupControlMessageProto.members)
        case .memberLeft:
            kind = .memberLeft
        case .encryptionKeyPairRequest:
            kind = .encryptionKeyPairRequest
        }
        return ClosedGroupControlMessage(kind: kind)
    }

    public override func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        guard let kind = kind else {
            SNLog("Couldn't construct closed group update proto from: \(self).")
            return nil
        }
        do {
            let closedGroupControlMessage: SNProtoDataMessageClosedGroupControlMessage.SNProtoDataMessageClosedGroupControlMessageBuilder
            switch kind {
            case .new(let publicKey, let name, let x25519KeyPair, let members, let admins, let expirationTimer, let ed25519KeyPair):
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .new)
                closedGroupControlMessage.setPublicKey(publicKey)
                closedGroupControlMessage.setName(name)
                let x25519KeyPairAsProto = SNProtoKeyPair.builder(publicKey: x25519KeyPair.publicKey, privateKey: x25519KeyPair.privateKey)
                do {
                    closedGroupControlMessage.setX25519(try x25519KeyPairAsProto.build())
                    if let ed25519KeyPair = ed25519KeyPair {
                        let ed25519KeyPairAsProto = try SNProtoKeyPair.builder(publicKey: Data(ed25519KeyPair.publicKey), privateKey: Data(ed25519KeyPair.secretKey)).build()
                        closedGroupControlMessage.setEd25519(ed25519KeyPairAsProto)
                    }
                } catch {
                    SNLog("Couldn't construct closed group update proto from: \(self).")
                    return nil
                }
                closedGroupControlMessage.setMembers(members)
                closedGroupControlMessage.setAdmins(admins)
                closedGroupControlMessage.setExpirationTimer(expirationTimer)
            case .encryptionKeyPair(let publicKey, let wrappers):
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .encryptionKeyPair)
                if let publicKey = publicKey {
                    closedGroupControlMessage.setPublicKey(publicKey)
                }
                closedGroupControlMessage.setWrappers(wrappers.compactMap { $0.toProto() })
            case .nameChange(let name):
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .nameChange)
                closedGroupControlMessage.setName(name)
            case .membersAdded(let members):
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .membersAdded)
                closedGroupControlMessage.setMembers(members)
            case .membersRemoved(let members):
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .membersRemoved)
                closedGroupControlMessage.setMembers(members)
            case .memberLeft:
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .memberLeft)
            case .encryptionKeyPairRequest:
                closedGroupControlMessage = SNProtoDataMessageClosedGroupControlMessage.builder(type: .encryptionKeyPairRequest)
            }
            let contentProto = SNProtoContent.builder()
            let dataMessageProto = SNProtoDataMessage.builder()
            dataMessageProto.setClosedGroupControlMessage(try closedGroupControlMessage.build())
            // Group context
            try setGroupContextIfNeeded(on: dataMessageProto, using: transaction)
            contentProto.setDataMessage(try dataMessageProto.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct closed group update proto from: \(self).")
            return nil
        }
    }

    // MARK: Description
    public override var description: String {
        """
        ClosedGroupControlMessage(
            kind: \(kind?.description ?? "null")
        )
        """
    }
}
