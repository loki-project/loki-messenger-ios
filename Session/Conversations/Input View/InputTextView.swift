// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionUtilitiesKit

public final class InputTextView: UITextView, UITextViewDelegate {
    private static let defaultFont: UIFont = .systemFont(ofSize: Values.mediumFontSize)
    private static let defaultThemeTextColor: ThemeValue = .textPrimary
    private weak var snDelegate: InputTextViewDelegate?
    private let maxWidth: CGFloat
    private lazy var heightConstraint = self.set(.height, to: minHeight)
    
    public override var text: String? { didSet { handleTextChanged() } }
    
    // MARK: - UI Components
    
    private lazy var placeholderLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.mediumFontSize)
        result.text = "message".localized()
        result.themeTextColor = .textSecondary
        
        return result
    }()
    
    // MARK: - Settings
    
    private let minHeight: CGFloat = 22
    private let maxHeight: CGFloat = 80

    // MARK: - Lifecycle
    
    init(delegate: InputTextViewDelegate, maxWidth: CGFloat) {
        snDelegate = delegate
        self.maxWidth = maxWidth
        
        super.init(frame: CGRect.zero, textContainer: nil)
        
        setUpViewHierarchy()
        self.delegate = self
        self.isAccessibilityElement = true
        self.accessibilityLabel = "Message"
    }
    
    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        preconditionFailure("Use init(delegate:) instead.")
    }

    public required init?(coder: NSCoder) {
        preconditionFailure("Use init(delegate:) instead.")
    }
    
    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            if UIPasteboard.general.hasImages {
                return true
            }
        }
        return super.canPerformAction(action, withSender: sender)
    }
    
    public override func paste(_ sender: Any?) {
        if let image = UIPasteboard.general.image {
            snDelegate?.didPasteImageFromPasteboard(self, image: image)
        }
        super.paste(sender)
    }

    private func setUpViewHierarchy() {
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        
        /// **Note:** If we add any additional attributes here then we will need to update the logic in
        /// `textView(_:,shouldChangeTextIn:replacementText:)` to match
        font = InputTextView.defaultFont
        themeBackgroundColor = .clear
        themeTextColor = InputTextView.defaultThemeTextColor
        themeTintColor = .primary
        
        heightConstraint.isActive = true
        let horizontalInset: CGFloat = 2
        textContainerInset = UIEdgeInsets(top: 0, left: horizontalInset, bottom: 0, right: horizontalInset)
        addSubview(placeholderLabel)
        placeholderLabel.pin(.leading, to: .leading, of: self, withInset: horizontalInset + 3) // Slight visual adjustment
        placeholderLabel.pin(.top, to: .top, of: self)
        pin(.trailing, to: .trailing, of: placeholderLabel, withInset: horizontalInset)
        pin(.bottom, to: .bottom, of: placeholderLabel)
        
        ThemeManager.onThemeChange(observer: self) { [weak self] theme, _ in
            switch theme.interfaceStyle {
                case .light: self?.keyboardAppearance = .light
                default: self?.keyboardAppearance = .dark
            }
        }
    }

    // MARK: - Updating
    
    public func textViewDidChange(_ textView: UITextView) {
        handleTextChanged()
    }
    
    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let currentText: String = (textView.text ?? "")
        guard let textRange: Range<String.Index> = Range(range, in: currentText) else { return true }
        
        /// Use utf16 view for proper length calculation
        let currentLength: Int = currentText.count
        let rangeLength: Int = currentText[textRange].count
        let newLength: Int = ((currentLength - rangeLength) + text.count)
        
        /// If the updated length is within the limit then just let the OS handle it (no need to do anything custom
        guard newLength > SessionApp.maxMessageCharacterCount else { return true }
        
        /// Ensure there is actually space remaining (if not then just don't allow editing)
        let remainingSpace: Int = SessionApp.maxMessageCharacterCount - (currentLength - rangeLength)
        guard remainingSpace > 0 else { return false }
        
        /// Truncate text based on character count (use `textStorage.replaceCharacters` for built in `undo` support)
        let truncatedText: String = String(text.prefix(remainingSpace))
        let offset: Int = range.location + truncatedText.count
        
        /// Pasting a value that is too large into the input will result in some odd default OS styling being applied to the text which is very
        /// different from our desired text style, in order to avoid this we need to detect this case and explicitly set the value as an attributed
        /// string with our explicit styling
        ///
        /// **Note:** If we add any additional attributes these will need to be updated to match
        if currentText.isEmpty {
            textView.textStorage.setAttributedString(
                NSAttributedString(
                    string: truncatedText,
                    attributes: [
                        .font: textView.font ?? InputTextView.defaultFont,
                        .foregroundColor: textView.textColor ?? ThemeManager.currentTheme.color(
                            for: InputTextView.defaultThemeTextColor
                        ) as Any
                    ]
                )
            )
        }
        else {
            textView.textStorage.replaceCharacters(in: range, with: truncatedText)
        }
        
        /// Position cursor after inserted text
        ///
        /// **Note:** We need to dispatch to the next run loop because it seems that iOS might revert the `selectedTextRange`
        /// after returning `false` from this function, by dispatching we then override this reverted position with a desired final position
        if let newPosition: UITextPosition = textView.position(from: textView.beginningOfDocument, offset: offset) {
            DispatchQueue.main.async {
                textView.selectedTextRange = textView.textRange(from: newPosition, to: newPosition)
            }
        }
        
        return false
    }
    
    private func handleTextChanged() {
        defer { snDelegate?.inputTextViewDidChangeContent(self) }
        
        placeholderLabel.isHidden = !(text ?? "").isEmpty
        
        let height = frame.height
        let size = sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        
        // `textView.contentSize` isn't accurate when restoring a multiline draft, so we set it here manually
        self.contentSize = size
        let newHeight = size.height.clamp(minHeight, maxHeight)
        
        guard newHeight != height else { return }
        
        heightConstraint.constant = newHeight
        snDelegate?.inputTextViewDidChangeSize(self)
    }
}

// MARK: - InputTextViewDelegate

protocol InputTextViewDelegate: AnyObject {
    func inputTextViewDidChangeSize(_ inputTextView: InputTextView)
    func inputTextViewDidChangeContent(_ inputTextView: InputTextView)
    func didPasteImageFromPasteboard(_ inputTextView: InputTextView, image: UIImage)
}
