//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer
import PromiseKit
import SessionUIKit
import CoreServices

@objc
public protocol AttachmentApprovalViewControllerDelegate: class {
    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                            didApproveAttachments attachments: [SignalAttachment], messageText: String?)

    func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController)

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController,
                            didChangeMessageText newMessageText: String?)

    @objc
    optional func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachment: SignalAttachment)

    @objc
    optional func attachmentApprovalDidTapAddMore(_ attachmentApproval: AttachmentApprovalViewController)
}

// MARK: -

@objc
public enum AttachmentApprovalViewControllerMode: UInt {
    case modal
    case sharedNavigation
}

// MARK: -

@objc
public class AttachmentApprovalViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    // MARK: - Properties

    private let mode: AttachmentApprovalViewControllerMode
    private let isAddMoreVisible: Bool

    public weak var approvalDelegate: AttachmentApprovalViewControllerDelegate?

    public var isEditingCaptions = false {
        didSet {
            updateContents()
        }
    }

    // MARK: - Initializers

    @available(*, unavailable, message:"use attachment: constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    let kSpacingBetweenItems: CGFloat = 20

    @objc
    required public init(mode: AttachmentApprovalViewControllerMode,
                         attachments: [SignalAttachment]) {
        assert(attachments.count > 0)
        self.mode = mode
        let attachmentItems = attachments.map { SignalAttachmentItem(attachment: $0 )}
        self.isAddMoreVisible = mode == .sharedNavigation

        self.attachmentItemCollection = AttachmentItemCollection(attachmentItems: attachmentItems, isAddMoreVisible: isAddMoreVisible)

        let options: [UIPageViewController.OptionsKey: Any] = [.interPageSpacing: kSpacingBetweenItems]
        super.init(transitionStyle: .scroll,
                   navigationOrientation: .horizontal,
                   options: options)
        self.dataSource = self
        self.delegate = self

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: NSNotification.Name.OWSApplicationDidBecomeActive,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    public class func wrappedInNavController(attachments: [SignalAttachment], approvalDelegate: AttachmentApprovalViewControllerDelegate) -> OWSNavigationController {
        let vc = AttachmentApprovalViewController(mode: .modal, attachments: attachments)
        vc.approvalDelegate = approvalDelegate
        let navController = OWSNavigationController(rootViewController: vc)
        navController.ows_prefersStatusBarHidden = true
        return navController
    }

    // MARK: - Notifications

    @objc func didBecomeActive() {
        AssertIsOnMainThread()

        updateContents()
    }

    // MARK: - Subviews

    var galleryRailView: GalleryRailView {
        return bottomToolView.galleryRailView
    }

    var attachmentTextToolbar: AttachmentTextToolbar {
        return bottomToolView.attachmentTextToolbar
    }

    lazy var bottomToolView: AttachmentApprovalInputAccessoryView = {
        let bottomToolView = AttachmentApprovalInputAccessoryView()
        bottomToolView.delegate = self

        return bottomToolView
    }()

    lazy var touchInterceptorView = UIView()

    // MARK: - View Lifecycle

    public override var prefersStatusBarHidden: Bool {
        return true
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = Colors.navigationBarBackground

        // avoid an unpleasant "bounce" which doesn't make sense in the context of a single item.
        pagerScrollView?.isScrollEnabled = attachmentItems.count > 1

        // Bottom Toolbar
        galleryRailView.delegate = self
        attachmentTextToolbar.attachmentTextToolbarDelegate = self

        // Navigation

        self.navigationItem.title = nil

        guard let firstItem = attachmentItems.first else {
            owsFailDebug("firstItem was unexpectedly nil")
            return
        }

        self.setCurrentItem(firstItem, direction: .forward, animated: false)

        // layout immediately to avoid animating the layout process during the transition
        self.currentPageViewController.view.layoutIfNeeded()

        view.addSubview(touchInterceptorView)
        touchInterceptorView.autoPinEdgesToSuperviewEdges()
        touchInterceptorView.isHidden = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapTouchInterceptorView(gesture:)))
        touchInterceptorView.addGestureRecognizer(tapGesture)
    }

    override public func viewWillAppear(_ animated: Bool) {
        Logger.debug("")
        super.viewWillAppear(animated)

        guard let navigationBar = navigationController?.navigationBar as? OWSNavigationBar else {
            owsFailDebug("navigationBar was nil or unexpected class")
            return
        }
        
        // Loki: Set navigation bar background color
        navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        navigationBar.shadowImage = UIImage()
        navigationBar.isTranslucent = false
        navigationBar.barTintColor = Colors.navigationBarBackground
        navigationBar.respectsTheme = true
        navigationBar.backgroundColor = Colors.navigationBarBackground
        let backgroundImage = UIImage(color: Colors.navigationBarBackground)
        navigationBar.setBackgroundImage(backgroundImage, for: .default)

        updateContents()
    }

    override public func viewDidAppear(_ animated: Bool) {
        Logger.debug("")

        super.viewDidAppear(animated)

        updateContents()
    }

    override public func viewWillDisappear(_ animated: Bool) {
        Logger.debug("")
        super.viewWillDisappear(animated)
    }

    private func updateContents() {
        updateNavigationBar()
        updateInputAccessory()

        touchInterceptorView.isHidden = !isEditingCaptions
    }

    // MARK: - Input Accessory

    override public var inputAccessoryView: UIView? {
        bottomToolView.layoutIfNeeded()
        return bottomToolView
    }

    override public var canBecomeFirstResponder: Bool {
        return !shouldHideControls
    }

    public func updateInputAccessory() {
        var currentPageViewController: AttachmentPrepViewController?
        if pageViewControllers.count == 1 {
            currentPageViewController = pageViewControllers.first
        }
        let currentAttachmentItem: SignalAttachmentItem? = currentPageViewController?.attachmentItem

        let hasPresentedView = self.presentedViewController != nil
        let isToolbarFirstResponder = bottomToolView.hasFirstResponder
        if !shouldHideControls, !isFirstResponder, !hasPresentedView, !isToolbarFirstResponder {
            becomeFirstResponder()
        }

        bottomToolView.update(isEditingCaptions: isEditingCaptions,
                              currentAttachmentItem: currentAttachmentItem,
                              shouldHideControls: shouldHideControls)
    }

    public var messageText: String? {
        get {
            return attachmentTextToolbar.messageText
        }
        set {
            attachmentTextToolbar.messageText = newValue
        }
    }

    // MARK: - Navigation Bar

    public func updateNavigationBar() {
        guard !shouldHideControls else {
            self.navigationItem.leftBarButtonItem = nil
            self.navigationItem.rightBarButtonItem = nil
            return
        }

        guard !isEditingCaptions else {
            // Hide all navigation bar items while the caption view is open.
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("ATTACHMENT_APPROVAL_CAPTION_TITLE", comment: "Title for 'caption' mode of the attachment approval view."), style: .plain, target: nil, action: nil)

            let doneButton = navigationBarButton(imageName: "image_editor_checkmark_full",
                                                 selector: #selector(didTapCaptionDone(sender:)))
            let navigationBarItems = [doneButton]
            updateNavigationBar(navigationBarItems: navigationBarItems)
            return
        }

        var navigationBarItems = [UIView]()

        if let viewControllers = viewControllers,
            viewControllers.count == 1,
            let firstViewController = viewControllers.first as? AttachmentPrepViewController {
            navigationBarItems = firstViewController.navigationBarItems()

            // Show the caption UI if there's more than one attachment
            // OR if the attachment already has a caption.
            let attachmentCount = attachmentItemCollection.count
            var shouldShowCaptionUI = attachmentCount > 0
            if let captionText = firstViewController.attachmentItem.captionText, captionText.count > 0 {
                shouldShowCaptionUI = true
            }
            if shouldShowCaptionUI {
                let captionButton = navigationBarButton(imageName: "image_editor_caption",
                                                        selector: #selector(didTapCaption(sender:)))
                navigationBarItems.append(captionButton)
            }
        }

        updateNavigationBar(navigationBarItems: navigationBarItems)

        let hasCancel = (mode != .sharedNavigation)
        if hasCancel {
            // Mimic a UIBarButtonItem of type .cancel, but with a shadow.
            let cancelButton = OWSButton(title: CommonStrings.cancelButton) { [weak self] in
                self?.cancelPressed()
            }
            cancelButton.setTitleColor(Colors.text, for: .normal)
            if let titleLabel = cancelButton.titleLabel {
                titleLabel.font = UIFont.systemFont(ofSize: 17.0)
            } else {
                owsFailDebug("Missing titleLabel.")
            }
            cancelButton.sizeToFit()
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: cancelButton)
        } else {
            // Mimic a conventional back button, but with a shadow.
            let isRTL = CurrentAppContext().isRTL
            let imageName = isRTL ? "NavBarBackRTL" : "NavBarBack"
            let backButton = OWSButton(imageName: imageName, tintColor: Colors.text) { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }

            // Nudge closer to the left edge to match default back button item.
            let kExtraLeftPadding: CGFloat = isRTL ? +0 : -8

            // Give some extra hit area to the back button. This is a little smaller
            // than the default back button, but makes sense for our left aligned title
            // view in the MessagesViewController
            let kExtraRightPadding: CGFloat = isRTL ? -0 : +10

            // Extra hit area above/below
            let kExtraHeightPadding: CGFloat = 4

            // Matching the default backbutton placement is tricky.
            // We can't just adjust the imageEdgeInsets on a UIBarButtonItem directly,
            // so we adjust the imageEdgeInsets on a UIButton, then wrap that
            // in a UIBarButtonItem.

            backButton.contentHorizontalAlignment = .left

            // Default back button is 1.5 pixel lower than our extracted image.
            let kTopInsetPadding: CGFloat = 1.5
            backButton.imageEdgeInsets = UIEdgeInsets(top: kTopInsetPadding, left: kExtraLeftPadding, bottom: 0, right: 0)

            var backImageSize = CGSize.zero
            if let backImage = UIImage(named: imageName) {
                backImageSize = backImage.size
            } else {
                owsFailDebug("Missing backImage.")
            }
            backButton.frame = CGRect(origin: .zero, size: CGSize(width: backImageSize.width + kExtraRightPadding,
                                                                  height: backImageSize.height + kExtraHeightPadding))

            // Note: using a custom leftBarButtonItem breaks the interactive pop gesture.
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: backButton)
        }
    }

    // MARK: - Control Visibility

    public var shouldHideControls: Bool {
        guard let pageViewController = pageViewControllers.first else {
            return false
        }
        return pageViewController.shouldHideControls
    }

    // MARK: - View Helpers

    func remove(attachmentItem: SignalAttachmentItem) {
        if attachmentItem == currentItem {
            if let nextItem = attachmentItemCollection.itemAfter(item: attachmentItem) {
                setCurrentItem(nextItem, direction: .forward, animated: true)
            } else if let prevItem = attachmentItemCollection.itemBefore(item: attachmentItem) {
                setCurrentItem(prevItem, direction: .reverse, animated: true)
            } else {
                owsFailDebug("removing last item shouldn't be possible because rail should not be visible")
                return
            }
        }

        guard let cell = galleryRailView.cellViews.first(where: { $0.item === attachmentItem }) else {
            owsFailDebug("cell was unexpectedly nil")
            return
        }

        UIView.animate(withDuration: 0.2,
                       animations: {
                        // shrink stack view item until it disappears
                        cell.isHidden = true

                        // simultaneously fade out
                        cell.alpha = 0
        },
                       completion: { _ in
                        self.attachmentItemCollection.remove(item: attachmentItem)
                        self.approvalDelegate?.attachmentApproval?(self, didRemoveAttachment: attachmentItem.attachment)
                        self.updateMediaRail()
        })
    }

    lazy var pagerScrollView: UIScrollView? = {
        // This is kind of a hack. Since we don't have first class access to the superview's `scrollView`
        // we traverse the view hierarchy until we find it.
        let pagerScrollView = view.subviews.first { $0 is UIScrollView } as? UIScrollView
        assert(pagerScrollView != nil)

        return pagerScrollView
    }()

    // MARK: - UIPageViewControllerDelegate

    public func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        Logger.debug("")

        assert(pendingViewControllers.count == 1)
        pendingViewControllers.forEach { viewController in
            guard let pendingPage = viewController as? AttachmentPrepViewController else {
                owsFailDebug("unexpected viewController: \(viewController)")
                return
            }

            // use compact scale when keyboard is popped.
            let scale: AttachmentPrepViewController.AttachmentViewScale = self.isFirstResponder ? .fullsize : .compact
            pendingPage.setAttachmentViewScale(scale, animated: false)
        }
    }

    public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted: Bool) {
        Logger.debug("")

        assert(previousViewControllers.count == 1)
        previousViewControllers.forEach { viewController in
            guard let previousPage = viewController as? AttachmentPrepViewController else {
                owsFailDebug("unexpected viewController: \(viewController)")
                return
            }

            if transitionCompleted {
                previousPage.zoomOut(animated: false)
                updateMediaRail()
            }
        }
    }

    // MARK: - UIPageViewControllerDataSource

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let currentViewController = viewController as? AttachmentPrepViewController else {
            owsFailDebug("unexpected viewController: \(viewController)")
            return nil
        }

        let currentItem = currentViewController.attachmentItem
        guard let previousItem = attachmentItem(before: currentItem) else {
            return nil
        }

        guard let previousPage: AttachmentPrepViewController = buildPage(item: previousItem) else {
            return nil
        }

        return previousPage
    }

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        Logger.debug("")

        guard let currentViewController = viewController as? AttachmentPrepViewController else {
            owsFailDebug("unexpected viewController: \(viewController)")
            return nil
        }

        let currentItem = currentViewController.attachmentItem
        guard let nextItem = attachmentItem(after: currentItem) else {
            return nil
        }

        guard let nextPage: AttachmentPrepViewController = buildPage(item: nextItem) else {
            return nil
        }

        return nextPage
    }

    public var currentPageViewController: AttachmentPrepViewController {
        return pageViewControllers.first!
    }

    public var pageViewControllers: [AttachmentPrepViewController] {
        return super.viewControllers!.map { $0 as! AttachmentPrepViewController }
    }

    @objc
    public override func setViewControllers(_ viewControllers: [UIViewController]?, direction: UIPageViewController.NavigationDirection, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        super.setViewControllers(viewControllers,
                                 direction: direction,
                                 animated: animated) { [weak self] (finished) in
                                    if let completion = completion {
                                        completion(finished)
                                    }
                                    self?.updateContents()
        }
    }

    var currentItem: SignalAttachmentItem! {
        get {
            return currentPageViewController.attachmentItem
        }
        set {
            setCurrentItem(newValue, direction: .forward, animated: false)
        }
    }

    private var cachedPages: [SignalAttachmentItem: AttachmentPrepViewController] = [:]
    private func buildPage(item: SignalAttachmentItem) -> AttachmentPrepViewController? {

        if let cachedPage = cachedPages[item] {
            Logger.debug("cache hit.")
            return cachedPage
        }

        Logger.debug("cache miss.")
        let viewController = AttachmentPrepViewController(attachmentItem: item)
        viewController.prepDelegate = self
        cachedPages[item] = viewController

        return viewController
    }

    private func setCurrentItem(_ item: SignalAttachmentItem, direction: UIPageViewController.NavigationDirection, animated isAnimated: Bool) {
        guard let page = self.buildPage(item: item) else {
            owsFailDebug("unexpectedly unable to build new page")
            return
        }

        page.loadViewIfNeeded()

        self.setViewControllers([page], direction: direction, animated: isAnimated, completion: nil)
        updateMediaRail()
    }

    func updateMediaRail() {
        guard let currentItem = self.currentItem else {
            owsFailDebug("currentItem was unexpectedly nil")
            return
        }

        let cellViewBuilder: (GalleryRailItem) -> GalleryRailCellView = { [weak self] railItem in
            switch railItem {
            case is AddMoreRailItem:
                return GalleryRailCellView()
            case is SignalAttachmentItem:
                let cell = ApprovalRailCellView()
                cell.approvalRailCellDelegate = self
                return cell
            default:
                owsFailDebug("unexpted rail item type: \(railItem)")
                return GalleryRailCellView()
            }
        }

        galleryRailView.configureCellViews(itemProvider: attachmentItemCollection,
                                           focusedItem: currentItem,
                                           cellViewBuilder: cellViewBuilder)

        if isAddMoreVisible {
            galleryRailView.isHidden = false
        } else if attachmentItemCollection.attachmentItems.count > 1 {
            galleryRailView.isHidden = false
        } else {
            galleryRailView.isHidden = true
        }
    }

    let attachmentItemCollection: AttachmentItemCollection

    var attachmentItems: [SignalAttachmentItem] {
        return attachmentItemCollection.attachmentItems
    }

    var attachments: [SignalAttachment] {
        return attachmentItems.map { (attachmentItem) in
            autoreleasepool {
                return self.processedAttachment(forAttachmentItem: attachmentItem)
            }
        }
    }

    // For any attachments edited with the image editor, returns a
    // new SignalAttachment that reflects those changes.  Otherwise,
    // returns the original attachment.
    //
    // If any errors occurs in the export process, we fail over to
    // sending the original attachment.  This seems better than trying
    // to involve the user in resolving the issue.
    func processedAttachment(forAttachmentItem attachmentItem: SignalAttachmentItem) -> SignalAttachment {
        guard let imageEditorModel = attachmentItem.imageEditorModel else {
            // Image was not edited.
            return attachmentItem.attachment
        }
        guard imageEditorModel.isDirty() else {
            // Image editor has no changes.
            return attachmentItem.attachment
        }
        guard let dstImage = ImageEditorCanvasView.renderForOutput(model: imageEditorModel, transform: imageEditorModel.currentTransform()) else {
            owsFailDebug("Could not render for output.")
            return attachmentItem.attachment
        }
        var dataUTI = kUTTypeImage as String
        guard let dstData: Data = {
            let isLossy: Bool = attachmentItem.attachment.mimeType.caseInsensitiveCompare(OWSMimeTypeImageJpeg) == .orderedSame
            if isLossy {
                dataUTI = kUTTypeJPEG as String
                return dstImage.jpegData(compressionQuality: 0.9)
            } else {
                dataUTI = kUTTypePNG as String
                return dstImage.pngData()
            }
            }() else {
                owsFailDebug("Could not export for output.")
                return attachmentItem.attachment
        }
        guard let dataSource = DataSourceValue.dataSource(with: dstData, utiType: dataUTI) else {
            owsFailDebug("Could not prepare data source for output.")
            return attachmentItem.attachment
        }

        // Rewrite the filename's extension to reflect the output file format.
        var filename: String? = attachmentItem.attachment.sourceFilename
        if let sourceFilename = attachmentItem.attachment.sourceFilename {
            if let fileExtension: String = MIMETypeUtil.fileExtension(forUTIType: dataUTI) {
                filename = (sourceFilename as NSString).deletingPathExtension.appendingFileExtension(fileExtension)
            }
        }
        dataSource.sourceFilename = filename

        let dstAttachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: dataUTI, imageQuality: .medium)
        if let attachmentError = dstAttachment.error {
            owsFailDebug("Could not prepare attachment for output: \(attachmentError).")
            return attachmentItem.attachment
        }
        // Preserve caption text.
        dstAttachment.captionText = attachmentItem.captionText
        return dstAttachment
    }

    func attachmentItem(before currentItem: SignalAttachmentItem) -> SignalAttachmentItem? {
        guard let currentIndex = attachmentItems.firstIndex(of: currentItem) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        let index: Int = attachmentItems.index(before: currentIndex)
        guard let previousItem = attachmentItems[safe: index] else {
            // already at first item
            return nil
        }

        return previousItem
    }

    func attachmentItem(after currentItem: SignalAttachmentItem) -> SignalAttachmentItem? {
        guard let currentIndex = attachmentItems.firstIndex(of: currentItem) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        let index: Int = attachmentItems.index(after: currentIndex)
        guard let nextItem = attachmentItems[safe: index] else {
            // already at last item
            return nil
        }

        return nextItem
    }

    // MARK: - Event Handlers

    @objc
    func didTapTouchInterceptorView(gesture: UITapGestureRecognizer) {
        Logger.info("")

        isEditingCaptions = false
    }

    private func cancelPressed() {
        self.approvalDelegate?.attachmentApprovalDidCancel(self)
    }

    @objc func didTapCaption(sender: UIButton) {
        Logger.verbose("")

        isEditingCaptions = true
    }

    @objc func didTapCaptionDone(sender: UIButton) {
        Logger.verbose("")

        isEditingCaptions = false
    }
}

