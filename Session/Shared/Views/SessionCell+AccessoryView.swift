// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit

extension SessionCell {
    public class AccessoryView: UIView, UISearchBarDelegate {
        // Note: We set a minimum width for the 'AccessoryView' so that the titles line up
        // nicely when we have a mix of icons and switches
        private static let minWidth: CGFloat = 50
        
        private var onTap: ((SessionButton?) -> Void)?
        private var searchTermChanged: ((String?) -> Void)?
        
        // MARK: - UI
        
        private lazy var minWidthConstraint: NSLayoutConstraint = self.widthAnchor
            .constraint(greaterThanOrEqualToConstant: AccessoryView.minWidth)
        private lazy var fixedWidthConstraint: NSLayoutConstraint = self.set(.width, to: AccessoryView.minWidth)
        private lazy var imageViewConstraints: [NSLayoutConstraint] = [
            imageView.pin(.top, to: .top, of: self),
            imageView.pin(.bottom, to: .bottom, of: self)
        ]
        private lazy var imageViewLeadingConstraint: NSLayoutConstraint = imageView.pin(.leading, to: .leading, of: self)
        private lazy var imageViewTrailingConstraint: NSLayoutConstraint = imageView.pin(.trailing, to: .trailing, of: self)
        private lazy var imageViewWidthConstraint: NSLayoutConstraint = imageView.set(.width, to: 0)
        private lazy var imageViewHeightConstraint: NSLayoutConstraint = imageView.set(.height, to: 0)
        private lazy var toggleSwitchConstraints: [NSLayoutConstraint] = [
            toggleSwitch.pin(.top, to: .top, of: self),
            toggleSwitch.pin(.leading, to: .leading, of: self),
            toggleSwitch.pin(.trailing, to: .trailing, of: self),
            toggleSwitch.pin(.bottom, to: .bottom, of: self)
        ]
        private lazy var dropDownStackViewConstraints: [NSLayoutConstraint] = [
            dropDownStackView.pin(.top, to: .top, of: self),
            dropDownStackView.pin(.leading, to: .leading, of: self, withInset: Values.smallSpacing),
            dropDownStackView.pin(.trailing, to: .trailing, of: self, withInset: -Values.smallSpacing),
            dropDownStackView.pin(.bottom, to: .bottom, of: self)
        ]
        private lazy var radioViewWidthConstraint: NSLayoutConstraint = radioView.set(.width, to: 0)
        private lazy var radioViewHeightConstraint: NSLayoutConstraint = radioView.set(.height, to: 0)
        private lazy var radioBorderViewWidthConstraint: NSLayoutConstraint = radioBorderView.set(.width, to: 0)
        private lazy var radioBorderViewHeightConstraint: NSLayoutConstraint = radioBorderView.set(.height, to: 0)
        private lazy var radioBorderViewConstraints: [NSLayoutConstraint] = [
            radioBorderView.pin(.top, to: .top, of: self),
            radioBorderView.center(.horizontal, in: self),
            radioBorderView.pin(.bottom, to: .bottom, of: self)
        ]
        private lazy var highlightingBackgroundLabelConstraints: [NSLayoutConstraint] = [
            highlightingBackgroundLabel.pin(.top, to: .top, of: self),
            highlightingBackgroundLabel.pin(.leading, to: .leading, of: self, withInset: Values.smallSpacing),
            highlightingBackgroundLabel.pin(.trailing, to: .trailing, of: self, withInset: -Values.smallSpacing),
            highlightingBackgroundLabel.pin(.bottom, to: .bottom, of: self)
        ]
        private lazy var profilePictureViewLeadingConstraint: NSLayoutConstraint = profilePictureView.pin(.leading, to: .leading, of: self)
        private lazy var profilePictureViewTrailingConstraint: NSLayoutConstraint = profilePictureView.pin(.trailing, to: .trailing, of: self)
        private lazy var profilePictureViewConstraints: [NSLayoutConstraint] = [
            profilePictureView.pin(.top, to: .top, of: self),
            profilePictureView.pin(.bottom, to: .bottom, of: self)
        ]
        private lazy var profilePictureViewWidthConstraint: NSLayoutConstraint = profilePictureView.set(.width, to: 0)
        private lazy var profilePictureViewHeightConstraint: NSLayoutConstraint = profilePictureView.set(.height, to: 0)
        private lazy var searchBarConstraints: [NSLayoutConstraint] = [
            searchBar.pin(.top, to: .top, of: self),
            searchBar.pin(.leading, to: .leading, of: self, withInset: -8),  // Removing default inset
            searchBar.pin(.trailing, to: .trailing, of: self, withInset: 8), // Removing default inset
            searchBar.pin(.bottom, to: .bottom, of: self)
        ]
        private lazy var buttonConstraints: [NSLayoutConstraint] = [
            button.pin(.top, to: .top, of: self),
            button.pin(.leading, to: .leading, of: self),
            button.pin(.trailing, to: .trailing, of: self),
            button.pin(.bottom, to: .bottom, of: self)
        ]
        
