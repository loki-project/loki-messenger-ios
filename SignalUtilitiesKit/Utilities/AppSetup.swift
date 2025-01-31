// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUIKit
import SessionSnodeKit
import SessionMessagingKit
import SessionUtilitiesKit

public enum AppSetup {
    public static func setupEnvironment(
        additionalMigrationTargets: [MigratableTarget.Type] = [],
        appSpecificBlock: (() -> ())? = nil,
        migrationProgressChanged: ((CGFloat, TimeInterval) -> ())? = nil,
        migrationsCompletion: @escaping (Result<Void, Error>) -> (),
        using dependencies: Dependencies
    ) {
        var backgroundTask: SessionBackgroundTask? = SessionBackgroundTask(label: #function, using: dependencies)
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Order matters here.
            //
            // All of these "singletons" should have any dependencies used in their
            // initializers injected.
            dependencies[singleton: .backgroundTaskManager].startObservingNotifications()
            
            // Attachments can be stored to NSTemporaryDirectory()
            // If you receive a media message while the device is locked, the download will fail if
            // the temporary directory is NSFileProtectionComplete
            try? dependencies[singleton: .fileManager].protectFileOrFolder(
                at: NSTemporaryDirectory(),
                fileProtectionType: .completeUntilFirstUserAuthentication
            )

            SessionEnvironment.shared = SessionEnvironment(
                audioSession: OWSAudioSession(),
                proximityMonitoringManager: OWSProximityMonitoringManagerImpl(using: dependencies),
                windowManager: OWSWindowManager(default: ())
            )
            appSpecificBlock?()            
            
            runPostSetupMigrations(
                backgroundTask: backgroundTask,
                additionalMigrationTargets: additionalMigrationTargets,
                migrationProgressChanged: migrationProgressChanged,
                migrationsCompletion: migrationsCompletion,
                using: dependencies
            )
            
            // The 'if' is only there to prevent the "variable never read" warning from showing
            if backgroundTask != nil { backgroundTask = nil }
        }
    }
    
    public static func runPostSetupMigrations(
        backgroundTask: SessionBackgroundTask? = nil,
        additionalMigrationTargets: [MigratableTarget.Type] = [],
        migrationProgressChanged: ((CGFloat, TimeInterval) -> ())? = nil,
        migrationsCompletion: @escaping (Result<Void, Error>) -> (),
        using dependencies: Dependencies
    ) {
        var backgroundTask: SessionBackgroundTask? = (backgroundTask ?? SessionBackgroundTask(label: #function, using: dependencies))
        
        dependencies[singleton: .storage].perform(
            migrationTargets: additionalMigrationTargets
                .appending(contentsOf: [
                    SNUtilitiesKit.self,
                    SNSnodeKit.self,
                    SNMessagingKit.self
                ]),
            onProgressUpdate: migrationProgressChanged,
            onMigrationRequirement: { db, requirement in
                switch requirement {
                    case .sessionIdCached:
                        guard let userKeyPair: KeyPair = Identity.fetchUserKeyPair(db) else { return }
                        
                        /// Cache the users session id so we don't need to fetch it from the database every time
                        dependencies.mutate(cache: .general) {
                            $0.setCachedSessionId(sessionId: SessionId(.standard, publicKey: userKeyPair.publicKey))
                        }
                        
                    case .libSessionStateLoaded:
                        guard Identity.userExists(db, using: dependencies) else { return }
                        
                        /// After the migrations have run but before the migration completion we load the `libSession` state
                        let cache: LibSession.Cache = LibSession.Cache(
                            userSessionId: dependencies[cache: .general].sessionId,
                            using: dependencies
                        )
                        cache.loadState(db)
                        dependencies.set(cache: .libSession, to: cache)
                }
            },
            onComplete: { result in
                // Callback that the migrations have completed
                migrationsCompletion(result)
                
                // The 'if' is only there to prevent the "variable never read" warning from showing
                if backgroundTask != nil { backgroundTask = nil }
            }
        )
    }
}