// MARK: -

extension AttachmentApprovalViewController: AttachmentTextToolbarDelegate {
    func attachmentTextToolbarDidBeginEditing(_ attachmentTextToolbar: AttachmentTextToolbar) {
        currentPageViewController.setAttachmentViewScale(.compact, animated: true)
    }

    func attachmentTextToolbarDidEndEditing(_ attachmentTextToolbar: AttachmentTextToolbar) {
        currentPageViewController.setAttachmentViewScale(.fullsize, animated: true)
    }

    func attachmentTextToolbarDidTapSend(_ attachmentTextToolbar: AttachmentTextToolbar) {
        // Toolbar flickers in and out if there are errors
        // and remains visible momentarily after share extension is dismissed.
        // It's easiest to just hide it at this point since we're done with it.
        currentPageViewController.shouldAllowAttachmentViewResizing = false
        attachmentTextToolbar.isUserInteractionEnabled = false
        attachmentTextToolbar.isHidden = true

        approvalDelegate?.attachmentApproval(self, didApproveAttachments: attachments, messageText: attachmentTextToolbar.messageText)
    }

    func attachmentTextToolbarDidChange(_ attachmentTextToolbar: AttachmentTextToolbar) {
        approvalDelegate?.attachmentApproval(self, didChangeMessageText: attachmentTextToolbar.messageText)
    }
}