        private let imageView: UIImageView = {
            let result: UIImageView = UIImageView()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.clipsToBounds = true
            result.contentMode = .scaleAspectFit
            result.themeTintColor = .textPrimary
            result.layer.minificationFilter = .trilinear
            result.layer.magnificationFilter = .trilinear
            result.isHidden = true
            
            return result
        }()
        
        private let toggleSwitch: UISwitch = {
            let result: UISwitch = UISwitch()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.isUserInteractionEnabled = false // Triggered by didSelectCell instead
            result.themeOnTintColor = .primary
            result.isHidden = true
            result.setContentHuggingHigh()
            result.setCompressionResistanceHigh()
            
            return result
        }()
        
        private let dropDownStackView: UIStackView = {
            let result: UIStackView = UIStackView()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.axis = .horizontal
            result.distribution = .fill
            result.alignment = .center
            result.spacing = Values.verySmallSpacing
            result.isHidden = true
            
            return result
        }()
        
        private let dropDownImageView: UIImageView = {
            let result: UIImageView = UIImageView(image: UIImage(systemName: "arrowtriangle.down.fill"))
            result.translatesAutoresizingMaskIntoConstraints = false
            result.themeTintColor = .textPrimary
            result.set(.width, to: 10)
            result.set(.height, to: 10)
            
            return result
        }()
        
        private let dropDownLabel: UILabel = {
            let result: UILabel = UILabel()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.font = .systemFont(ofSize: Values.smallFontSize, weight: .medium)
            result.themeTextColor = .textPrimary
            result.setContentHuggingHigh()
            result.setCompressionResistanceHigh()
            
            return result
        }()
        
        private let radioBorderView: UIView = {
            let result: UIView = UIView()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.isUserInteractionEnabled = false
            result.layer.borderWidth = 1
            result.themeBorderColor = .radioButton_unselectedBorder
            result.isHidden = true
            
            return result
        }()
        
        private let radioView: UIView = {
            let result: UIView = UIView()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.isUserInteractionEnabled = false
            result.themeBackgroundColor = .radioButton_unselectedBackground
            result.isHidden = true
            
            return result
        }()
        
        public lazy var highlightingBackgroundLabel: SessionHighlightingBackgroundLabel = {
            let result: SessionHighlightingBackgroundLabel = SessionHighlightingBackgroundLabel()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.isHidden = true
            
            return result
        }()
        
        private lazy var profilePictureView: ProfilePictureView = {
            let result: ProfilePictureView = ProfilePictureView()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.isHidden = true
            
            return result
        }()
        
        private lazy var profileIconContainerView: UIView = {
            let result: UIView = UIView()
            result.translatesAutoresizingMaskIntoConstraints = false
            result.themeBackgroundColor = .primary
            result.isHidden = true
            result.set(.width, to: 26)
            result.set(.height, to: 26)
            result.layer.cornerRadius = (26 / 2)
            
            return result
        }()
        
        private lazy var profileIconImageView: UIImageView = {
            let result: UIImageView = UIImageView()
            result.translatesAutoresizingMaskIntoConstraints = false
            
            return result
        }()
        
        private lazy var searchBar: UISearchBar = {
            let result: ContactsSearchBar = ContactsSearchBar()
            result.themeTintColor = .textPrimary
            result.themeBackgroundColor = .clear
            result.searchTextField.themeBackgroundColor = .backgroundSecondary
            result.delegate = self
            
            return result
        }()
        
        private lazy var button: SessionButton = {
            let result: SessionButton = SessionButton(style: .bordered, size: .medium)
            result.translatesAutoresizingMaskIntoConstraints = false
            result.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
            result.isHidden = true
            
            return result
        }()
        
        private var customView: UIView?
        
        // MARK: - Initialization
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            setupViewHierarchy()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            
            setupViewHierarchy()
        }

