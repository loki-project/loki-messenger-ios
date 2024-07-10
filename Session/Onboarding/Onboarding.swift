// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine
import GRDB
import SessionUtilitiesKit
import SessionMessagingKit
import SessionSnodeKit

// MARK: - Cache

public extension Cache {
    static let onboarding: CacheConfig<OnboardingCacheType, OnboardingImmutableCacheType> = Dependencies.create(
        identifier: "onboarding",
        createInstance: { dependencies in Onboarding.Cache(flow: .none, using: dependencies) },
        mutableInstance: { $0 },
        immutableInstance: { $0 }
    )
}

// MARK: - Onboarding

public enum Onboarding {
    public enum State: CustomStringConvertible {
        case noUser
        case noUserFailedIdentity
        case missingName
        case completed
        
        public var description: String {
            switch self {
                case .noUser: return "No User"                                  // stringlint:disable
                case .noUserFailedIdentity: return "No User Failed Identity"    // stringlint:disable
                case .missingName: return "Missing Name"                        // stringlint:disable
                case .completed: return "Completed"                             // stringlint:disable
            }
        }
    }
    
    public enum Flow {
        case none
        case register
        case loadAccount
        case link   // TODO: [GROUPS REBUILD] Remove me after onbarding merge
        case devSettings
    }
}

// MARK: - Onboarding.Cache

extension Onboarding {
    class Cache: OnboardingCacheType {
        private let dependencies: Dependencies
        public let id: UUID = UUID()
        public let initialFlow: Onboarding.Flow
        public var state: State
        private let suppressDidRegisterNotification: Bool
        
        public var seed: Data
        public var ed25519KeyPair: KeyPair
        public var x25519KeyPair: KeyPair
        public var userSessionId: SessionId
        public var useAPNS: Bool
        
        public var displayName: String
        public var _displayNamePublisher: AnyPublisher<String?, Error>?
        private var userProfileConfigMessage: ProcessedMessage?
        private var cancelable: AnyCancellable?
        
        public var displayNamePublisher: AnyPublisher<String?, Error> {
            _displayNamePublisher ?? Fail(error: NetworkError.notFound).eraseToAnyPublisher()
        }
        
        // MARK: - Initialization
        
        init(flow: Onboarding.Flow, using dependencies: Dependencies) {
            self.dependencies = dependencies
            self.initialFlow = flow
            self.suppressDidRegisterNotification = false
            
            typealias StoredData = (
                state: State,
                displayName: String,
                ed25519KeyPair: KeyPair,
                x25519KeyPair: KeyPair
            )
            let storedData: StoredData = dependencies[singleton: .storage].read { db -> StoredData in
                // If we have no ed25519KeyPair then the user doesn't have an account
                guard
                    let x25519KeyPair: KeyPair = Identity.fetchUserKeyPair(db),
                    let ed25519KeyPair: KeyPair = Identity.fetchUserEd25519KeyPair(db)
                else { return (.noUser, "", KeyPair.empty, KeyPair.empty) }
                
                // If we have no display name then collect one (this can happen if the
                // app crashed during onboarding which would leave the user in an invalid
                // state with no display name)
                let displayName: String = Profile.fetchOrCreateCurrentUser(db, using: dependencies).name
                guard !displayName.isEmpty else { return (.missingName, "Anonymous", x25519KeyPair, ed25519KeyPair) }
                
                // Otherwise we have enough for a full user and can start the app
                return (.completed, displayName, x25519KeyPair, ed25519KeyPair)
            }.defaulting(to: (.noUser, "", KeyPair.empty, KeyPair.empty))
            
            /// Store the initial `displayName` value in case we need it
            self.displayName = storedData.displayName
            
            /// Update the cached values depending on the `initialState`
            switch storedData.state {
                case .noUser, .noUserFailedIdentity:
                    /// Reset the `PushNotificationAPI` keys (just in case they were left over from a prior install)
                    PushNotificationAPI.deleteKeys(using: dependencies)
                    
                    /// Try to generate the identity data
                    guard
                        let finalSeedData: Data = dependencies[singleton: .crypto].generate(.randomBytes(16)),
                        let identity: (ed25519KeyPair: KeyPair, x25519KeyPair: KeyPair) = try? Identity.generate(
                            from: finalSeedData,
                            using: dependencies
                        )
                    else {
                        /// Seed or identity generation failed so leave the `Onboarding.Cache` in an invalid state for the UI to
                        /// recover somehow
                        self.state = .noUserFailedIdentity
                        self.seed = Data()
                        self.ed25519KeyPair = KeyPair(publicKey: [], secretKey: [])
                        self.x25519KeyPair = KeyPair(publicKey: [], secretKey: [])
                        self.userSessionId = .invalid
                        self.useAPNS = false
                        return
                    }
                    
                    /// The identity data was successfully generated so store it for the onboarding process
                    self.state = .noUser
                    self.seed = finalSeedData
                    self.ed25519KeyPair = identity.ed25519KeyPair
                    self.x25519KeyPair = identity.x25519KeyPair
                    self.userSessionId = SessionId(.standard, publicKey: x25519KeyPair.publicKey)
                    self.useAPNS = false
                    
                case .missingName, .completed:
                    self.state = storedData.state
                    self.seed = Data()
                    self.ed25519KeyPair = storedData.ed25519KeyPair
                    self.x25519KeyPair = storedData.x25519KeyPair
                    self.userSessionId = dependencies[cache: .general].sessionId
                    self.useAPNS = dependencies[defaults: .standard, key: .isUsingFullAPNs]
            }
        }
        
