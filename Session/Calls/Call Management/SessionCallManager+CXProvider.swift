// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import AVFAudio
import CallKit
import SessionUtilitiesKit

extension SessionCallManager: CXProviderDelegate {
    public func providerDidReset(_ provider: CXProvider) {
        Log.assertOnMainThread()
        (currentCall as? SessionCall)?.endSessionCall()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        Log.assertOnMainThread()
        if startCallAction() {
            action.fulfill()
        }
        else {
            action.fail()
        }
    }
    
    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Log.assertOnMainThread()
        Log.debug("[CallKit] Perform CXAnswerCallAction")
        
        guard let call: SessionCall = (self.currentCall as? SessionCall) else { return action.fail() }
        
        if dependencies.hasInitialised(singleton: .appContext) && dependencies[singleton: .appContext].isMainAppAndActive {
            if answerCallAction() {
                action.fulfill()
            }
            else {
                action.fail()
            }
        }
        else {
            call.answerSessionCallInBackground(action: action)
        }
    }
    
    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Log.debug("[CallKit] Perform CXEndCallAction")
        Log.assertOnMainThread()
        
        if endCallAction() {
            action.fulfill()
        }
        else {
            action.fail()
        }
    }
    
    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Log.debug("[CallKit] Perform CXSetMutedCallAction, isMuted: \(action.isMuted)")
        Log.assertOnMainThread()
        
        if setMutedCallAction(isMuted: action.isMuted) {
            action.fulfill()
        }
        else {
            action.fail()
        }
    }
    
    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        // TODO: set on hold
    }
    
    public func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        // TODO: handle timeout
    }
    
    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        Log.debug("[CallKit] Audio session did activate.")
        Log.assertOnMainThread()
        guard let call: SessionCall = (self.currentCall as? SessionCall) else { return }
        
        call.webRTCSession.audioSessionDidActivate(audioSession)
        if call.isOutgoing && !call.hasConnected { CallRingTonePlayer.shared.startPlayingRingTone() }
    }
    
    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        Log.debug("[CallKit] Audio session did deactivate.")
        Log.assertOnMainThread()
        guard let call: SessionCall = (self.currentCall as? SessionCall) else { return }
        
        call.webRTCSession.audioSessionDidDeactivate(audioSession)
    }
}

