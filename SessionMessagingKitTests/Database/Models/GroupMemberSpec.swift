// Copyright © 2025 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

import Quick
import Nimble

@testable import SessionMessagingKit

class GroupMemberSpec: QuickSpec {
    override class func spec() {
        // MARK: - a GroupMember
        describe("a GroupMember") {
            // MARK: -- when ProfileAssociated
            context("when ProfileAssociated") {
                // MARK: ---- is sorted correctly
                it("is sorted correctly") {
                    let userSessionId: SessionId = SessionId(.standard, hex: TestConstants.publicKey)
                    var members: [WithProfile<GroupMember>] = (0..<100).map { index in
                        WithProfile(
                            value: GroupMember(
                                groupId: "TestGroupId",
                                profileId: "05_(Id\(index < 10 ? "0" : "")\(index))",
                                role: .standard,
                                roleStatus: .accepted,
                                isHidden: false
                            ),
                            profile: Profile(
                                id: "05_(Id\(index < 10 ? "0" : "")\(index))",
                                name: "Name\(index < 10 ? "0" : "")\(index)"
                            ),
                            currentUserSessionId: userSessionId
                        )
                    }
                    
                    // Update some names so that we can test the name sorting (case, special chars
                    // non-english, etc.)
                    members.with(1, name: "Test3")
                    members.with(2, name: "zName")
                    members.with(3, name: "test2")
                    members.with(4, name: "$#@$Name")
                    members.with(5, name: "TeSt1")
                    members.with(6, name: "BName")
                    members.with(7, name: "⽇")
                    members.with(8, name: "⽉")
                    
                    // Provide a bunch of different statuses
                    var statusRandomGenerator: ARC4RandomNumberGenerator = ARC4RandomNumberGenerator(seed: 1234)
                    let remainingMembers: Double = Double(members.count - 10)
                    let numberOfStatuses: Int = Int(floor(remainingMembers / Double(GroupMember.RoleStatus.allCases.count)))
                    let allStatuses: [GroupMember.RoleStatus] = GroupMember.RoleStatus.allCases
                        .duplicated(count: numberOfStatuses)
                        .shuffled(using: &statusRandomGenerator)
                    allStatuses.enumerated().forEach { index, status in
                        members.with(10 + index, roleStatus: status)
                    }
                    
                    // Make a bunch of the users admins
                    (40..<80).forEach { index in
                        members.with(index, role: .admin)
                    }
                    
                    // Remove some profiles so we can check those
                    (80..<90).forEach { index in
                        members.with(index, removedProfile: true)
                    }
                    
                    // Make a few of them the current user to check where they get placed
                    members.with(20, profileId: userSessionId.hexString, name: "You1")
                    members.with(50, profileId: userSessionId.hexString, name: "You2")
                    members.with(70, profileId: userSessionId.hexString, name: "You3")
                    members.with(95, profileId: userSessionId.hexString, name: "You4")
                    members.with(98, profileId: userSessionId.hexString, name: "You5")
                    
                    // Sort the members and check that the values are in the expected orders
                    let sortedMembers: [WithProfile<GroupMember>] = members.sorted()
                    expect(sortedMembers.map { $0.profile?.name ?? $0.profileId }).to(equal([
                        "05_(Id87)", "Name15", "Name18", "05_(Id81)", "05_(Id84)",
                        "Name91", "Name93", "05_(Id80)", "05_(Id82)", "05_(Id89)",
                        "05_(Id86)", "05_(Id83)", "05_(Id88)", "Name90", "Name40",
                        "Name44", "Name45", "Name48", "Name49", "Name57",
                        "Name60", "Name61", "Name67", "Name10", "Name17",
                        "Name19", "Name23", "Name26", "Name33", "Name39",
                        "Name63", "Name64", "Name68", "Name72", "Name76",
                        "Name32", "Name38", "Name43", "Name55", "Name59",
                        "Name73", "Name75", "Name79", "Name11", "Name16",
                        "Name22", "Name28", "Name31", "Name36", "Name53",
                        "Name54", "Name77", "You1", "Name21", "Name25",
                        "Name30", "Name34", "Name41", "Name51", "Name62",
                        "Name65", "Name66", "Name74", "Name12", "Name24",
                        "Name27", "Name29", "Name35", "You2", "Name56",
                        "Name58", "Name71", "You3", "Name42", "Name46",
                        "Name47", "Name52", "Name69", "Name78", "You4",
                        "You5", "05_(Id85)", "$#@$Name", "BName", "Name00",
                        "Name09", "Name13", "Name14", "Name37", "Name92",
                        "Name94", "Name96", "Name97", "Name99", "TeSt1",
                        "test2", "Test3", "zName", "⽇", "⽉"
                    ]))
                    expect(sortedMembers.map { $0.value.role }).to(equal([
                        .standard, .standard, .standard, .standard, .standard,
                        .standard, .standard, .standard, .standard, .standard,
                        .standard, .standard, .standard, .standard, .admin,
                        .admin, .admin, .admin, .admin, .admin,
                        .admin, .admin, .admin, .standard, .standard,
                        .standard, .standard, .standard, .standard, .standard,
                        .admin, .admin, .admin, .admin, .admin,
                        .standard, .standard, .admin, .admin, .admin,
                        .admin, .admin, .admin, .standard, .standard,
                        .standard, .standard, .standard, .standard, .admin,
                        .admin, .admin, .standard, .standard, .standard,
                        .standard, .standard, .admin, .admin, .admin,
                        .admin, .admin, .admin, .standard, .standard,
                        .standard, .standard, .standard, .admin, .admin,
                        .admin, .admin, .admin, .admin, .admin,
                        .admin, .admin, .admin, .admin, .standard,
                        .standard, .standard, .standard, .standard, .standard,
                        .standard, .standard, .standard, .standard, .standard,
                        .standard, .standard, .standard, .standard, .standard,
                        .standard, .standard, .standard, .standard, .standard
                    ]))
                    expect(sortedMembers.map { $0.value.roleStatus }).to(equal([
                        .failed, .failed, .failed, .sending, .sending,
                        .sending, .sending, .pending, .pending, .pending,
                        .unknown, .pendingRemoval, .pendingRemoval, .pendingRemoval, .failed,
                        .failed, .failed, .failed, .failed, .failed,
                        .failed, .failed, .failed, .notSentYet, .notSentYet,
                        .notSentYet, .notSentYet, .notSentYet, .notSentYet, .notSentYet,
                        .notSentYet, .notSentYet, .notSentYet, .notSentYet, .notSentYet,
                        .sending, .sending, .sending, .sending, .sending,
                        .sending, .sending, .sending, .pending, .pending,
                        .pending, .pending, .pending, .pending, .pending,
                        .pending, .pending, .unknown, .unknown, .unknown,
                        .unknown, .unknown, .unknown, .unknown, .unknown,
                        .unknown, .unknown, .unknown, .pendingRemoval, .pendingRemoval,
                        .pendingRemoval, .pendingRemoval, .pendingRemoval, .pendingRemoval, .pendingRemoval,
                        .pendingRemoval, .pendingRemoval, .accepted, .accepted, .accepted,
                        .accepted, .accepted, .accepted, .accepted, .accepted,
                        .accepted, .accepted, .accepted, .accepted, .accepted,
                        .accepted, .accepted, .accepted, .accepted, .accepted,
                        .accepted, .accepted, .accepted, .accepted, .accepted,
                        .accepted, .accepted, .accepted, .accepted, .accepted
                    ]))
                    
                    let indexesOfCurrentUser: [Int] = sortedMembers.enumerated().reduce(into: []) { result, next in
                        guard next.element.profileId == userSessionId.hexString else { return }
                        
                        result.append(next.offset)
                    }
                    expect(indexesOfCurrentUser).to(equal([
                        52, 68, 72, 79, 80
                    ]))
                }
            }
        }
    }
}

// MARK: - Convenience

private extension Array {
    func duplicated(count: Int) -> [Element] {
        guard count > 1 else { return self }
        
        var updated: [Element] = self
        (0..<(count - 1)).forEach { _ in updated += self }
        
        return updated
    }
}

private extension Array where Element == WithProfile<GroupMember> {
    mutating func with(
        _ index: Int,
        profileId: String? = nil,
        name: String? = nil,
        removedProfile: Bool = false,
        role: GroupMember.Role? = nil,
        roleStatus: GroupMember.RoleStatus? = nil
    ) {
        let current: WithProfile<GroupMember> = self[index]
        
        self[index] = WithProfile(
            value: GroupMember(
                groupId: "TestGroupId",
                profileId: (profileId ?? current.profileId),
                role: (role ?? current.value.role),
                roleStatus: (roleStatus ?? current.value.roleStatus),
                isHidden: false
            ),
            profile: (removedProfile ? nil :
                current.profile.map { currentProfile in
                    Profile(
                        id: (profileId ?? current.profileId),
                        name: (name ?? currentProfile.name)
                    )
                }
            ),
            currentUserSessionId: current.currentUserSessionId
        )
    }
}