        /// This initializer should only be used in the `DeveloperSettingsViewModel` when swapping between network service layers
        init(
            ed25519KeyPair: KeyPair,
            x25519KeyPair: KeyPair,
            displayName: String,
            using dependencies: Dependencies
        ) {
            self.dependencies = dependencies
            self.state = .completed
            self.initialFlow = .devSettings
            self.seed = Data()
            self.ed25519KeyPair = ed25519KeyPair
            self.x25519KeyPair = x25519KeyPair
            self.userSessionId = SessionId(.standard, publicKey: x25519KeyPair.publicKey)
            self.useAPNS = dependencies[defaults: .standard, key: .isUsingFullAPNs]
            self.displayName = displayName
            self._displayNamePublisher = nil
            self.cancelable = nil
            
            /// Don't trigger the `Identity.didRegister` notification in this case
            self.suppressDidRegisterNotification = true
        }

        deinit {
            cancelable?.cancel()
        }
        
        // MARK: - Functions
        
        public func setSeedData(_ seedData: Data) throws {
            cancelable?.cancel()
            
            // Generate the keys and store them
            let identity: (ed25519KeyPair: KeyPair, x25519KeyPair: KeyPair) = try Identity.generate(
                from: seedData,
                using: dependencies
            )
            self.seed = seedData
            self.ed25519KeyPair = identity.ed25519KeyPair
            self.x25519KeyPair = identity.x25519KeyPair
            self.userSessionId = SessionId(.standard, publicKey: identity.x25519KeyPair.publicKey)
            
            /// **Note:** We trigger this as a "background poll" as doing so means the received messages will be
            /// processed immediately rather than async as part of a Job
            let poller: CurrentUserPoller = CurrentUserPoller(
                swarmPublicKey: userSessionId.hexString,
                shouldStoreMessages: false,
                logStartAndStopCalls: false,
                customAuthMethod: Authentication.standard(
                    sessionId: userSessionId,
                    ed25519KeyPair: identity.ed25519KeyPair
                ),
                drainBehaviour: .alwaysRandom,
                using: dependencies
            )

            typealias PollResult = (configMessage: ProcessedMessage, displayName: String)
            let publisher: AnyPublisher<String?, Error> = poller
                .poll(
                    namespaces: [.configUserProfile],
                    calledFromBackgroundPoller: true,
                    isBackgroundPollValid: { true }
                )
                .tryMap { [userSessionId, dependencies] messages, _, _, _ -> PollResult? in
                    guard
                        let targetMessage: ProcessedMessage = messages.last, /// Just in case there are multiple
                        case let .config(_, _, serverHash, serverTimestampMs, data) = targetMessage
                    else { return nil }
                    
                    /// In order to process the config message we need to create and load a `libSession` cache, but we don't want to load this into
                    /// memory at this stage in case the user cancels the onboarding process part way through
                    let cache: LibSession.Cache = LibSession.Cache(userSessionId: userSessionId, using: dependencies)
                    cache.loadDefaultStatesFor(
                        userConfigVariants: [.userProfile],
                        groups: [],
                        userSessionId: userSessionId,
                        userEd25519KeyPair: identity.ed25519KeyPair
                    )
                    try cache.unsafeDirectMergeConfigMessage(
                        swarmPublicKey: userSessionId.hexString,
                        messages: [
                            ConfigMessageReceiveJob.Details.MessageInfo(
                                namespace: .configUserProfile,
                                serverHash: serverHash,
                                serverTimestampMs: serverTimestampMs,
                                data: data
                            )
                        ]
                    )
                    
                    return (targetMessage, cache.userProfileDisplayName)
                }
                .handleEvents(
                    receiveOutput: { [weak self] result in
                        guard let result: PollResult = result else { return }
                        
                        /// Only store the `displayName` returned from the swarm if the user hasn't provided one in the display
                        /// name step (otherwise the user could enter a display name and have it immediately overwritten due to the
                        /// config request running slow)
                        if self?.displayName.isEmpty == true {
                            self?.displayName = result.displayName
                        }
                        
                        self?.userProfileConfigMessage = result.configMessage
                    }
                )
                .map { result -> String? in result?.displayName }
                .catch { error -> AnyPublisher<String?, Error> in
                    Log.warn("[Onboarding] Failed to retrieve existing profile information due to error: \(error).")
                    return Just(nil)
                        .setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                }
                .shareReplay(1)
                .eraseToAnyPublisher()
            
            /// Store the publisher and cancelable so we only make one request during onboarding
            _displayNamePublisher = publisher
            cancelable = publisher
                .subscribe(on: DispatchQueue.global(qos: .userInitiated), using: dependencies)
                .sink(receiveCompletion: { _ in
                    print("RAWR")
                }, receiveValue: { _ in
                    print("VDVDFV")
                })
        }
        
