// Copyright © 2025 Rangeproof Pty Ltd. All rights reserved.

import AVFAudio

public enum Permissions {
    
    public enum MicrophonePermisson {
        case denied
        case granted
        case undetermined
        case unknown
    }
    
    public static var microphone: MicrophonePermisson {
        if #available(iOSApplicationExtension 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
                case .undetermined:
                    return .undetermined
                case .denied:
                    return .denied
                case .granted:
                    return .granted
                @unknown default:
                    return .unknown
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
                case .undetermined:
                    return .undetermined
                case .denied:
                    return .denied
                case .granted:
                    return .granted
                @unknown default:
                    return .unknown
            }
        }
    }
}
