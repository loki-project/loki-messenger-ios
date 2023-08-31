// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import CallKit
import SessionUtilitiesKit

public protocol CallManagerProtocol {
    var currentCall: CurrentCallProtocol? { get set }
    
    func reportCurrentCallEnded(reason: CXCallEndedReason?, using dependencies: Dependencies)
    
    func showCallUIForCall(caller: String, uuid: String, mode: CallMode, interactionId: Int64?)
    func handleAnswerMessage(_ message: CallMessage)
    func dismissAllCallUI()
}