        private func setupViewHierarchy() {
            addSubview(imageView)
            addSubview(toggleSwitch)
            addSubview(dropDownStackView)
            addSubview(radioBorderView)
            addSubview(highlightingBackgroundLabel)
            addSubview(profilePictureView)
            addSubview(profileIconContainerView)
            addSubview(button)
            addSubview(searchBar)
            
            dropDownStackView.addArrangedSubview(dropDownImageView)
            dropDownStackView.addArrangedSubview(dropDownLabel)
            
            radioBorderView.addSubview(radioView)
            radioView.center(in: radioBorderView)
            
            profileIconContainerView.addSubview(profileIconImageView)
            
            profileIconContainerView.pin(.bottom, to: .bottom, of: profilePictureView)
            profileIconContainerView.pin(.trailing, to: .trailing, of: profilePictureView)
            profileIconImageView.pin(to: profileIconContainerView, withInset: Values.verySmallSpacing)
        }
        
        // MARK: - Content
        
        func prepareForReuse() {
            isHidden = true
            onTap = nil
            searchTermChanged = nil
            
            imageView.image = nil
            imageView.themeTintColor = .textPrimary
            imageView.contentMode = .scaleAspectFit
            dropDownImageView.themeTintColor = .textPrimary
            dropDownLabel.text = ""
            dropDownLabel.themeTextColor = .textPrimary
            radioBorderView.themeBorderColor = .radioButton_unselectedBorder
            radioView.themeBackgroundColor = .radioButton_unselectedBackground
            highlightingBackgroundLabel.text = ""
            highlightingBackgroundLabel.themeTextColor = .textPrimary
            customView?.removeFromSuperview()
            
            imageView.isHidden = true
            toggleSwitch.isHidden = true
            dropDownStackView.isHidden = true
            radioBorderView.isHidden = true
            radioView.alpha = 1
            radioView.isHidden = true
            highlightingBackgroundLabel.isHidden = true
            profilePictureView.isHidden = true
            profileIconContainerView.isHidden = true
            button.isHidden = true
            searchBar.isHidden = true
            
            minWidthConstraint.constant = AccessoryView.minWidth
            minWidthConstraint.isActive = false
            fixedWidthConstraint.constant = AccessoryView.minWidth
            fixedWidthConstraint.isActive = false
            imageViewLeadingConstraint.isActive = false
            imageViewTrailingConstraint.isActive = false
            imageViewWidthConstraint.isActive = false
            imageViewHeightConstraint.isActive = false
            imageViewConstraints.forEach { $0.isActive = false }
            toggleSwitchConstraints.forEach { $0.isActive = false }
            dropDownStackViewConstraints.forEach { $0.isActive = false }
            radioViewWidthConstraint.isActive = false
            radioViewHeightConstraint.isActive = false
            radioBorderViewWidthConstraint.isActive = false
            radioBorderViewHeightConstraint.isActive = false
            radioBorderViewConstraints.forEach { $0.isActive = false }
            highlightingBackgroundLabelConstraints.forEach { $0.isActive = false }
            profilePictureViewLeadingConstraint.isActive = false
            profilePictureViewTrailingConstraint.isActive = false
            profilePictureViewWidthConstraint.isActive = false
            profilePictureViewHeightConstraint.isActive = false
            profilePictureViewConstraints.forEach { $0.isActive = false }
            searchBarConstraints.forEach { $0.isActive = false }
            buttonConstraints.forEach { $0.isActive = false }
        }
        
