// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Lucide
import SessionUIKit
import SignalUtilitiesKit
import SessionMessagingKit
import SessionUtilitiesKit

final class DeletedMessageView: UIView {
    private static let iconSize: CGFloat = 18
    private static let iconImageViewSize: CGFloat = 30
    
    // MARK: - Lifecycle
    
    init(textColor: ThemeValue, variant: Interaction.Variant, maxWidth: CGFloat) {
        super.init(frame: CGRect.zero)
        accessibilityIdentifier = "Deleted message"
        isAccessibilityElement = true
        setUpViewHierarchy(textColor: textColor, variant: variant, maxWidth: maxWidth)
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(textColor:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(textColor:) instead.")
    }
    
    private func setUpViewHierarchy(textColor: ThemeValue, variant: Interaction.Variant, maxWidth: CGFloat) {
        // Image view
        let imageContainerView: UIView = UIView()
        imageContainerView.set(.width, to: DeletedMessageView.iconImageViewSize)
        imageContainerView.set(.height, to: DeletedMessageView.iconImageViewSize)
        
        let imageView = UIImageView(image: Lucide.image(icon: .trash2, size: DeletedMessageView.iconSize)?.withRenderingMode(.alwaysTemplate))
        imageView.themeTintColor = textColor
        imageView.contentMode = .scaleAspectFit
        imageView.set(.width, to: DeletedMessageView.iconSize)
        imageView.set(.height, to: DeletedMessageView.iconSize)
        imageContainerView.addSubview(imageView)
        imageView.center(in: imageContainerView)
        
        // Body label
        let titleLabel = UILabel()
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.preferredMaxLayoutWidth = maxWidth - 6   // `6` for the `stackView.layoutMargins`
        titleLabel.font = .systemFont(ofSize: Values.smallFontSize)
        titleLabel.text = {
            switch variant {
                case .standardIncomingDeletedLocally, .standardOutgoingDeletedLocally:
                    return "deleteMessageDeletedLocally".localized()
                
                default: return "deleteMessageDeletedGlobally".localized()
            }
        }()
        titleLabel.themeTextColor = textColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 2
        
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ imageContainerView, titleLabel ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 6)
        addSubview(stackView)
        
        let calculatedSize: CGSize = stackView.systemLayoutSizeFitting(CGSize(width: maxWidth, height: 999))
        stackView.pin(to: self, withInset: Values.smallSpacing)
        stackView.set(.height, to: calculatedSize.height)
    }
}
