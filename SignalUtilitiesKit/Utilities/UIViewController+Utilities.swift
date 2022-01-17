import SessionUIKit

@objc(LKViewControllerUtilities)
public final class ViewControllerUtilities : NSObject {

    private override init() { }

    @objc(setUpDefaultSessionStyleForVC:withTitle:customBackButton:customBackground:)
    public static func setUpDefaultSessionStyle(for vc: UIViewController, title: String?, hasCustomBackButton: Bool, hasCustomBackground: Bool = false) {
        // Set gradient background
        if !hasCustomBackground {
            vc.view.backgroundColor = .clear
            let gradient = Gradients.defaultBackground
            vc.view.setGradient(gradient)
        }
        
        // Set navigation bar background color
        if let navigationBar = vc.navigationController?.navigationBar {
            navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
            navigationBar.shadowImage = UIImage()
            navigationBar.isTranslucent = false
            navigationBar.barTintColor = Colors.navigationBarBackground
        }
        // Customize title
        if let title = title {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.textColor = Colors.text
            titleLabel.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
            vc.navigationItem.titleView = titleLabel
        }
        // Set up back button
        if hasCustomBackButton {
            let backButton = UIBarButtonItem(title: "Back", style: .plain, target: nil, action: nil)
            backButton.tintColor = Colors.text
            vc.navigationItem.backBarButtonItem = backButton
        }
    }
}