        public func update(
            with accessory: Accessory?,
            tintColor: ThemeValue,
            isEnabled: Bool
        ) {
            guard let accessory: Accessory = accessory else { return }
            
            // If we have an accessory value then this shouldn't be hidden
            self.isHidden = false

            switch accessory {
                case .icon(let image, let iconSize, let customTint, let shouldFill):
                    imageView.image = image
                    imageView.themeTintColor = (customTint ?? tintColor)
                    imageView.contentMode = (shouldFill ? .scaleAspectFill : .scaleAspectFit)
                    imageView.isHidden = false
                    
                    switch iconSize {
                        case .fit:
                            imageView.sizeToFit()
                            fixedWidthConstraint.constant = (imageView.bounds.width + (shouldFill ? 0 : (Values.smallSpacing * 2)))
                            fixedWidthConstraint.isActive = true
                            imageViewWidthConstraint.constant = imageView.bounds.width
                            imageViewHeightConstraint.constant = imageView.bounds.height

                        default:
                            fixedWidthConstraint.isActive = (iconSize.size <= fixedWidthConstraint.constant)
                            imageViewWidthConstraint.constant = iconSize.size
                            imageViewHeightConstraint.constant = iconSize.size
                    }
                    
                    minWidthConstraint.isActive = !fixedWidthConstraint.isActive
                    imageViewLeadingConstraint.constant = (shouldFill ? 0 : Values.smallSpacing)
                    imageViewTrailingConstraint.constant = (shouldFill ? 0 : -Values.smallSpacing)
                    imageViewLeadingConstraint.isActive = true
                    imageViewTrailingConstraint.isActive = true
                    imageViewWidthConstraint.isActive = true
                    imageViewHeightConstraint.isActive = true
                    imageViewConstraints.forEach { $0.isActive = true }
                
                case .iconAsync(let iconSize, let customTint, let shouldFill, let setter):
                    setter(imageView)
                    imageView.themeTintColor = (customTint ?? tintColor)
                    imageView.contentMode = (shouldFill ? .scaleAspectFill : .scaleAspectFit)
                    imageView.isHidden = false
                    
                    switch iconSize {
                        case .fit:
                            imageView.sizeToFit()
                            fixedWidthConstraint.constant = (imageView.bounds.width + (shouldFill ? 0 : (Values.smallSpacing * 2)))
                            fixedWidthConstraint.isActive = true
                            imageViewWidthConstraint.constant = imageView.bounds.width
                            imageViewHeightConstraint.constant = imageView.bounds.height

                        default:
                            fixedWidthConstraint.isActive = (iconSize.size <= fixedWidthConstraint.constant)
                            imageViewWidthConstraint.constant = iconSize.size
                            imageViewHeightConstraint.constant = iconSize.size
                    }
                    
                    minWidthConstraint.isActive = !fixedWidthConstraint.isActive
                    imageViewLeadingConstraint.constant = (shouldFill ? 0 : Values.smallSpacing)
                    imageViewTrailingConstraint.constant = (shouldFill ? 0 : -Values.smallSpacing)
                    imageViewLeadingConstraint.isActive = true
                    imageViewTrailingConstraint.isActive = true
                    imageViewWidthConstraint.isActive = true
                    imageViewHeightConstraint.isActive = true
                    imageViewConstraints.forEach { $0.isActive = true }
                    
                case .toggle(let dataSource):
                    toggleSwitch.isHidden = false
                    toggleSwitch.isEnabled = isEnabled
                    
                    fixedWidthConstraint.isActive = true
                    toggleSwitchConstraints.forEach { $0.isActive = true }
                    
                    let newValue: Bool = dataSource.currentBoolValue// TODO: Clean this up so it's less flakey? (if the change is made async then the UI won't be updated)
                    
                    if newValue != toggleSwitch.isOn {
                        toggleSwitch.setOn(newValue, animated: true)
                    }
                    
                case .dropDown(let dataSource):
                    dropDownLabel.text = dataSource.currentStringValue
                    dropDownStackView.isHidden = false
                    dropDownStackViewConstraints.forEach { $0.isActive = true }
                    minWidthConstraint.isActive = true
                    
                case .radio(let size, let isSelectedRetriever, let storedSelection):
                    let isSelected: Bool = isSelectedRetriever()
                    let wasOldSelection: Bool = (!isSelected && storedSelection)
                    
                    radioBorderView.isHidden = false
                    radioBorderView.themeBorderColor = (isSelected ?
                        .radioButton_selectedBorder :
                        .radioButton_unselectedBorder
                    )
                    radioBorderView.layer.cornerRadius = (size.borderSize / 2)
                    
                    radioView.alpha = (wasOldSelection ? 0.3 : 1)
                    radioView.isHidden = (!isSelected && !storedSelection)
                    radioView.themeBackgroundColor = (isSelected || wasOldSelection ?
                        .radioButton_selectedBackground :
                        .radioButton_unselectedBackground
                    )
                    radioView.layer.cornerRadius = (size.selectionSize / 2)
                    
                    radioViewWidthConstraint.constant = size.selectionSize
                    radioViewHeightConstraint.constant = size.selectionSize
                    radioBorderViewWidthConstraint.constant = size.borderSize
                    radioBorderViewHeightConstraint.constant = size.borderSize
                    
                    fixedWidthConstraint.isActive = true
                    radioViewWidthConstraint.isActive = true
                    radioViewHeightConstraint.isActive = true
                    radioBorderViewWidthConstraint.isActive = true
                    radioBorderViewHeightConstraint.isActive = true
                    radioBorderViewConstraints.forEach { $0.isActive = true }
                    
                case .highlightingBackgroundLabel(let title):
                    highlightingBackgroundLabel.text = title
                    highlightingBackgroundLabel.themeTextColor = tintColor
                    highlightingBackgroundLabel.isHidden = false
                    highlightingBackgroundLabelConstraints.forEach { $0.isActive = true }
                    minWidthConstraint.isActive = true
                    
                case .profile(
                    let profileId,
                    let profileSize,
                    let threadVariant,
                    let customImageData,
                    let profile,
                    let additionalProfile,
                    let cornerIcon
                ):
                    // Note: We MUST set the 'size' property before triggering the 'update'
                    // function or the profile picture won't layout correctly
                    switch profileSize {
                        case .fit:
                            profilePictureView.size = IconSize.large.size
                            profilePictureViewWidthConstraint.constant = IconSize.large.size
                            profilePictureViewHeightConstraint.constant = IconSize.large.size

                        default:
                            profilePictureView.size = profileSize.size
                            profilePictureViewWidthConstraint.constant = profileSize.size
                            profilePictureViewHeightConstraint.constant = profileSize.size
                    }
                    
                    profilePictureView.update(
                        publicKey: profileId,
                        threadVariant: threadVariant,
                        customImageData: customImageData,
                        profile: profile,
                        additionalProfile: additionalProfile
                    )
                    profilePictureView.isHidden = false
                    profileIconContainerView.isHidden = (cornerIcon == nil)
                    profileIconImageView.image = cornerIcon
                    
                    fixedWidthConstraint.constant = profilePictureViewWidthConstraint.constant
                    fixedWidthConstraint.isActive = true
                    profilePictureViewLeadingConstraint.constant = (profilePictureView.size > AccessoryView.minWidth ? 0 : Values.smallSpacing)
                    profilePictureViewTrailingConstraint.constant = (profilePictureView.size > AccessoryView.minWidth ? 0 : -Values.smallSpacing)
                    profilePictureViewLeadingConstraint.isActive = true
                    profilePictureViewTrailingConstraint.isActive = true
                    profilePictureViewWidthConstraint.isActive = true
                    profilePictureViewHeightConstraint.isActive = true
                    profilePictureViewConstraints.forEach { $0.isActive = true }
                    
                case .search(let placeholder, let searchTermChanged):
                    self.searchTermChanged = searchTermChanged
                    searchBar.placeholder = placeholder
                    searchBar.isHidden = false
                    searchBarConstraints.forEach { $0.isActive = true }
                    
                case .button(let style, let title, let onTap):
                    self.onTap = onTap
                    button.setTitle(title, for: .normal)
                    button.setStyle(style)
                    button.isHidden = false
                    minWidthConstraint.isActive = true
                    buttonConstraints.forEach { $0.isActive = true }
                    
                case .customView(let viewGenerator):
                    let generatedView: UIView = viewGenerator()
                    addSubview(generatedView)
                    
                    generatedView.pin(.top, to: .top, of: self)
                    generatedView.pin(.leading, to: .leading, of: self)
                    generatedView.pin(.trailing, to: .trailing, of: self)
                    generatedView.pin(.bottom, to: .bottom, of: self)
                    
                    customView?.removeFromSuperview()  // Just in case
                    customView = generatedView
                    minWidthConstraint.isActive = true
            }
        }
        
        // MARK: - Interaction
        
        func setHighlighted(_ highlighted: Bool, animated: Bool) {
            highlightingBackgroundLabel.setHighlighted(highlighted, animated: animated)
        }
        
        func setSelected(_ selected: Bool, animated: Bool) {
            highlightingBackgroundLabel.setSelected(selected, animated: animated)
        }
        
        @objc private func buttonTapped() {
            onTap?(button)
        }
        
        // MARK: - UISearchBarDelegate
        
        public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            searchTermChanged?(searchText)
        }
        
        public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            searchBar.setShowsCancelButton(true, animated: true)
        }
        
        public func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            searchBar.setShowsCancelButton(false, animated: true)
        }
        
        public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            searchBar.endEditing(true)
        }
    }
}
