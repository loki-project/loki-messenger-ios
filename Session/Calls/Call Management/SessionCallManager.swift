// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import CallKit
import GRDB
import SessionMessagingKit
import SignalCoreKit
import SignalUtilitiesKit
import SessionUtilitiesKit

public final class SessionCallManager: NSObject, CallManagerProtocol {
    let dependencies: Dependencies
    
    let provider: CXProvider?
    let callController: CXCallController?
    
    public var currentCall: CurrentCallProtocol? = nil {
        willSet {
            if (newValue != nil) {
                DispatchQueue.main.async {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            } else {
                DispatchQueue.main.async {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }
        }
    }
    
    private static var _sharedProvider: CXProvider?
    static func sharedProvider(useSystemCallLog: Bool) -> CXProvider {
        let configuration = buildProviderConfiguration(useSystemCallLog: useSystemCallLog)

        if let sharedProvider = self._sharedProvider {
            sharedProvider.configuration = configuration
            return sharedProvider
        }
        else {
            SwiftSingletons.register(self)
            let provider = CXProvider(configuration: configuration)
            _sharedProvider = provider
            return provider
        }
    }
    
    static func buildProviderConfiguration(useSystemCallLog: Bool) -> CXProviderConfiguration {
        let providerConfiguration = CXProviderConfiguration(localizedName: "Session")
        providerConfiguration.supportsVideo = true
        providerConfiguration.maximumCallGroups = 1
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportedHandleTypes = [.generic]
        let iconMaskImage = #imageLiteral(resourceName: "SessionGreen32")
        providerConfiguration.iconTemplateImageData = iconMaskImage.pngData()
        providerConfiguration.includesCallsInRecents = useSystemCallLog

        return providerConfiguration
    }
    
    // MARK: - Initialization
    
    init(useSystemCallLog: Bool = false, using dependencies: Dependencies) {
        self.dependencies = dependencies
        
        if Preferences.isCallKitSupported {
            self.provider = SessionCallManager.sharedProvider(useSystemCallLog: useSystemCallLog)
            self.callController = CXCallController()
        }
        else {
            self.provider = nil
            self.callController = nil
        }
        
        super.init()
        
        // We cannot assert singleton here, because this class gets rebuilt when the user changes relevant call settings
        self.provider?.setDelegate(self, queue: nil)
    }
    
    // MARK: - Report calls
    
    public static func reportFakeCall(info: String) {
        let callId = UUID()
        let provider = SessionCallManager.sharedProvider(useSystemCallLog: false)
        provider.reportNewIncomingCall(
            with: callId,
            update: CXCallUpdate()
        ) { _ in
            SNLog("[Calls] Reported fake incoming call to CallKit due to: \(info)")
        }
        provider.reportCall(
            with: callId,
            endedAt: nil,
            reason: .failed
        )
    }
    
    public func setCurrentCall(_ call: CurrentCallProtocol?) {
        self.currentCall = call
    }
    
    public func reportOutgoingCall(_ call: SessionCall, using dependencies: Dependencies) {
        AssertIsOnMainThread()
        dependencies[defaults: .appGroup, key: .isCallOngoing] = true
        dependencies[defaults: .appGroup, key: .lastCallPreOffer] = Date()
        
        call.stateDidChange = {
            if call.hasStartedConnecting {
                self.provider?.reportOutgoingCall(with: call.callId, startedConnectingAt: call.connectingDate)
            }
            
            if call.hasConnected {
                self.provider?.reportOutgoingCall(with: call.callId, connectedAt: call.connectedDate)
            }
        }
    }
    
    public func reportIncomingCall(
        _ call: CurrentCallProtocol,
        callerName: String,
        completion: @escaping (Error?) -> Void
    ) {
        let provider = provider ?? Self.sharedProvider(useSystemCallLog: false)
        // Construct a CXCallUpdate describing the incoming call, including the caller.
        let update = CXCallUpdate()
        update.localizedCallerName = callerName
        update.remoteHandle = CXHandle(type: .generic, value: call.callId.uuidString)
        update.hasVideo = false

        disableUnsupportedFeatures(callUpdate: update)

        // Report the incoming call to the system
        provider.reportNewIncomingCall(with: call.callId, update: update) { [dependencies] error in
            guard error == nil else {
                self.reportCurrentCallEnded(reason: .failed)
                completion(error)
                return
            }
            dependencies[defaults: .appGroup, key: .isCallOngoing] = true
            dependencies[defaults: .appGroup, key: .lastCallPreOffer] = Date()
            completion(nil)
        }
    }
    
    public func reportCurrentCallEnded(reason: CXCallEndedReason?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.reportCurrentCallEnded(reason: reason)
            }
            return
        }
        
        func handleCallEnded() {
            WebRTCSession.current = nil
            dependencies[defaults: .appGroup, key: .isCallOngoing] = false
            dependencies[defaults: .appGroup, key: .lastCallPreOffer] = nil
            
            if dependencies.hasInitialised(singleton: .appContext) && dependencies[singleton: .appContext].isInBackground {
                (UIApplication.shared.delegate as? AppDelegate)?.stopPollers()
                DDLog.flushLog()
            }
        }
        
        guard let call = currentCall else {
            handleCallEnded()
            suspendDatabaseIfCallEndedInBackground()
            return
        }
        
        if let reason = reason {
            self.provider?.reportCall(with: call.callId, endedAt: nil, reason: reason)
            
            switch (reason) {
                case .answeredElsewhere: call.updateCallMessage(mode: .answeredElsewhere, using: dependencies)
                case .unanswered: call.updateCallMessage(mode: .unanswered, using: dependencies)
                case .declinedElsewhere: call.updateCallMessage(mode: .local, using: dependencies)
                default: call.updateCallMessage(mode: .remote, using: dependencies)
            }
        }
        else {
            call.updateCallMessage(mode: .local, using: dependencies)
        }
        
        call.webRTCSession.dropConnection()
        self.currentCall = nil
        handleCallEnded()
    }
    
