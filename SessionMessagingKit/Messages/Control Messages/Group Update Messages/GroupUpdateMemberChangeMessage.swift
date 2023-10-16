// Copyright © 2023 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public final class GroupUpdateMemberChangeMessage: ControlMessage {
    private enum CodingKeys: String, CodingKey {
        case changeType
        case memberPublicKeys
    }
    
    public enum ChangeType: Int, Codable {
        case added = 1
        case removed = 2
        case promoted = 3
    }
    
    public var changeType: ChangeType
    public var memberPublicKeys: [Data]
    
    // MARK: - Initialization
    
    public init(
        changeType: ChangeType,
        memberPublicKeys: [Data],
        sentTimestamp: UInt64? = nil
    ) {
        self.changeType = changeType
        self.memberPublicKeys = memberPublicKeys
        
        super.init(
            sentTimestamp: sentTimestamp
        )
    }
    
    // MARK: - Codable
    
    required init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        changeType = try container.decode(ChangeType.self, forKey: .changeType)
        memberPublicKeys = try container.decode([Data].self, forKey: .memberPublicKeys)
        
        try super.init(from: decoder)
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(changeType, forKey: .changeType)
        try container.encode(memberPublicKeys, forKey: .memberPublicKeys)
    }

    // MARK: - Proto Conversion
    
    public override class func fromProto(_ proto: SNProtoContent, sender: String) -> GroupUpdateMemberChangeMessage? {
        guard
            let groupMemberChangeMessage = proto.dataMessage?.groupUpdateMessage?.memberChangeMessage,
            let changeType: ChangeType = ChangeType(rawValue: Int(groupMemberChangeMessage.type.rawValue))
        else { return nil }
        
        
        return GroupUpdateMemberChangeMessage(
            changeType: changeType,
            memberPublicKeys: groupMemberChangeMessage.memberPublicKeys
        )
    }

    public override func toProto(_ db: Database, threadId: String) -> SNProtoContent? {
        do {
            let memberChangeMessageBuilder: SNProtoGroupUpdateMemberChangeMessage.SNProtoGroupUpdateMemberChangeMessageBuilder = SNProtoGroupUpdateMemberChangeMessage.builder(
                type: {
                    switch changeType {
                        case .added: return .added
                        case .removed: return .removed
                        case .promoted: return .promoted
                    }
                }()
            )
            
            memberChangeMessageBuilder.setMemberPublicKeys(memberPublicKeys)
            
            let groupUpdateMessage = SNProtoGroupUpdateMessage.builder()
            groupUpdateMessage.setMemberChangeMessage(try memberChangeMessageBuilder.build())
            
            let dataMessage = SNProtoDataMessage.builder()
            dataMessage.setGroupUpdateMessage(try groupUpdateMessage.build())
            
            let contentProto = SNProtoContent.builder()
            contentProto.setDataMessage(try dataMessage.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct data extraction notification proto from: \(self).")
            return nil
        }
    }

    // MARK: - Description
    
    public var description: String {
        """
        GroupUpdateMemberChangeMessage(
            changeType: \(changeType),
            memberPublicKeys: \(memberPublicKeys.map { $0.toHexString() })
        )
        """
    }
}