        func setUserAPNS(_ useAPNS: Bool) {
            self.useAPNS = useAPNS
        }
        
        func setDisplayName(_ displayName: String) {
            self.displayName = displayName
        }
        
        func completeRegistration(onComplete: @escaping (() -> Void)) {
            DispatchQueue.global(qos: .userInitiated).async(using: dependencies) { [weak self, initialFlow, userSessionId, ed25519KeyPair, x25519KeyPair, useAPNS, displayName, userProfileConfigMessage, suppressDidRegisterNotification, dependencies] in
                /// Cache the users session id (so we don't need to fetch it from the database every time)
                dependencies.mutate(cache: .general) {
                    $0.setCachedSessionId(sessionId: userSessionId)
                }
                
                /// If we had a proper `initialFlow` then create a new `libSession` cache (to ensure no previous state remains)
                if initialFlow != .none {
                    dependencies.set(
                        cache: .libSession,
                        to: LibSession.Cache(
                            userSessionId: userSessionId,
                            using: dependencies
                        )
                    )
                }
                
                dependencies[singleton: .storage].write { db in
                    /// Only update the cached state if we have a proper `initialFlow`
                    if initialFlow != .none {
                        /// Store the user identity information
                        try Identity.store(db, ed25519KeyPair: ed25519KeyPair, x25519KeyPair: x25519KeyPair)
                        
                        /// No need to show the seed again if the user is restoring or linking
                        db[.hasViewedSeed] = (initialFlow == .loadAccount || initialFlow == .link)
                        
                        /// Create a contact for the current user and set their approval/trusted statuses so they don't get weird behaviours
                        try Contact
                            .fetchOrCreate(db, id: userSessionId.hexString, using: dependencies)
                            .upsert(db)
                        try Contact
                            .filter(id: userSessionId.hexString)
                            .updateAll( /// Current user `Contact` record not synced so no need to use `updateAllAndConfig`
                                db,
                                Contact.Columns.isTrusted.set(to: true),    /// Always trust the current user
                                Contact.Columns.isApproved.set(to: true),
                                Contact.Columns.didApproveMe.set(to: true)
                            )
                        
                        /// Create the 'Note to Self' thread (not visible by default)
                        try SessionThread.fetchOrCreate(
                            db,
                            id: userSessionId.hexString,
                            variant: .contact,
                            shouldBeVisible: false,
                            calledFromConfig: nil,
                            using: dependencies
                        )
                        
                        /// Load the initial `libSession` state (won't have been created on launch due to lack of ed25519 key)
                        dependencies.mutate(cache: .libSession) {
                            $0.loadState(db)
                            
                            /// If we have a `userProfileConfigMessage` then we should try to handle it here as if we don't then
                            /// we won't even process it (because the hash may be deduped via another process)
                            if let userProfileConfigMessage: ProcessedMessage = userProfileConfigMessage {
                                try? $0.handleConfigMessages(
                                    db,
                                    swarmPublicKey: userSessionId.hexString,
                                    messages: ConfigMessageReceiveJob
                                        .Details(
                                            messages: [userProfileConfigMessage],
                                            calledFromBackgroundPoller: false
                                        )
                                        .messages
                                )
                            }
                        }
                        
                        /// Clear the `lastNameUpdate` timestamp and forcibly set the `displayName` provided during the onboarding
                        /// step (we do this after handling the config message because we want the value provided during onboarding to
                        /// superseed any retrieved from the config)
                        try Profile
                            .filter(id: userSessionId.hexString)
                            .updateAll(db, Profile.Columns.lastNameUpdate.set(to: nil))
                        try Profile.updateIfNeeded(
                            db,
                            publicKey: userSessionId.hexString,
                            name: displayName,
                            displayPictureUpdate: .none,
                            sentTimestamp: dependencies.dateNow.timeIntervalSince1970,
                            calledFromConfig: nil,
                            using: dependencies
                        )
                    }
                    
                    /// Now that everything is saved we should update the `Onboarding.Cache` `state` to be `completed`
                    self?.state = .completed
                    
                    /// We need to explicitly `updateAllAndConfig` the `shouldBeVisible` value to `false` for new accounts otherwise it
                    /// won't actually get synced correctly and could result in linking a second device and having the 'Note to Self' conversation incorrectly
                    /// being visible
                    if initialFlow == .register {
                        try SessionThread
                            .filter(id: userSessionId.hexString)
                            .updateAllAndConfig(
                                db,
                                SessionThread.Columns.shouldBeVisible.set(to: false),
                                calledFromConfig: nil,
                                using: dependencies
                            )
                    }
                }
                
                /// Store whether the user wants to use APNS
                dependencies[defaults: .standard, key: .isUsingFullAPNs] = useAPNS
                
                /// Set `hasSyncedInitialConfiguration` to true so that when we hit the home screen a configuration sync is
                /// triggered (yes, the logic is a bit weird). This is needed so that if the user registers and immediately links a device,
                /// there'll be a configuration in their swarm.
                dependencies[defaults: .standard, key: .hasSyncedInitialConfiguration] = (initialFlow == .register)
                
                /// Notify the app that registration is complete
                if !suppressDidRegisterNotification {
                    Identity.didRegister()
                }
             
                DispatchQueue.main.async(using: dependencies) {
                    onComplete()
                }
            }
        }
    }
}