// MARK: -

extension AttachmentApprovalViewController: AttachmentPrepViewControllerDelegate {
    func prepViewControllerUpdateNavigationBar() {
        updateNavigationBar()
    }

    func prepViewControllerUpdateControls() {
        updateInputAccessory()
    }
}

// MARK: GalleryRail

extension SignalAttachmentItem: GalleryRailItem {
    func isEqual(to other: GalleryRailItem) -> Bool {
        guard let otherItem: SignalAttachmentItem = other as? SignalAttachmentItem else { return false }
        
        return (self == otherItem)
    }
    
    func buildRailItemView() -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill

        getThumbnailImage().map { image in
            imageView.image = image
        }.retainUntilComplete()

        return imageView
    }
}

// MARK: -

extension AttachmentItemCollection: GalleryRailItemProvider {
    var railItems: [GalleryRailItem] {
        if isAddMoreVisible {
            return self.attachmentItems + [AddMoreRailItem()]
        } else {
            return self.attachmentItems
        }
    }
}

// MARK: -

extension AttachmentApprovalViewController: GalleryRailViewDelegate {
    public func galleryRailView(_ galleryRailView: GalleryRailView, didTapItem imageRailItem: GalleryRailItem) {
        if imageRailItem is AddMoreRailItem {
            self.approvalDelegate?.attachmentApprovalDidTapAddMore?(self)
            return
        }

        guard let targetItem = imageRailItem as? SignalAttachmentItem else {
            owsFailDebug("unexpected imageRailItem: \(imageRailItem)")
            return
        }

        guard let currentIndex = attachmentItems.firstIndex(of: currentItem) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return
        }