    // MARK: - Util
    
    private func disableUnsupportedFeatures(callUpdate: CXCallUpdate) {
        // Call Holding is failing to restart audio when "swapping" calls on the CallKit screen
        // until user returns to in-app call screen.
        callUpdate.supportsHolding = false

        // Not yet supported
        callUpdate.supportsGrouping = false
        callUpdate.supportsUngrouping = false

        // Is there any reason to support this?
        callUpdate.supportsDTMF = false
    }
    
    public func suspendDatabaseIfCallEndedInBackground() {
        if dependencies.hasInitialised(singleton: .appContext) && dependencies[singleton: .appContext].isInBackground {
            // Stop all jobs except for message sending and when completed suspend the database
            dependencies[singleton: .jobRunner].stopAndClearPendingJobs(exceptForVariant: .messageSend, using: dependencies) { [dependencies] in
                Storage.suspendDatabaseAccess(using: dependencies)
            }
        }
    }
    
    // MARK: - UI
    
    public func showCallUIForCall(caller: String, uuid: String, mode: CallMode, interactionId: Int64?) {
        guard
            let call: SessionCall = dependencies[singleton: .storage]
                .read({ [dependencies] db in
                    SessionCall(db, for: caller, uuid: uuid, mode: mode, using: dependencies)
                })
        else { return }
        
        call.callInteractionId = interactionId
        call.reportIncomingCallIfNeeded { [dependencies] error in
            if let error = error {
                SNLog("[Calls] Failed to report incoming call to CallKit due to error: \(error)")
                return
            }
            
            DispatchQueue.main.async {
                guard
                    dependencies.hasInitialised(singleton: .appContext),
                    dependencies[singleton: .appContext].isMainAppAndActive,
                    let presentingVC: UIViewController = dependencies[singleton: .appContext].frontmostViewController
                else { return }
                
                if let conversationVC: ConversationVC = presentingVC as? ConversationVC, conversationVC.viewModel.threadData.threadId == call.sessionId {
                    let callVC = CallVC(for: call, using: dependencies)
                    callVC.conversationVC = conversationVC
                    conversationVC.inputAccessoryView?.isHidden = true
                    conversationVC.inputAccessoryView?.alpha = 0
                    presentingVC.present(callVC, animated: true, completion: nil)
                }
                else if !Preferences.isCallKitSupported {
                    let incomingCallBanner = IncomingCallBanner(for: call, using: dependencies)
                    incomingCallBanner.show()
                }
            }
        }
    }
    
    public func handleAnswerMessage(_ message: CallMessage) {
        guard dependencies.hasInitialised(singleton: .appContext) else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.handleAnswerMessage(message)
            }
            return
        }
        
        (dependencies[singleton: .appContext].frontmostViewController as? CallVC)?.handleAnswerMessage(message)
    }
    
    public func dismissAllCallUI() {
        guard dependencies.hasInitialised(singleton: .appContext) else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.dismissAllCallUI()
            }
            return
        }
        
        IncomingCallBanner.current?.dismiss()
        (dependencies[singleton: .appContext].frontmostViewController as? CallVC)?.handleEndCallMessage()
        MiniCallView.current?.dismiss()
    }
}
