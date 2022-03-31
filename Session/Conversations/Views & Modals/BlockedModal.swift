import SessionMessagingKit

final class BlockedModal: Modal {
    private let publicKey: String
    
    // MARK: Lifecycle
    init(publicKey: String) {
        self.publicKey = publicKey
        super.init(nibName: nil, bundle: nil)
    }
    
    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(publicKey:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(publicKey:) instead.")
    }
    
    override func populateContentView() {
        // Name
        let name = Storage.shared.getContact(with: publicKey)?.displayName(for: .regular) ?? publicKey
        // Title
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.largeFontSize)
        titleLabel.text = String(format: NSLocalizedString("modal_blocked_title", comment: ""), name)
        titleLabel.textAlignment = .center
        // Message
        let messageLabel = UILabel()
        messageLabel.textColor = Colors.text
        messageLabel.font = .systemFont(ofSize: Values.smallFontSize)
        let message = String(format: NSLocalizedString("modal_blocked_explanation", comment: ""), name)
        let attributedMessage = NSMutableAttributedString(string: message)
        attributedMessage.addAttributes([ .font : UIFont.boldSystemFont(ofSize: Values.smallFontSize) ], range: (message as NSString).range(of: name))
        messageLabel.attributedText = attributedMessage
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.textAlignment = .center
        // Unblock button
        let unblockButton = UIButton()
        unblockButton.set(.height, to: Values.mediumButtonHeight)
        unblockButton.layer.cornerRadius = Modal.buttonCornerRadius
        unblockButton.backgroundColor = Colors.buttonBackground
        unblockButton.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        unblockButton.setTitleColor(Colors.text, for: UIControl.State.normal)
        unblockButton.setTitle(NSLocalizedString("modal_blocked_button_title", comment: ""), for: UIControl.State.normal)
        unblockButton.addTarget(self, action: #selector(unblock), for: UIControl.Event.touchUpInside)
        // Button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ cancelButton, unblockButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = Values.mediumSpacing
        buttonStackView.distribution = .fillEqually
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ titleLabel, messageLabel, buttonStackView ])
        mainStackView.axis = .vertical
        mainStackView.spacing = Values.largeSpacing
        contentView.addSubview(mainStackView)
        mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: Values.largeSpacing)
    }
    
    // MARK: Interaction
    @objc private func unblock() {
        let publicKey: String = self.publicKey
        
        Storage.shared.write(
            with: { transaction in
                guard let transaction = transaction as? YapDatabaseReadWriteTransaction, let contact: Contact = Storage.shared.getContact(with: publicKey, using: transaction) else {
                    return
                }
                
                contact.isBlocked = false
                Storage.shared.setContact(contact, using: transaction as Any)
            },
            completion: {
                MessageSender.syncConfiguration(forceSyncNow: true).retainUntilComplete()
            }
        )
        
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
}