        guard let targetIndex = attachmentItems.firstIndex(of: targetItem) else {
            owsFailDebug("targetIndex was unexpectedly nil")
            return
        }

        let direction: UIPageViewController.NavigationDirection = currentIndex < targetIndex ? .forward : .reverse

        self.setCurrentItem(targetItem, direction: direction, animated: true)
    }
}

// MARK: -

enum KeyboardScenario {
    case hidden, editingMessage, editingCaption
}

// MARK: -

extension AttachmentApprovalViewController: ApprovalRailCellViewDelegate {
    func approvalRailCellView(_ approvalRailCellView: ApprovalRailCellView, didRemoveItem attachmentItem: SignalAttachmentItem) {
        remove(attachmentItem: attachmentItem)
    }

    func canRemoveApprovalRailCellView(_ approvalRailCellView: ApprovalRailCellView) -> Bool {
        return self.attachmentItems.count > 1
    }
}

// MARK: -

extension AttachmentApprovalViewController: AttachmentApprovalInputAccessoryViewDelegate {
    public func attachmentApprovalInputUpdateMediaRail() {
        updateMediaRail()
    }

    public func attachmentApprovalInputStartEditingCaptions() {
        isEditingCaptions = true
    }

    public func attachmentApprovalInputStopEditingCaptions() {
        isEditingCaptions = false
    }
}
