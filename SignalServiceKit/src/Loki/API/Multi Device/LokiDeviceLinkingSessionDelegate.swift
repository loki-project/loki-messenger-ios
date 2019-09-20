
@objc(LKDeviceLinkingSessionDelegate)
public protocol LokiDeviceLinkingSessionDelegate {
    
    @objc func requestUserAuthorization(for deviceLink: LokiDeviceLink)
    @objc func handleDeviceLinkingSessionTimeout()
}
