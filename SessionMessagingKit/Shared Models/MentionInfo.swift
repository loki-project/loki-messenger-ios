// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.
//
// stringlint:disable

import GRDB
import SessionUtilitiesKit

public struct MentionInfo: FetchableRecord, Decodable, ColumnExpressible {
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case profile
        case threadVariant
        case openGroupServer
        case openGroupRoomToken
    }
    
    public let profile: Profile
    public let threadVariant: SessionThread.Variant
    public let openGroupServer: String?
    public let openGroupRoomToken: String?
}

public extension MentionInfo {
    // stringlint:ignore_contents
    static func query(
        userPublicKey: String,
        threadId: String,
        threadVariant: SessionThread.Variant,
        targetPrefixes: [SessionId.Prefix],
        currentUserBlinded15SessionId: String?,
        currentUserBlinded25SessionId: String?,
        pattern: FTS5Pattern?
    ) -> AdaptedFetchRequest<SQLRequest<MentionInfo>>? {
        let profile: TypedTableAlias<Profile> = TypedTableAlias()
        let interaction: TypedTableAlias<Interaction> = TypedTableAlias()
        let openGroup: TypedTableAlias<OpenGroup> = TypedTableAlias()
        let groupMember: TypedTableAlias<GroupMember> = TypedTableAlias()
        let prefixesLiteral: SQLExpression = targetPrefixes
            .map { prefix in
                SQL(
                """
                (
                    \(profile[.id]) > '\(SQL(stringLiteral: "\(prefix.rawValue)"))' AND
                    \(profile[.id]) < '\(SQL(stringLiteral: "\(prefix.endOfRangeString)"))'
                )
                """)
            }
            .joined(operator: .or)
        let profileFullTextSearch: SQL = SQL(stringLiteral: Profile.fullTextSearchTableName)
        let currentUserIds: Set<String> = [
            userPublicKey,
            currentUserBlinded15SessionId,
            currentUserBlinded25SessionId
        ].compactMap { $0 }.asSet()
        
        /// The query needs to differ depending on the thread variant because the behaviour should be different:
        ///
        /// **Contact:** We should show the profile directly (filtered out if the pattern doesn't match)
        /// **Group:** We should show all profiles within the group, filtered by the pattern
        /// **Community:** We should show only the 20 most recent profiles which match the pattern
        let request: SQLRequest<MentionInfo> = {
            let hasValidPattern: Bool = (pattern != nil && pattern?.rawPattern != "\"\"*")
            let targetJoin: SQL = {
                guard hasValidPattern else { return "FROM \(Profile.self)" }
                
                return """
                    FROM \(profileFullTextSearch)
                    JOIN \(Profile.self) ON (
                        \(Profile.self).rowid = \(profileFullTextSearch).rowid AND (
                            \(SQL("\(threadVariant) != \(SessionThread.Variant.community)")) OR
                            \(prefixesLiteral)
                        )
                    )
                """
            }()
            let targetWhere: SQL = {
                guard let pattern: FTS5Pattern = pattern, pattern.rawPattern != "\"\"*" else {
                    return """
                        WHERE (
                            \(SQL("\(threadVariant) != \(SessionThread.Variant.community)")) OR
                            \(prefixesLiteral)
                        )
                    """
                }
                
                let matchLiteral: SQL = SQL(stringLiteral: "\(Profile.Columns.nickname.name):\(pattern.rawPattern) OR \(Profile.Columns.name.name):\(pattern.rawPattern)")
                
                return "WHERE \(profileFullTextSearch) MATCH '\(matchLiteral)'"
            }()
            
            switch threadVariant {
                case .contact:
                    return SQLRequest("""
                        SELECT
                            \(Profile.self).*,
                            \(SQL("\(threadVariant) AS \(MentionInfo.Columns.threadVariant)"))
                    
                        \(targetJoin)
                        \(targetWhere) AND (
                            \(SQL("\(profile[.id]) = \(threadId)")) OR
                            \(SQL("\(profile[.id]) IN \(currentUserIds)"))
                        )
                        ORDER BY \(SQL("\(profile[.id]) IN \(currentUserIds)")) DESC
                    """)
                    
                case .legacyGroup, .group:
                    return SQLRequest("""
                        SELECT
                            \(Profile.self).*,
                            \(SQL("\(threadVariant) AS \(MentionInfo.Columns.threadVariant)"))
                    
                        \(targetJoin)
                        JOIN \(GroupMember.self) ON (
                            \(SQL("\(groupMember[.groupId]) = \(threadId)")) AND
                            \(groupMember[.profileId]) = \(profile[.id]) AND
                            \(SQL("\(groupMember[.role]) != \(GroupMember.Role.zombie)"))
                        )
                        \(targetWhere)
                        GROUP BY \(profile[.id])
                        ORDER BY
                            \(SQL("\(profile[.id]) IN \(currentUserIds)")) DESC,
                            IFNULL(\(profile[.nickname]), \(profile[.name])) ASC
                    """)
                    
                case .community:
                    return SQLRequest("""
                        SELECT
                            \(Profile.self).*,
                            \(SQL("\(threadVariant) AS \(MentionInfo.Columns.threadVariant)")),
                            \(openGroup[.server]) AS \(MentionInfo.Columns.openGroupServer),
                            \(openGroup[.roomToken]) AS \(MentionInfo.Columns.openGroupRoomToken),
                            MAX(\(interaction[.timestampMs]))  -- Want the newest interaction (for sorting)
                    
                        \(targetJoin)
                        JOIN \(Interaction.self) ON (
                            \(SQL("\(interaction[.threadId]) = \(threadId)")) AND
                            \(interaction[.authorId]) = \(profile[.id])
                        )
                        JOIN \(OpenGroup.self) ON \(SQL("\(openGroup[.threadId]) = \(threadId)"))
                        \(targetWhere)
                        GROUP BY \(profile[.id])
                        ORDER BY
                            \(SQL("\(profile[.id]) IN \(currentUserIds)")) DESC,
                            \(interaction[.timestampMs].desc)
                        LIMIT 20
                    """)
            }
        }()
        
        return request.adapted { db in
            let adapters = try splittingRowAdapters(columnCounts: [
                Profile.numberOfSelectedColumns(db)
            ])
            
            return ScopeAdapter.with(MentionInfo.self, [
                .profile: adapters[0]
            ])
        }
    }
}
