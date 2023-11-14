// Copyright © 2023 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Sodium
import SessionUtil
import SessionUtilitiesKit

import Quick
import Nimble

@testable import SessionMessagingKit

class SessionUtilSpec: QuickSpec {
    override class func spec() {
        // MARK: Configuration
        
        @TestState var dependencies: TestDependencies! = TestDependencies { dependencies in
            dependencies.dateNow = Date(timeIntervalSince1970: 1234567890)
            dependencies.forceSynchronous = true
        }
        @TestState(cache: .general, in: dependencies) var mockGeneralCache: MockGeneralCache! = MockGeneralCache(
            initialSetup: { cache in
                cache.when { $0.sessionId }.thenReturn(SessionId(.standard, hex: TestConstants.publicKey))
            }
        )
        @TestState(singleton: .storage, in: dependencies) var mockStorage: Storage! = SynchronousStorage(
            customWriter: try! DatabaseQueue(),
            migrationTargets: [
                SNUtilitiesKit.self,
                SNMessagingKit.self
            ],
            using: dependencies,
            initialData: { db in
                try Identity(variant: .x25519PublicKey, data: Data(hex: TestConstants.publicKey)).insert(db)
                try Identity(variant: .x25519PrivateKey, data: Data(hex: TestConstants.privateKey)).insert(db)
                try Identity(variant: .ed25519PublicKey, data: Data(hex: TestConstants.edPublicKey)).insert(db)
                try Identity(variant: .ed25519SecretKey, data: Data(hex: TestConstants.edSecretKey)).insert(db)
            }
        )
        @TestState(singleton: .crypto, in: dependencies) var mockCrypto: MockCrypto! = MockCrypto(
            initialSetup: { crypto in
                crypto
                    .when { crypto in crypto.generate(.ed25519KeyPair(seed: any(), using: any())) }
                    .thenReturn(
                        KeyPair(
                            publicKey: Data.data(
                                fromHex: "cbd569f56fb13ea95a3f0c05c331cc24139c0090feb412069dc49fab34406ece"
                            )!.bytes,
                            secretKey: Data.data(
                                fromHex: "0123456789abcdef0123456789abcdeffedcba9876543210fedcba9876543210" +
                                "cbd569f56fb13ea95a3f0c05c331cc24139c0090feb412069dc49fab34406ece"
                            )!.bytes
                        )
                    )
            }
        )
        @TestState(singleton: .jobRunner, in: dependencies) var mockJobRunner: MockJobRunner! = MockJobRunner(
            initialSetup: { jobRunner in
                jobRunner
                    .when { $0.add(any(), job: any(), dependantJob: any(), canStartJob: any(), using: any()) }
                    .thenReturn(nil)
            }
        )
        
        @TestState var createGroupOutput: SessionUtil.CreatedGroupInfo! = {
            mockStorage.write(using: dependencies) { db in
                 try SessionUtil.createGroup(
                    db,
                    name: "TestGroup",
                    description: nil,
                    displayPictureUrl: nil,
                    displayPictureFilename: nil,
                    displayPictureEncryptionKey: nil,
                    members: [],
                    using: dependencies
                 )
            }
        }()
        @TestState(cache: .sessionUtil, in: dependencies) var mockSessionUtilCache: MockSessionUtilCache! = MockSessionUtilCache(
            initialSetup: { cache in
                var conf: UnsafeMutablePointer<config_object>!
                var secretKey: [UInt8] = Array(Data(hex: TestConstants.edSecretKey))
                _ = user_groups_init(&conf, &secretKey, nil, 0, nil)
                
                cache.when { $0.setConfig(for: any(), sessionId: any(), to: any()) }.thenReturn(())
                cache.when { $0.config(for: .userGroups, sessionId: any()) }
                    .thenReturn(Atomic(.object(conf)))
                cache.when { $0.config(for: .groupInfo, sessionId: any()) }
                    .thenReturn(Atomic(createGroupOutput.groupState[.groupInfo]))
                cache.when { $0.config(for: .groupMembers, sessionId: any()) }
                    .thenReturn(Atomic(createGroupOutput.groupState[.groupMembers]))
                cache.when { $0.config(for: .groupKeys, sessionId: any()) }
                    .thenReturn(Atomic(createGroupOutput.groupState[.groupKeys]))
            }
        )
        @TestState var userGroupsConfig: SessionUtil.Config!
        
        // MARK: - SessionUtil
        describe("SessionUtil") {
            // MARK: -- when parsing a community url
            context("when parsing a community url") {
                // MARK: ---- handles the example urls correctly
                it("handles the example urls correctly") {
                    let validUrls: [String] = [
                        [
                            "https://sessionopengroup.co/r/main?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"
                        ],
                        [
                            "https://sessionopengroup.co/main?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"
                        ],
                        [
                            "http://sessionopengroup.co/r/main?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"
                        ],
                        [
                            "http://sessionopengroup.co/main?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"
                        ],
                        [
                            "https://143.198.213.225:443/r/main?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"
                        ],
                        [
                            "https://143.198.213.225:443/main?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"
                        ],
                        [
                            "http://143.198.213.255:80/main?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"
                        ],
                        [
                            "http://143.198.213.255:80/r/main?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"
                        ]
                    ].map { $0.joined() }
                    let processedValues: [(room: String, server: String, publicKey: String)] = validUrls
                        .map { SessionUtil.parseCommunity(url: $0) }
                        .compactMap { $0 }
                    let processedRooms: [String] = processedValues.map { $0.room }
                    let processedServers: [String] = processedValues.map { $0.server }
                    let processedPublicKeys: [String] = processedValues.map { $0.publicKey }
                    let expectedRooms: [String] = [String](repeating: "main", count: 8)
                    let expectedServers: [String] = [
                        "https://sessionopengroup.co",
                        "https://sessionopengroup.co",
                        "http://sessionopengroup.co",
                        "http://sessionopengroup.co",
                        "https://143.198.213.225",
                        "https://143.198.213.225",
                        "http://143.198.213.255",
                        "http://143.198.213.255"
                    ]
                    let expectedPublicKeys: [String] = [String](
                        repeating: "658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c",
                        count: 8
                    )
                    
                    expect(processedValues.count).to(equal(validUrls.count))
                    expect(processedRooms).to(equal(expectedRooms))
                    expect(processedServers).to(equal(expectedServers))
                    expect(processedPublicKeys).to(equal(expectedPublicKeys))
                }

                // MARK: ---- handles the r prefix if present
                it("handles the r prefix if present") {
                    let info = SessionUtil.parseCommunity(
                        url: [
                            "https://sessionopengroup.co/r/main?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"
                        ].joined()
                    )
                    
                    expect(info?.room).to(equal("main"))
                    expect(info?.server).to(equal("https://sessionopengroup.co"))
                    expect(info?.publicKey).to(equal("658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"))
                }

                // MARK: ---- fails if no scheme is provided
                it("fails if no scheme is provided") {
                    let info = SessionUtil.parseCommunity(
                        url: [
                            "sessionopengroup.co/r/main?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"
                        ].joined()
                    )
                    
                    expect(info?.room).to(beNil())
                    expect(info?.server).to(beNil())
                    expect(info?.publicKey).to(beNil())
                }
                
                // MARK: ---- fails if there is no room
                it("fails if there is no room") {
                    let info = SessionUtil.parseCommunity(
                        url: [
                            "https://sessionopengroup.co?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"
                        ].joined()
                    )
                    
                    expect(info?.room).to(beNil())
                    expect(info?.server).to(beNil())
                    expect(info?.publicKey).to(beNil())
                }
                
                // MARK: ---- fails if there is no public key parameter
                it("fails if there is no public key parameter") {
                    let info = SessionUtil.parseCommunity(
                        url: "https://sessionopengroup.co/r/main"
                    )
                    
                    expect(info?.room).to(beNil())
                    expect(info?.server).to(beNil())
                    expect(info?.publicKey).to(beNil())
                }
                
                // MARK: ---- fails if the public key parameter is not 64 characters
                it("fails if the public key parameter is not 64 characters") {
                    let info = SessionUtil.parseCommunity(
                        url: [
                            "https://sessionopengroup.co/r/main?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231"
                        ].joined()
                    )
                    
                    expect(info?.room).to(beNil())
                    expect(info?.server).to(beNil())
                    expect(info?.publicKey).to(beNil())
                }
                
                // MARK: ---- fails if the public key parameter is not a hex string
                it("fails if the public key parameter is not a hex string") {
                    let info = SessionUtil.parseCommunity(
                        url: [
                            "https://sessionopengroup.co/r/main?",
                            "public_key=!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
                        ].joined()
                    )
                    
                    expect(info?.room).to(beNil())
                    expect(info?.server).to(beNil())
                    expect(info?.publicKey).to(beNil())
                }
                
                // MARK: ---- maintains the same TLS
                it("maintains the same TLS") {
                    let server1 = SessionUtil.parseCommunity(
                        url: [
                            "http://sessionopengroup.co/r/main?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"
                        ].joined()
                    )?.server
                    let server2 = SessionUtil.parseCommunity(
                        url: [
                            "https://sessionopengroup.co/r/main?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"
                        ].joined()
                    )?.server
                    
                    expect(server1).to(equal("http://sessionopengroup.co"))
                    expect(server2).to(equal("https://sessionopengroup.co"))
                }
                
                // MARK: ---- maintains the same port
                it("maintains the same port") {
                    let server1 = SessionUtil.parseCommunity(
                        url: [
                            "https://sessionopengroup.co/r/main?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"
                        ].joined()
                    )?.server
                    let server2 = SessionUtil.parseCommunity(
                        url: [
                            "https://sessionopengroup.co:1234/r/main?",
                            "public_key=658d29b91892a2389505596b135e76a53db6e11d613a51dbd3d0816adffb231c"
                        ].joined()
                    )?.server
                    
                    expect(server1).to(equal("https://sessionopengroup.co"))
                    expect(server2).to(equal("https://sessionopengroup.co:1234"))
                }
            }
            
            // MARK: -- when generating a url
            context("when generating a url") {
                // MARK: ---- generates the url correctly
                it("generates the url correctly") {
                    expect(SessionUtil.communityUrlFor(server: "server", roomToken: "room", publicKey: "f8fec9b701000000ffffffff0400008000000000000000000000000000000000"))
                        .to(equal("server/room?public_key=f8fec9b701000000ffffffff0400008000000000000000000000000000000000"))
                }
                
                // MARK: ---- maintains the casing provided
                it("maintains the casing provided") {
                    expect(SessionUtil.communityUrlFor(server: "SeRVer", roomToken: "RoOM", publicKey: "f8fec9b701000000ffffffff0400008000000000000000000000000000000000"))
                        .to(equal("SeRVer/RoOM?public_key=f8fec9b701000000ffffffff0400008000000000000000000000000000000000"))
                }
            }
            
            // MARK: -- when creating a group
            context("when creating a group") {
                beforeEach {
                    var userGroupsConf: UnsafeMutablePointer<config_object>!
                    var secretKey: [UInt8] = Array(Data(hex: TestConstants.edSecretKey))
                    _ = user_groups_init(&userGroupsConf, &secretKey, nil, 0, nil)
                    userGroupsConfig = .object(userGroupsConf)
                    
                    mockSessionUtilCache
                        .when { $0.config(for: .userGroups, sessionId: any()) }
                        .thenReturn(Atomic(userGroupsConfig))
                }
                
                // MARK: ---- throws when there is no user ed25519 keyPair
                it("throws when there is no user ed25519 keyPair") {
                    var resultError: Error? = nil
                    
                    mockStorage.write { db in
                        try Identity.filter(id: .ed25519PublicKey).deleteAll(db)
                        try Identity.filter(id: .ed25519SecretKey).deleteAll(db)
                        
                        do {
                            _ = try SessionUtil.createGroup(
                                db,
                                name: "Testname",
                                description: nil,
                                displayPictureUrl: nil,
                                displayPictureFilename: nil,
                                displayPictureEncryptionKey: nil,
                                members: [],
                                using: dependencies
                            )
                        }
                        catch { resultError = error }
                    }
                    
                    expect(resultError).to(matchError(MessageSenderError.noKeyPair))
                }
                
                // MARK: ---- throws when it fails to generate a new identity ed25519 keyPair
                it("throws when it fails to generate a new identity ed25519 keyPair") {
                    var resultError: Error? = nil
                    
                    mockCrypto
                        .when { $0.generate(.ed25519KeyPair(seed: any(), using: any())) }
                        .thenReturn(nil)
                    
                    mockStorage.write { db in
                        do {
                            _ = try SessionUtil.createGroup(
                                db,
                                name: "Testname",
                                description: nil,
                                displayPictureUrl: nil,
                                displayPictureFilename: nil,
                                displayPictureEncryptionKey: nil,
                                members: [],
                                using: dependencies
                            )
                        }
                        catch { resultError = error }
                    }
                    
                    expect(resultError).to(matchError(MessageSenderError.noKeyPair))
                }
                
                // MARK: ---- throws when given an invalid member id
                it("throws when given an invalid member id") {
                    var resultError: Error? = nil
                    
                    mockStorage.write { db in
                        do {
                            _ = try SessionUtil.createGroup(
                                db,
                                name: "Testname",
                                description: nil,
                                displayPictureUrl: nil,
                                displayPictureFilename: nil,
                                displayPictureEncryptionKey: nil,
                                members: [(
                                    id: "123456",
                                    profile: Profile(
                                        id: "123456",
                                        name: ""
                                    )
                                )],
                                using: dependencies
                            )
                        }
                        catch { resultError = error }
                    }
                    
                    expect(resultError).to(matchError(
                        NSError(
                            domain: "cpp_exception",
                            code: -2,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Invalid session ID: expected 66 hex digits starting with 05; got 123456"
                            ]
                        )
                    ))
                }
                
                // MARK: ---- returns the correct identity keyPair
                it("returns the correct identity keyPair") {
                    createGroupOutput = mockStorage.write(using: dependencies) { db in
                        try SessionUtil.createGroup(
                            db,
                            name: "Testname",
                            description: nil,
                            displayPictureUrl: nil,
                            displayPictureFilename: nil,
                            displayPictureEncryptionKey: nil,
                            members: [],
                            using: dependencies
                        )
                    }
                    
                    expect(createGroupOutput.identityKeyPair.publicKey.toHexString())
                        .to(equal("cbd569f56fb13ea95a3f0c05c331cc24139c0090feb412069dc49fab34406ece"))
                    expect(createGroupOutput.identityKeyPair.secretKey.toHexString())
                        .to(equal(
                            "0123456789abcdef0123456789abcdeffedcba9876543210fedcba9876543210" +
                            "cbd569f56fb13ea95a3f0c05c331cc24139c0090feb412069dc49fab34406ece"
                        ))
                }
                
                // MARK: ---- returns a closed group with the correct data set
                it("returns a closed group with the correct data set") {
                    createGroupOutput = mockStorage.write(using: dependencies) { db in
                        try SessionUtil.createGroup(
                            db,
                            name: "Testname",
                            description: nil,
                            displayPictureUrl: "TestUrl",
                            displayPictureFilename: "TestFilename",
                            displayPictureEncryptionKey: Data([1, 2, 3]),
                            members: [],
                            using: dependencies
                        )
                    }
                    
                    expect(createGroupOutput.group.threadId)
                        .to(equal("03cbd569f56fb13ea95a3f0c05c331cc24139c0090feb412069dc49fab34406ece"))
                    expect(createGroupOutput.group.groupIdentityPrivateKey?.toHexString())
                        .to(equal(
                            "0123456789abcdef0123456789abcdeffedcba9876543210fedcba9876543210" +
                            "cbd569f56fb13ea95a3f0c05c331cc24139c0090feb412069dc49fab34406ece"
                        ))
                    expect(createGroupOutput.group.name).to(equal("Testname"))
                    expect(createGroupOutput.group.displayPictureUrl).to(equal("TestUrl"))
                    expect(createGroupOutput.group.displayPictureFilename).to(equal("TestFilename"))
                    expect(createGroupOutput.group.displayPictureEncryptionKey).to(equal(Data([1, 2, 3])))
                    expect(createGroupOutput.group.formationTimestamp).to(equal(1234567890))
                    expect(createGroupOutput.group.invited).to(beFalse())
                }
                
                // MARK: ---- returns the members setup correctly
                it("returns the members setup correctly") {
                    createGroupOutput = mockStorage.write(using: dependencies) { db in
                        try SessionUtil.createGroup(
                            db,
                            name: "Testname",
                            description: nil,
                            displayPictureUrl: nil,
                            displayPictureFilename: nil,
                            displayPictureEncryptionKey: nil,
                            members: [(
                                id: "051111111111111111111111111111111111111111111111111111111111111111",
                                profile: Profile(
                                    id: "051111111111111111111111111111111111111111111111111111111111111111",
                                    name: "TestName",
                                    profilePictureUrl: "testUrl",
                                    profileEncryptionKey: Data([1, 2, 3])
                                )
                            )],
                            using: dependencies
                        )
                    }
                    
                    expect(createGroupOutput.members.count).to(equal(2))
                    expect(createGroupOutput.members.map { $0.groupId })
                        .to(equal([
                            "03cbd569f56fb13ea95a3f0c05c331cc24139c0090feb412069dc49fab34406ece",
                            "03cbd569f56fb13ea95a3f0c05c331cc24139c0090feb412069dc49fab34406ece",
                        ]))
                    expect(createGroupOutput.members.map { $0.profileId }.asSet())
                        .to(equal([
                            "051111111111111111111111111111111111111111111111111111111111111111",
                            "05\(TestConstants.publicKey)"
                        ]))
                    expect(createGroupOutput.members.map { $0.role }.asSet())
                        .to(equal([
                            .standard,
                            .admin
                        ]))
                    expect(createGroupOutput.members.map { $0.isHidden }.asSet())
                        .to(equal([
                            false,
                            false
                        ]))
                }
                
                // MARK: ---- adds the current user as an admin when not provided
                it("adds the current user as an admin when not provided") {
                    createGroupOutput = mockStorage.write(using: dependencies) { db in
                        try SessionUtil.createGroup(
                            db,
                            name: "Testname",
                            description: nil,
                            displayPictureUrl: nil,
                            displayPictureFilename: nil,
                            displayPictureEncryptionKey: nil,
                            members: [(
                                id: "051111111111111111111111111111111111111111111111111111111111111111",
                                profile: Profile(
                                    id: "051111111111111111111111111111111111111111111111111111111111111111",
                                    name: "TestName"
                                )
                            )],
                            using: dependencies
                        )
                    }
                    
                    expect(createGroupOutput.members.map { $0.groupId })
                        .to(contain("03cbd569f56fb13ea95a3f0c05c331cc24139c0090feb412069dc49fab34406ece"))
                    expect(createGroupOutput.members.map { $0.profileId })
                        .to(contain("05\(TestConstants.publicKey)"))
                    expect(createGroupOutput.members.map { $0.role }).to(contain(.admin))
                }
                
                // MARK: ---- handles members without profile data correctly
                it("handles members without profile data correctly") {
                    createGroupOutput = mockStorage.write(using: dependencies) { db in
                        try SessionUtil.createGroup(
                            db,
                            name: "Testname",
                            description: nil,
                            displayPictureUrl: nil,
                            displayPictureFilename: nil,
                            displayPictureEncryptionKey: nil,
                            members: [(
                                id: "051111111111111111111111111111111111111111111111111111111111111111",
                                profile: nil
                            )],
                            using: dependencies
                        )
                    }
                    
                    expect(createGroupOutput.members.count).to(equal(2))
                    expect(createGroupOutput.members.map { $0.groupId })
                        .to(contain("03cbd569f56fb13ea95a3f0c05c331cc24139c0090feb412069dc49fab34406ece"))
                    expect(createGroupOutput.members.map { $0.profileId })
                        .to(contain("051111111111111111111111111111111111111111111111111111111111111111"))
                    expect(createGroupOutput.members.map { $0.role }).to(contain(.standard))
                }
                
                // MARK: ---- stores the config states in the cache correctly
                it("stores the config states in the cache correctly") {
                    createGroupOutput = mockStorage.write(using: dependencies) { db in
                        try SessionUtil.createGroup(
                            db,
                            name: "Testname",
                            description: nil,
                            displayPictureUrl: nil,
                            displayPictureFilename: nil,
                            displayPictureEncryptionKey: nil,
                            members: [(
                                id: "051111111111111111111111111111111111111111111111111111111111111111",
                                profile: nil
                            )],
                            using: dependencies
                        )
                    }
                    
                    expect(mockSessionUtilCache).to(call(.exactly(times: 3)) {
                        $0.setConfig(for: any(), sessionId: any(), to: any())
                    })
                    expect(mockSessionUtilCache)
                        .to(call(matchingParameters: .atLeast(2)) {
                            $0.setConfig(
                                for: .groupInfo,
                                sessionId: SessionId(
                                    .group,
                                    hex: "cbd569f56fb13ea95a3f0c05c331cc24139c0090feb412069dc49fab34406ece"
                                ),
                                to: any()
                            )
                        })
                    expect(mockSessionUtilCache)
                        .to(call(matchingParameters: .atLeast(2)) {
                            $0.setConfig(
                                for: .groupMembers,
                                sessionId: SessionId(
                                    .group,
                                    hex: "cbd569f56fb13ea95a3f0c05c331cc24139c0090feb412069dc49fab34406ece"
                                ),
                                to: any()
                            )
                        })
                    expect(mockSessionUtilCache)
                        .to(call(matchingParameters: .atLeast(2)) {
                            $0.setConfig(
                                for: .groupKeys,
                                sessionId: SessionId(
                                    .group,
                                    hex: "cbd569f56fb13ea95a3f0c05c331cc24139c0090feb412069dc49fab34406ece"
                                ),
                                to: any()
                            )
                        })
                }
            }
            
            // MARK: -- when saving a created a group
            context("when saving a created a group") {
                // MARK: ---- saves config dumps for the stored configs
                it("saves config dumps for the stored configs") {
                    mockStorage.write(using: dependencies) { db in
                        createGroupOutput = try SessionUtil.createGroup(
                            db,
                            name: "Testname",
                            description: nil,
                            displayPictureUrl: nil,
                            displayPictureFilename: nil,
                            displayPictureEncryptionKey: nil,
                            members: [(
                                id: "051111111111111111111111111111111111111111111111111111111111111111",
                                profile: nil
                            )],
                            using: dependencies
                        )
                        
                        try SessionUtil.saveCreatedGroup(
                            db,
                            group: createGroupOutput.group,
                            groupState: createGroupOutput.groupState,
                            using: dependencies
                        )
                    }
                    
                    let result: [ConfigDump]? = mockStorage.read(using: dependencies) { db in
                        try ConfigDump.fetchAll(db)
                    }
                    
                    expect(result?.map { $0.variant }.asSet())
                        .to(contain([.groupInfo, .groupKeys, .groupMembers]))
                    expect(result?.map { $0.sessionId }.asSet())
                        .to(contain([
                            SessionId(
                                .group,
                                hex: "cbd569f56fb13ea95a3f0c05c331cc24139c0090feb412069dc49fab34406ece"
                            )
                        ]))
                    expect(result?.map { $0.timestampMs }.asSet())
                        .to(contain([1234567890000]))
                }
                
                // MARK: ---- adds the group to the user groups config
                it("adds the group to the user groups config") {
                    mockStorage.write(using: dependencies) { db in
                        createGroupOutput = try SessionUtil.createGroup(
                            db,
                            name: "Testname",
                            description: nil,
                            displayPictureUrl: nil,
                            displayPictureFilename: nil,
                            displayPictureEncryptionKey: nil,
                            members: [(
                                id: "051111111111111111111111111111111111111111111111111111111111111111",
                                profile: nil
                            )],
                            using: dependencies
                        )
                        
                        try SessionUtil.saveCreatedGroup(
                            db,
                            group: createGroupOutput.group,
                            groupState: createGroupOutput.groupState,
                            using: dependencies
                        )
                    }
                    
                    let result: [ConfigDump]? = mockStorage.read(using: dependencies) { db in
                        try ConfigDump.fetchAll(db)
                    }
                    
                    expect(result?.map { $0.variant }.asSet()).to(contain([.userGroups]))
                    expect(result?.map { $0.timestampMs }.asSet()).to(contain([1234567890000]))
                }
            }
            
            // MARK: -- when receiving a GROUP_INFO update
            context("when receiving a GROUP_INFO update") {
                @TestState var latestGroup: ClosedGroup?
                @TestState var initialDisappearingConfig: DisappearingMessagesConfiguration?
                @TestState var latestDisappearingConfig: DisappearingMessagesConfiguration?
                
                beforeEach {
                    mockStorage.write(using: dependencies) { db in
                        try SessionThread.fetchOrCreate(
                            db,
                            id: createGroupOutput.group.threadId,
                            variant: .group,
                            shouldBeVisible: true,
                            calledFromConfigHandling: false,
                            using: dependencies
                        )
                        try createGroupOutput.group.insert(db)
                        try createGroupOutput.members.forEach { try $0.insert(db) }
                        initialDisappearingConfig = try DisappearingMessagesConfiguration
                            .fetchOne(db, id: createGroupOutput.group.threadId)
                            .defaulting(
                                to: DisappearingMessagesConfiguration.defaultWith(createGroupOutput.group.threadId)
                            )
                    }
                }
                
                // MARK: ---- does nothing if there are no changes
                it("does nothing if there are no changes") {
                    dependencies.setMockableValue(key: "needsDump", false)
                    
                    mockStorage.write(using: dependencies) { db in
                        try SessionUtil.handleGroupInfoUpdate(
                            db,
                            in: createGroupOutput.groupState[.groupInfo],
                            groupSessionId: SessionId(.group, hex: createGroupOutput.group.threadId),
                            serverTimestampMs: 1234567891000,
                            using: dependencies
                        )
                    }
                    
                    latestGroup = mockStorage.read(using: dependencies) { db in
                        try ClosedGroup.fetchOne(db, id: createGroupOutput.group.threadId)
                    }
                    expect(createGroupOutput.groupState[.groupInfo]).toNot(beNil())
                    expect(createGroupOutput.group).to(equal(latestGroup))
                }
                
                // MARK: ---- throws if the config is invalid
                it("throws if the config is invalid") {
                    dependencies.setMockableValue(key: "needsDump", true)
                    
                    mockStorage.write(using: dependencies) { db in
                        expect {
                            try SessionUtil.handleGroupInfoUpdate(
                                db,
                                in: .invalid,
                                groupSessionId: SessionId(.group, hex: createGroupOutput.group.threadId),
                                serverTimestampMs: 1234567891000,
                                using: dependencies
                            )
                        }
                        .to(throwError())
                    }
                }
                
                // MARK: ---- removes group data if the group is destroyed
                it("removes group data if the group is destroyed") {
                    createGroupOutput.groupState[.groupInfo]?.conf.map { groups_info_destroy_group($0) }
                    dependencies.setMockableValue(key: "needsDump", true)
                    
                    mockStorage.write(using: dependencies) { db in
                        try SessionUtil.handleGroupInfoUpdate(
                            db,
                            in: createGroupOutput.groupState[.groupInfo],
                            groupSessionId: SessionId(.group, hex: createGroupOutput.group.threadId),
                            serverTimestampMs: 1234567891000,
                            using: dependencies
                        )
                    }
                    
                    latestGroup = mockStorage.read(using: dependencies) { db in
                        try ClosedGroup.fetchOne(db, id: createGroupOutput.group.threadId)
                    }
                    expect(latestGroup?.authData).to(beNil())
                    expect(latestGroup?.groupIdentityPrivateKey).to(beNil())
                }
                
                // MARK: ---- updates the name if it changed
                it("updates the name if it changed") {
                    createGroupOutput.groupState[.groupInfo]?.conf.map {
                        var updatedName: [CChar] = "UpdatedName".cArray.nullTerminated()
                        groups_info_set_name($0, &updatedName)
                    }
                    dependencies.setMockableValue(key: "needsDump", true)
                    
                    mockStorage.write(using: dependencies) { db in
                        try SessionUtil.handleGroupInfoUpdate(
                            db,
                            in: createGroupOutput.groupState[.groupInfo],
                            groupSessionId: SessionId(.group, hex: createGroupOutput.group.threadId),
                            serverTimestampMs: 1234567891000,
                            using: dependencies
                        )
                    }
                    
                    latestGroup = mockStorage.read(using: dependencies) { db in
                        try ClosedGroup.fetchOne(db, id: createGroupOutput.group.threadId)
                    }
                    expect(createGroupOutput.group.name).to(equal("TestGroup"))
                    expect(latestGroup?.name).to(equal("UpdatedName"))
                }
                
                // MARK: ---- updates the description if it changed
                it("updates the description if it changed") {
                    createGroupOutput.groupState[.groupInfo]?.conf.map {
                        var updatedDesc: [CChar] = "UpdatedDesc".cArray.nullTerminated()
                        groups_info_set_description($0, &updatedDesc)
                    }
                    dependencies.setMockableValue(key: "needsDump", true)
                    
                    mockStorage.write(using: dependencies) { db in
                        try SessionUtil.handleGroupInfoUpdate(
                            db,
                            in: createGroupOutput.groupState[.groupInfo],
                            groupSessionId: SessionId(.group, hex: createGroupOutput.group.threadId),
                            serverTimestampMs: 1234567891000,
                            using: dependencies
                        )
                    }
                    
                    latestGroup = mockStorage.read(using: dependencies) { db in
                        try ClosedGroup.fetchOne(db, id: createGroupOutput.group.threadId)
                    }
                    expect(createGroupOutput.group.groupDescription).to(beNil())
                    expect(latestGroup?.groupDescription).to(equal("UpdatedDesc"))
                }
                
                // MARK: ---- updates the formation timestamp if it changed
                it("updates the formation timestamp if it changed") {
                    createGroupOutput.groupState[.groupInfo]?.conf.map { groups_info_set_created($0, 54321) }
                    dependencies.setMockableValue(key: "needsDump", true)
                    
                    mockStorage.write(using: dependencies) { db in
                        try SessionUtil.handleGroupInfoUpdate(
                            db,
                            in: createGroupOutput.groupState[.groupInfo],
                            groupSessionId: SessionId(.group, hex: createGroupOutput.group.threadId),
                            serverTimestampMs: 1234567891000,
                            using: dependencies
                        )
                    }
                    
                    latestGroup = mockStorage.read(using: dependencies) { db in
                        try ClosedGroup.fetchOne(db, id: createGroupOutput.group.threadId)
                    }
                    expect(createGroupOutput.group.formationTimestamp).to(equal(1234567890))
                    expect(latestGroup?.formationTimestamp).to(equal(54321))
                }
                
                // MARK: ---- and the display picture was changed
                context("and the display picture was changed") {
                    // MARK: ------ removes the display picture
                    it("removes the display picture") {
                        mockStorage.write(using: dependencies) { db in
                            try ClosedGroup
                                .updateAll(
                                    db,
                                    ClosedGroup.Columns.displayPictureUrl.set(to: "TestUrl"),
                                    ClosedGroup.Columns.displayPictureEncryptionKey.set(to: Data([1, 2, 3])),
                                    ClosedGroup.Columns.displayPictureFilename.set(to: "TestFilename")
                                )
                        }
                        dependencies.setMockableValue(key: "needsDump", true)
                        
                        mockStorage.write(using: dependencies) { db in
                            try SessionUtil.handleGroupInfoUpdate(
                                db,
                                in: createGroupOutput.groupState[.groupInfo],
                                groupSessionId: SessionId(.group, hex: createGroupOutput.group.threadId),
                                serverTimestampMs: 1234567891000,
                                using: dependencies
                            )
                        }
                        
                        latestGroup = mockStorage.read(using: dependencies) { db in
                            try ClosedGroup.fetchOne(db, id: createGroupOutput.group.threadId)
                        }
                        expect(latestGroup?.displayPictureUrl).to(beNil())
                        expect(latestGroup?.displayPictureEncryptionKey).to(beNil())
                        expect(latestGroup?.displayPictureFilename).to(beNil())
                        expect(latestGroup?.lastDisplayPictureUpdate).to(equal(1234567891))
                    }
                    
                    // MARK: ------ schedules a display picture download job if there is a new one
                    it("schedules a display picture download job if there is a new one") {
                        createGroupOutput.groupState[.groupInfo]?.conf.map {
                            var displayPic: user_profile_pic = user_profile_pic()
                            displayPic.url = "https://www.oxen.io/file/1234".toLibSession()
                            displayPic.key = Data(
                                repeating: 1,
                                count: DisplayPictureManager.aes256KeyByteLength
                            ).toLibSession()
                            groups_info_set_pic($0, displayPic)
                        }
                        dependencies.setMockableValue(key: "needsDump", true)
                        
                        mockStorage.write(using: dependencies) { db in
                            try SessionUtil.handleGroupInfoUpdate(
                                db,
                                in: createGroupOutput.groupState[.groupInfo],
                                groupSessionId: SessionId(.group, hex: createGroupOutput.group.threadId),
                                serverTimestampMs: 1234567891000,
                                using: dependencies
                            )
                        }
                        
                        expect(mockJobRunner)
                            .to(call(.exactly(times: 1), matchingParameters: .all) { jobRunner in
                                jobRunner.add(
                                    any(),
                                    job: Job(
                                        variant: .displayPictureDownload,
                                        behaviour: .runOnce,
                                        shouldBlock: false,
                                        shouldBeUnique: true,
                                        shouldSkipLaunchBecomeActive: false,
                                        details: DisplayPictureDownloadJob.Details(
                                            target: .group(
                                                id: createGroupOutput.group.threadId,
                                                url: "https://www.oxen.io/file/1234",
                                                encryptionKey: Data(
                                                    repeating: 1,
                                                    count: DisplayPictureManager.aes256KeyByteLength
                                                )
                                            ),
                                            timestamp: 1234567891
                                        )
                                    ),
                                    canStartJob: true,
                                    using: any()
                                )
                            })
                    }
                }
                
                // MARK: ---- updates the disappearing messages config
                it("updates the disappearing messages config") {
                    createGroupOutput.groupState[.groupInfo]?.conf.map { groups_info_set_expiry_timer($0, 10) }
                    dependencies.setMockableValue(key: "needsDump", true)
                    
                    mockStorage.write(using: dependencies) { db in
                        try SessionUtil.handleGroupInfoUpdate(
                            db,
                            in: createGroupOutput.groupState[.groupInfo],
                            groupSessionId: SessionId(.group, hex: createGroupOutput.group.threadId),
                            serverTimestampMs: 1234567891000,
                            using: dependencies
                        )
                    }
                    
                    latestDisappearingConfig = mockStorage.read(using: dependencies) { db in
                        try DisappearingMessagesConfiguration.fetchOne(db, id: createGroupOutput.group.threadId)
                    }
                    expect(initialDisappearingConfig?.isEnabled).to(beFalse())
                    expect(initialDisappearingConfig?.durationSeconds).to(equal(0))
                    expect(latestDisappearingConfig?.isEnabled).to(beTrue())
                    expect(latestDisappearingConfig?.durationSeconds).to(equal(10))
                }
            }
        }
    }
}

// MARK: - Convenience

private extension SessionUtil.Config {
    var conf: UnsafeMutablePointer<config_object>? {
        switch self {
            case .object(let conf): return conf
            default: return nil
        }
    }
}
