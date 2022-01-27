//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc public class OWSAlerts: NSObject {

    /// Cleanup and present alert for no permissions
    @objc
    public class func showNoMicrophonePermissionAlert() {
        let alertTitle = NSLocalizedString("CALL_AUDIO_PERMISSION_TITLE", comment: "Alert title when calling and permissions for microphone are missing")
        let alertMessage = NSLocalizedString("CALL_AUDIO_PERMISSION_MESSAGE", comment: "Alert message when calling and permissions for microphone are missing")
        let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)

        let dismissAction = UIAlertAction(title: CommonStrings.dismissButton, style: .cancel)
        dismissAction.accessibilityIdentifier = "OWSAlerts.\("dismiss")"
        alert.addAction(dismissAction)

        if let settingsAction = CurrentAppContext().openSystemSettingsAction {
            settingsAction.accessibilityIdentifier = "OWSAlerts.\("settings")"
            alert.addAction(settingsAction)
        }
        CurrentAppContext().frontmostViewController()?.presentAlert(alert)
    }

    @objc
    public class func showAlert(_ alert: UIAlertController) {
        guard let frontmostViewController = CurrentAppContext().frontmostViewController() else {
            owsFailDebug("frontmostViewController was unexpectedly nil")
            return
        }
        frontmostViewController.presentAlert(alert)
    }

    @objc
    public class func showAlert(title: String) {
        self.showAlert(title: title, message: nil, buttonTitle: nil)
    }

    @objc
    public class func showAlert(title: String?, message: String) {
        self.showAlert(title: title, message: message, buttonTitle: nil)
    }

    @objc
    public class func showAlert(title: String?, message: String? = nil, buttonTitle: String? = nil, buttonAction: ((UIAlertAction) -> Void)? = nil) {
        guard let fromViewController = CurrentAppContext().frontmostViewController() else {
            return
        }
        showAlert(title: title, message: message, buttonTitle: buttonTitle, buttonAction: buttonAction,
                  fromViewController: fromViewController)
    }

    @objc
    public class func showAlert(title: String?, message: String? = nil, buttonTitle: String? = nil, buttonAction: ((UIAlertAction) -> Void)? = nil, fromViewController: UIViewController?) {

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        let actionTitle = buttonTitle ?? NSLocalizedString("OK", comment: "")
        let okAction = UIAlertAction(title: actionTitle, style: .default, handler: buttonAction)
        okAction.accessibilityIdentifier = "OWSAlerts.\("ok")"
        alert.addAction(okAction)
        fromViewController?.presentAlert(alert)
    }

    @objc
    public class func showConfirmationAlert(title: String, message: String? = nil, proceedTitle: String? = nil, proceedAction: @escaping (UIAlertAction) -> Void) {
        assert(title.count > 0)

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(self.cancelAction)

        let actionTitle = proceedTitle ?? NSLocalizedString("OK", comment: "")
        let okAction = UIAlertAction(title: actionTitle, style: .default, handler: proceedAction)
        okAction.accessibilityIdentifier = "OWSAlerts.\("ok")"
        alert.addAction(okAction)

        CurrentAppContext().frontmostViewController()?.presentAlert(alert)
    }

    @objc
    public class func showErrorAlert(message: String) {
        self.showAlert(title: CommonStrings.errorAlertTitle, message: message, buttonTitle: nil)
    }

    @objc
    public class var cancelAction: UIAlertAction {
        let action = UIAlertAction(title: CommonStrings.cancelButton, style: .cancel) { _ in
            Logger.debug("Cancel item")
            // Do nothing.
        }
        action.accessibilityIdentifier = "OWSAlerts.\("cancel")"
        return action
    }
}
