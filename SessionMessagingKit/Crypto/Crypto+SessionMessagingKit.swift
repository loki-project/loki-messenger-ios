// Copyright © 2023 Rangeproof Pty Ltd. All rights reserved.
//
// stringlint:disable

import Foundation
import GRDB
import SessionUtil
import SessionUtilitiesKit

// MARK: - Encryption

public extension Crypto.Generator {
    static func ciphertextWithSessionProtocol(
        _ db: Database,
        plaintext: Data,
        destination: Message.Destination,
        using dependencies: Dependencies
    ) -> Crypto.Generator<Data> {
        return Crypto.Generator(
            id: "ciphertextWithSessionProtocol",
            args: [plaintext, destination]
        ) {
            let ed25519KeyPair: KeyPair = try Identity.fetchUserEd25519KeyPair(db) ?? {
                throw MessageSenderError.noUserED25519KeyPair
            }()
            let destinationX25519PublicKey: Data = try {
                switch destination {
                    case .contact(let publicKey): return Data(SessionId(.standard, hex: publicKey).publicKey)
                    case .closedGroup(let groupPublicKey):
                        return try ClosedGroupKeyPair.fetchLatestKeyPair(db, threadId: groupPublicKey)?.publicKey ?? {
                            throw MessageSenderError.noKeyPair
                        }()

                    default: throw MessageSenderError.signingFailed
                }
            }()

            var cPlaintext: [UInt8] = Array(plaintext)
            var cEd25519SecretKey: [UInt8] = ed25519KeyPair.secretKey
            var cDestinationPubKey: [UInt8] = Array(destinationX25519PublicKey)
            var maybeCiphertext: UnsafeMutablePointer<UInt8>? = nil
            var ciphertextLen: Int = 0

            guard
                cEd25519SecretKey.count == 64,
                cDestinationPubKey.count == 32,
                session_encrypt_for_recipient_deterministic(
                    &cPlaintext,
                    cPlaintext.count,
                    &cEd25519SecretKey,
                    &cDestinationPubKey,
                    &maybeCiphertext,
                    &ciphertextLen
                ),
                ciphertextLen > 0,
                let ciphertext: Data = maybeCiphertext.map({ Data(bytes: $0, count: ciphertextLen) })
            else { throw MessageSenderError.encryptionFailed }

            maybeCiphertext?.deallocate()

            return ciphertext
        }
    }

    static func ciphertextWithMultiEncrypt(
        messages: [Data],
        toRecipients recipients: [SessionId],
        ed25519PrivateKey: [UInt8],
        domain: LibSession.Crypto.Domain
    ) -> Crypto.Generator<Data> {
        return Crypto.Generator(
            id: "ciphertextWithMultiEncrypt",
            args: [messages, recipients, ed25519PrivateKey, domain]
        ) {
            var outLen: Int = 0
            var cMessages: [UnsafePointer<UInt8>?] = (try? (messages
                .map { message -> [UInt8] in Array(message) }
                .unsafeCopyUInt8Array()))
                .defaulting(to: [])
            var messageSizes: [Int] = messages.map { $0.count }
            var cRecipients: [UnsafePointer<UInt8>?] = (try? (recipients
                .map { recipient -> [UInt8] in recipient.publicKey }
                .unsafeCopyUInt8Array()))
                .defaulting(to: [])
            var secretKey: [UInt8] = ed25519PrivateKey
            var cEncryptedDataPtr: UnsafeMutablePointer<UInt8>? = session_encrypt_for_multiple_simple_ed25519(
                &outLen,
                &cMessages,
                &messageSizes,
                messages.count,
                &cRecipients,
                recipients.count,
                &secretKey,
                domain.cString(using: .utf8),
                nil,
                0
            )

            let encryptedData: Data? = cEncryptedDataPtr.map { Data(bytes: $0, count: outLen) }
            cMessages.forEach { $0?.deallocate() }
            cRecipients.forEach { $0?.deallocate() }
            cEncryptedDataPtr?.deallocate()

            return try encryptedData ?? { throw MessageSenderError.encryptionFailed }()
        }
    }
}

// MARK: - Decryption