// MARK: - OnboardingCacheType

/// This is a read-only version of the Cache designed to avoid unintentionally mutating the instance in a non-thread-safe way
public protocol OnboardingImmutableCacheType: ImmutableCacheType {
    var id: UUID { get }
    var state: Onboarding.State { get }
    var initialFlow: Onboarding.Flow { get }
    
    var seed: Data { get }
    var ed25519KeyPair: KeyPair { get }
    var x25519KeyPair: KeyPair { get }
    var userSessionId: SessionId { get }
    var useAPNS: Bool { get }
    
    var displayName: String { get }
    var displayNamePublisher: AnyPublisher<String?, Error> { get }
}

public protocol OnboardingCacheType: OnboardingImmutableCacheType, MutableCacheType {
    var id: UUID { get }
    var state: Onboarding.State { get }
    var initialFlow: Onboarding.Flow { get }
    
    var seed: Data { get }
    var ed25519KeyPair: KeyPair { get }
    var x25519KeyPair: KeyPair { get }
    var userSessionId: SessionId { get }
    var useAPNS: Bool { get }
    
    var displayName: String { get }
    var displayNamePublisher: AnyPublisher<String?, Error> { get }
    
    func setSeedData(_ seedData: Data) throws
    func setUserAPNS(_ useAPNS: Bool)
    func setDisplayName(_ displayName: String)
    
    /// Complete the registration process storing the created/updated user state in the database and creating
    /// the `libSession` state if needed
    ///
    /// **Note:** The `onComplete` callback will be run on the main thread
    func completeRegistration(onComplete: @escaping (() -> Void))
}

public extension OnboardingCacheType {
    func completeRegistration() { completeRegistration(onComplete: {}) }
}