public extension Crypto.Generator {
    static func plaintextWithSessionProtocol(
        _ db: Database,
        ciphertext: Data,
        using dependencies: Dependencies
    ) -> Crypto.Generator<(plaintext: Data, senderSessionIdHex: String)> {
        return Crypto.Generator(
            id: "plaintextWithSessionProtocol",
            args: [ciphertext]
        ) {
            let ed25519KeyPair: KeyPair = try Identity.fetchUserEd25519KeyPair(db) ?? {
                throw MessageSenderError.noUserED25519KeyPair
            }()

            var cCiphertext: [UInt8] = Array(ciphertext)
            var cEd25519SecretKey: [UInt8] = ed25519KeyPair.secretKey
            var cSenderSessionId: [CChar] = [CChar](repeating: 0, count: 67)
            var maybePlaintext: UnsafeMutablePointer<UInt8>? = nil
            var plaintextLen: Int = 0

            guard
                cEd25519SecretKey.count == 64,
                session_decrypt_incoming(
                    &cCiphertext,
                    cCiphertext.count,
                    &cEd25519SecretKey,
                    &cSenderSessionId,
                    &maybePlaintext,
                    &plaintextLen
                ),
                plaintextLen > 0,
                let plaintext: Data = maybePlaintext.map({ Data(bytes: $0, count: plaintextLen) })
            else { throw MessageReceiverError.decryptionFailed }

            maybePlaintext?.deallocate()

            return (plaintext, String(cString: cSenderSessionId))
        }
    }

    static func plaintextWithSessionProtocolLegacyGroup(
        ciphertext: Data,
        keyPair: KeyPair,
        using dependencies: Dependencies
    ) -> Crypto.Generator<(plaintext: Data, senderSessionIdHex: String)> {
        return Crypto.Generator(
            id: "plaintextWithSessionProtocol",
            args: [ciphertext]
        ) {
            var cCiphertext: [UInt8] = Array(ciphertext)
            var cX25519Pubkey: [UInt8] = keyPair.publicKey
            var cX25519Seckey: [UInt8] = keyPair.secretKey
            var cSenderSessionId: [CChar] = [CChar](repeating: 0, count: 67)
            var maybePlaintext: UnsafeMutablePointer<UInt8>? = nil
            var plaintextLen: Int = 0

            guard
                cX25519Pubkey.count == 32,
                cX25519Seckey.count == 32,
                session_decrypt_incoming_legacy_group(
                    &cCiphertext,
                    cCiphertext.count,
                    &cX25519Pubkey,
                    &cX25519Seckey,
                    &cSenderSessionId,
                    &maybePlaintext,
                    &plaintextLen
                ),
                plaintextLen > 0,
                let plaintext: Data = maybePlaintext.map({ Data(bytes: $0, count: plaintextLen) })
            else { throw MessageReceiverError.decryptionFailed }

            maybePlaintext?.deallocate()

            return (plaintext, String(cString: cSenderSessionId))
        }
    }

    static func plaintextWithPushNotificationPayload(
        payload: Data,
        encKey: Data
    ) -> Crypto.Generator<Data> {
        return Crypto.Generator(
            id: "plaintextWithPushNotificationPayload",
            args: [payload, encKey]
        ) {
            var cPayload: [UInt8] = Array(payload)
            var cEncKey: [UInt8] = Array(encKey)
            var maybePlaintext: UnsafeMutablePointer<UInt8>? = nil
            var plaintextLen: Int = 0

            guard
                cEncKey.count == 32,
                session_decrypt_push_notification(
                    &cPayload,
                    cPayload.count,
                    &cEncKey,
                    &maybePlaintext,
                    &plaintextLen
                ),
                plaintextLen > 0,
                let plaintext: Data = maybePlaintext.map({ Data(bytes: $0, count: plaintextLen) })
            else { throw MessageReceiverError.decryptionFailed }

            maybePlaintext?.deallocate()

            return plaintext
        }
    }

    static func plaintextWithMultiEncrypt(
        ciphertext: Data,
        senderSessionId: SessionId,
        ed25519PrivateKey: [UInt8],
        domain: LibSession.Crypto.Domain
    ) -> Crypto.Generator<Data> {
        return Crypto.Generator(
            id: "plaintextWithMultiEncrypt",
            args: [ciphertext, senderSessionId, ed25519PrivateKey, domain]
        ) {
            var outLen: Int = 0
            var cEncryptedData: [UInt8] = Array(ciphertext)
            var cEd25519PrivateKey: [UInt8] = ed25519PrivateKey
            var cSenderPubkey: [UInt8] = senderSessionId.publicKey
            var cDecryptedDataPtr: UnsafeMutablePointer<UInt8>? = session_decrypt_for_multiple_simple_ed25519(
                &outLen,
                &cEncryptedData,
                cEncryptedData.count,
                &cEd25519PrivateKey,
                &cSenderPubkey,
                domain.cString(using: .utf8)
            )

            let decryptedData: Data? = cDecryptedDataPtr.map { Data(bytes: $0, count: outLen) }
            cDecryptedDataPtr?.deallocate()

            return try decryptedData ?? { throw MessageReceiverError.decryptionFailed }()
        }
    }
}
