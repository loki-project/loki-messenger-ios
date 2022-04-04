//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit
import SessionUIKit

// Objc wrapper for the MediaGalleryItem struct
@objc
public class GalleryItemBox: NSObject {
    public let value: MediaGalleryItem

    init(_ value: MediaGalleryItem) {
        self.value = value
    }

    @objc
    public var attachmentStream: TSAttachmentStream {
        return value.attachmentStream
    }
}

private class Box<A> {
    var value: A
    init(_ val: A) {
        self.value = val
    }
}

fileprivate extension MediaDetailViewController {
    var galleryItem: MediaGalleryItem {
        return self.galleryItemBox.value
    }
}

class MediaPageViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, MediaDetailViewControllerDelegate, MediaGalleryDataSourceDelegate {

    private weak var mediaGalleryDataSource: MediaGalleryDataSource?

    private var cachedPages: [MediaGalleryItem: MediaDetailViewController] = [:]
    private var initialPage: MediaDetailViewController!

    public var currentViewController: MediaDetailViewController {
        return viewControllers!.first as! MediaDetailViewController
    }

    public var currentItem: MediaGalleryItem! {
        return currentViewController.galleryItemBox.value
    }

    public func setCurrentItem(_ item: MediaGalleryItem, direction: UIPageViewController.NavigationDirection, animated isAnimated: Bool) {
        guard let galleryPage = self.buildGalleryPage(galleryItem: item) else {
            owsFailDebug("unexpectedly unable to build new gallery page")
            return
        }

        updateTitle(item: item)
        updateCaption(item: item)
        setViewControllers([galleryPage], direction: direction, animated: isAnimated)
        updateFooterBarButtonItems(isPlayingVideo: false)
        updateMediaRail()
    }

    private let uiDatabaseConnection: YapDatabaseConnection

    private let showAllMediaButton: Bool
    private let sliderEnabled: Bool

    init(initialItem: MediaGalleryItem, mediaGalleryDataSource: MediaGalleryDataSource, uiDatabaseConnection: YapDatabaseConnection, options: MediaGalleryOption) {
        assert(uiDatabaseConnection.isInLongLivedReadTransaction())
        self.uiDatabaseConnection = uiDatabaseConnection
        self.showAllMediaButton = options.contains(.showAllMediaButton)
        self.sliderEnabled = options.contains(.sliderEnabled)
        self.mediaGalleryDataSource = mediaGalleryDataSource

        let kSpacingBetweenItems: CGFloat = 20

        let options: [UIPageViewController.OptionsKey: Any] = [.interPageSpacing: kSpacingBetweenItems]
        super.init(transitionStyle: .scroll,
                   navigationOrientation: .horizontal,
                   options: options)

        self.dataSource = self
        self.delegate = self

        guard let initialPage = self.buildGalleryPage(galleryItem: initialItem) else {
            owsFailDebug("unexpectedly unable to build initial gallery item")
            return
        }
        self.initialPage = initialPage
        self.setViewControllers([initialPage], direction: .forward, animated: false, completion: nil)
    }

    @available(*, unavailable, message: "Unimplemented")
    required init?(coder: NSCoder) {
        notImplemented()
    }

    deinit {
        Logger.debug("deinit")
    }

    // MARK: - Subview

    // MARK: Bottom Bar
    var bottomContainer: UIView!
    var footerBar: UIToolbar!
    let captionContainerView: CaptionContainerView = CaptionContainerView()
    var galleryRailView: GalleryRailView = GalleryRailView()

    var pagerScrollView: UIScrollView!

    // MARK: UIViewController overrides

    override func viewDidLoad() {
        super.viewDidLoad()

        // Navigation

        // Note: using a custom leftBarButtonItem breaks the interactive pop gesture, but we don't want to be able
        // to swipe to go back in the pager view anyway, instead swiping back should show the next page.
        let backButton = OWSViewController.createOWSBackButton(withTarget: self, selector: #selector(didPressDismissButton))
        self.navigationItem.leftBarButtonItem = backButton

        self.navigationItem.titleView = portraitHeaderView

        if showAllMediaButton {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: MediaStrings.allMedia, style: .plain, target: self, action: #selector(didPressAllMediaButton))
        }

        // Even though bars are opaque, we want content to be layed out behind them.
        // The bars might obscure part of the content, but they can easily be hidden by tapping
        // The alternative would be that content would shift when the navbars hide.
        self.extendedLayoutIncludesOpaqueBars = true
        self.automaticallyAdjustsScrollViewInsets = false

        // Get reference to paged content which lives in a scrollView created by the superclass
        // We show/hide this content during presentation
        for view in self.view.subviews {
            if let pagerScrollView = view as? UIScrollView {
                self.pagerScrollView = pagerScrollView
            }
        }

        // Hack to avoid "page" bouncing when not in gallery view.
        // e.g. when getting to media details via message details screen, there's only
        // one "Page" so the bounce doesn't make sense.
        pagerScrollView.isScrollEnabled = sliderEnabled
        pagerScrollViewContentOffsetObservation = pagerScrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, change in
            guard let strongSelf = self else { return }
            strongSelf.pagerScrollView(strongSelf.pagerScrollView, contentOffsetDidChange: change)
        }

        // Views
        pagerScrollView.backgroundColor = Colors.navigationBarBackground
        
        view.backgroundColor = Colors.navigationBarBackground

        captionContainerView.delegate = self
        updateCaptionContainerVisibility()

        galleryRailView.delegate = self
        galleryRailView.autoSetDimension(.height, toSize: 72)

        let footerBar = self.makeClearToolbar()
        self.footerBar = footerBar
        footerBar.tintColor = Colors.text
        footerBar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: UIBarMetrics.default)
        footerBar.setShadowImage(UIImage(), forToolbarPosition: .any)
        footerBar.isTranslucent = false
        footerBar.barTintColor = Colors.navigationBarBackground

        let bottomContainer = UIView()
        self.bottomContainer = bottomContainer
        bottomContainer.backgroundColor = Colors.navigationBarBackground

        let bottomStack = UIStackView(arrangedSubviews: [captionContainerView, galleryRailView, footerBar])
        bottomStack.axis = .vertical
        bottomContainer.addSubview(bottomStack)
        bottomStack.autoPinEdgesToSuperviewEdges()

        self.view.addSubview(bottomContainer)
        bottomContainer.autoPinWidthToSuperview()
        bottomContainer.autoPinEdge(.bottom, to: .bottom, of: view)
        footerBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        footerBar.autoSetDimension(.height, toSize: 44)

        updateTitle()
        updateCaption(item: currentItem)
        updateMediaRail()
        updateFooterBarButtonItems(isPlayingVideo: true)

        // Gestures

        let verticalSwipe = UISwipeGestureRecognizer(target: self, action: #selector(didSwipeView))
        verticalSwipe.direction = [.up, .down]
        view.addGestureRecognizer(verticalSwipe)
        
        let navigationBar = navigationController!.navigationBar
        navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        navigationBar.shadowImage = UIImage()
        navigationBar.isTranslucent = false
        navigationBar.barTintColor = Colors.navigationBarBackground
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let isLandscape = size.width > size.height
        self.navigationItem.titleView = isLandscape ? nil : self.portraitHeaderView
    }

    override func didReceiveMemoryWarning() {
        Logger.info("")
        super.didReceiveMemoryWarning()

        self.cachedPages = [:]
    }

    // MARK: KVO

    var pagerScrollViewContentOffsetObservation: NSKeyValueObservation?
    func pagerScrollView(_ pagerScrollView: UIScrollView, contentOffsetDidChange change: NSKeyValueObservedChange<CGPoint>) {
        guard let newValue = change.newValue else {
            owsFailDebug("newValue was unexpectedly nil")
            return
        }

        let width = pagerScrollView.frame.size.width
        guard width > 0 else {
            return
        }
        let ratioComplete = abs((newValue.x - width) / width)
        captionContainerView.updatePagerTransition(ratioComplete: ratioComplete)
    }

    // MARK: View Helpers

    public func willBePresentedAgain() {
        updateFooterBarButtonItems(isPlayingVideo: false)
    }

    public func wasPresented() {
        let currentViewController = self.currentViewController

        if currentViewController.galleryItem.isVideo {
            currentViewController.playVideo()
        }
    }

    private func makeClearToolbar() -> UIToolbar {
        let toolbar = UIToolbar()

        toolbar.backgroundColor = Colors.navigationBarBackground

        // hide 1px top-border
        toolbar.clipsToBounds = true

        return toolbar
    }

    private var shouldHideToolbars: Bool = false {
        didSet {
            if (oldValue == shouldHideToolbars) {
                return
            }

            // Hiding the status bar affects the positioning of the navbar. We don't want to show that in an animation, it's
            // better to just have everythign "flit" in/out.
            UIApplication.shared.setStatusBarHidden(shouldHideToolbars, with: .none)
            self.navigationController?.setNavigationBarHidden(shouldHideToolbars, animated: false)

            UIView.animate(withDuration: 0.1) {
                self.currentViewController.setShouldHideToolbars(self.shouldHideToolbars)
                self.bottomContainer.isHidden = self.shouldHideToolbars
            }
        }
    }

    // MARK: Bar Buttons

    lazy var shareBarButton: UIBarButtonItem = {
        let shareBarButton = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(didPressShare))
        shareBarButton.tintColor = Colors.text
        return shareBarButton
    }()

    lazy var deleteBarButton: UIBarButtonItem = {
        let deleteBarButton = UIBarButtonItem(barButtonSystemItem: .trash,
                                              target: self,
                                              action: #selector(didPressDelete))
        deleteBarButton.tintColor = Colors.text
        return deleteBarButton
    }()

    func buildFlexibleSpace() -> UIBarButtonItem {
        return UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
    }

    lazy var videoPlayBarButton: UIBarButtonItem = {
        let videoPlayBarButton = UIBarButtonItem(barButtonSystemItem: .play, target: self, action: #selector(didPressPlayBarButton))
        videoPlayBarButton.tintColor = Colors.text
        return videoPlayBarButton
    }()

    lazy var videoPauseBarButton: UIBarButtonItem = {
        let videoPauseBarButton = UIBarButtonItem(barButtonSystemItem: .pause, target: self, action:
            #selector(didPressPauseBarButton))
        videoPauseBarButton.tintColor = Colors.text
        return videoPauseBarButton
    }()

    private func updateFooterBarButtonItems(isPlayingVideo: Bool) {
        // TODO do we still need this? seems like a vestige
        // from when media detail view was used for attachment approval
        if self.footerBar == nil {
            owsFailDebug("No footer bar visible.")
            return
        }

        var toolbarItems: [UIBarButtonItem] = [
            shareBarButton,
            buildFlexibleSpace()
        ]

        if (self.currentItem.isVideo) {
            toolbarItems += [
                isPlayingVideo ? self.videoPauseBarButton : self.videoPlayBarButton,
                buildFlexibleSpace()
            ]
        }

        toolbarItems.append(deleteBarButton)

        self.footerBar.setItems(toolbarItems, animated: false)
    }

    func updateMediaRail() {
        guard let currentItem = self.currentItem else {
            owsFailDebug("currentItem was unexpectedly nil")
            return
        }

        galleryRailView.configureCellViews(itemProvider: currentItem.album,
                                           focusedItem: currentItem,
                                           cellViewBuilder: { _ in return GalleryRailCellView() })
    }

    // MARK: Actions

    @objc
    public func didPressAllMediaButton(sender: Any) {
        Logger.debug("")

        currentViewController.stopAnyVideo()

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
            return
        }
        mediaGalleryDataSource.showAllMedia(focusedItem: currentItem)
    }

    @objc
    public func didSwipeView(sender: Any) {
        Logger.debug("")

        self.dismissSelf(animated: true)
    }

    @objc
    public func didPressDismissButton(_ sender: Any) {
        dismissSelf(animated: true)
    }

    @objc
    public func didPressShare(_ sender: Any) {
        guard let currentViewController = self.viewControllers?[0] as? MediaDetailViewController else {
            owsFailDebug("currentViewController was unexpectedly nil")
            return
        }

        let attachmentStream = currentViewController.galleryItem.attachmentStream

        AttachmentSharing.showShareUI(forAttachment: attachmentStream) { activityType in
            guard let activityType = activityType, activityType == .saveToCameraRoll,
                let tsMessage = currentViewController.galleryItem.message as? TSIncomingMessage, let thread = tsMessage.thread as? TSContactThread else { return }
            let message = DataExtractionNotification()
            message.kind = .mediaSaved(timestamp: tsMessage.timestamp)
            Storage.write { transaction in
                MessageSender.send(message, in: thread, using: transaction)
            }
            
        }
    }

    @objc
    public func didPressDelete(_ sender: Any) {
        guard let currentViewController = self.viewControllers?[0] as? MediaDetailViewController else {
            owsFailDebug("currentViewController was unexpectedly nil")
            return
        }

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
            return
        }

        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let deleteAction = UIAlertAction(title: NSLocalizedString("delete_message_for_me", comment: ""),
                                         style: .destructive) { _ in
                                            let deletedItem = currentViewController.galleryItem
                                            mediaGalleryDataSource.delete(items: [deletedItem], initiatedBy: self)
        }
        actionSheet.addAction(OWSAlerts.cancelAction)
        actionSheet.addAction(deleteAction)

        self.presentAlert(actionSheet)
    }

    // MARK: MediaGalleryDataSourceDelegate

    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, willDelete items: [MediaGalleryItem], initiatedBy: AnyObject) {
        Logger.debug("")

        guard let currentItem = self.currentItem else {
            owsFailDebug("currentItem was unexpectedly nil")
            return
        }

        guard items.contains(currentItem) else {
            Logger.debug("irrelevant item")
            return
        }

        // If we setCurrentItem with (animated: true) while this VC is in the background, then
        // the next/previous cache isn't expired, and we're able to swipe back to the just-deleted vc.
        // So to get the correct behavior, we should only animate these transitions when this
        // vc is in the foreground
        let isAnimated = initiatedBy === self

        if !self.sliderEnabled {
            // In message details, which doesn't use the slider, so don't swap pages.
        } else if let nextItem = mediaGalleryDataSource.galleryItem(after: currentItem) {
            self.setCurrentItem(nextItem, direction: .forward, animated: isAnimated)
        } else if let previousItem = mediaGalleryDataSource.galleryItem(before: currentItem) {
            self.setCurrentItem(previousItem, direction: .reverse, animated: isAnimated)
        } else {
            // else we deleted the last piece of media, return to the conversation view
            self.dismissSelf(animated: true)
        }
    }

    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, deletedSections: IndexSet, deletedItems: [IndexPath]) {
        // no-op
    }

    @objc
    public func didPressPlayBarButton(_ sender: Any) {
        guard let currentViewController = self.viewControllers?[0] as? MediaDetailViewController else {
            owsFailDebug("currentViewController was unexpectedly nil")
            return
        }
        currentViewController.didPressPlayBarButton(sender)
    }

    @objc
    public func didPressPauseBarButton(_ sender: Any) {
        guard let currentViewController = self.viewControllers?[0] as? MediaDetailViewController else {
            owsFailDebug("currentViewController was unexpectedly nil")
            return
        }
        currentViewController.didPressPauseBarButton(sender)
    }

    // MARK: UIPageViewControllerDelegate

    var pendingViewController: MediaDetailViewController?
    public func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        Logger.debug("")

        assert(pendingViewControllers.count == 1)
        pendingViewControllers.forEach { viewController in
            guard let pendingViewController = viewController as? MediaDetailViewController else {
                owsFailDebug("unexpected mediaDetailViewController: \(viewController)")
                return
            }
            self.pendingViewController = pendingViewController

            if let pendingCaptionText = pendingViewController.galleryItem.captionForDisplay, pendingCaptionText.count > 0 {
                self.captionContainerView.pendingText = pendingCaptionText
            } else {
                self.captionContainerView.pendingText = nil
            }

            // Ensure upcoming page respects current toolbar status
            pendingViewController.setShouldHideToolbars(self.shouldHideToolbars)
        }
    }

    public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted: Bool) {
        Logger.debug("")

        assert(previousViewControllers.count == 1)
        previousViewControllers.forEach { viewController in
            guard let previousPage = viewController as? MediaDetailViewController else {
                owsFailDebug("unexpected mediaDetailViewController: \(viewController)")
                return
            }

            // Do any cleanup for the no-longer visible view controller
            if transitionCompleted {
                pendingViewController = nil

                // This can happen when trying to page past the last (or first) view controller
                // In that case, we don't want to change the captionView.
                if (previousPage != currentViewController) {
                    captionContainerView.completePagerTransition()
                }

                updateTitle()
                updateMediaRail()
                previousPage.zoomOut(animated: false)
                previousPage.stopAnyVideo()
                updateFooterBarButtonItems(isPlayingVideo: false)
            } else {
                captionContainerView.pendingText = nil
            }
        }
    }

    // MARK: UIPageViewControllerDataSource

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        Logger.debug("")

        guard let previousDetailViewController = viewController as? MediaDetailViewController else {
            owsFailDebug("unexpected viewController: \(viewController)")
            return nil
        }

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
            return nil
        }

        let previousItem = previousDetailViewController.galleryItem
        guard let nextItem: MediaGalleryItem = mediaGalleryDataSource.galleryItem(before: previousItem) else {
            return nil
        }

        guard let nextPage: MediaDetailViewController = buildGalleryPage(galleryItem: nextItem) else {
            return nil
        }

        return nextPage
    }

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        Logger.debug("")

        guard let previousDetailViewController = viewController as? MediaDetailViewController else {
            owsFailDebug("unexpected viewController: \(viewController)")
            return nil
        }

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
            return nil
        }

        let previousItem = previousDetailViewController.galleryItem
        guard let nextItem = mediaGalleryDataSource.galleryItem(after: previousItem) else {
            // no more pages
            return nil
        }

        guard let nextPage: MediaDetailViewController = buildGalleryPage(galleryItem: nextItem) else {
            return nil
        }

        return nextPage
    }

    private func buildGalleryPage(galleryItem: MediaGalleryItem) -> MediaDetailViewController? {

        if let cachedPage = cachedPages[galleryItem] {
            Logger.debug("cache hit.")
            return cachedPage
        }

        Logger.debug("cache miss.")
        var fetchedItem: ConversationViewItem?
        self.uiDatabaseConnection.read { transaction in
            let message = galleryItem.message
            let thread = message.thread(with: transaction)
            fetchedItem = ConversationInteractionViewItem(interaction: message,
                                                          isGroupThread: thread.isGroupThread(),
                                                          transaction: transaction)
        }

        guard let viewItem = fetchedItem else {
            owsFailDebug("viewItem was unexpectedly nil")
            return nil
        }

        let viewController = MediaDetailViewController(galleryItemBox: GalleryItemBox(galleryItem), viewItem: viewItem)
        viewController.delegate = self

        cachedPages[galleryItem] = viewController
        return viewController
    }

    public func dismissSelf(animated isAnimated: Bool, completion: (() -> Void)? = nil) {
        // Swapping mediaView for presentationView will be perceptible if we're not zoomed out all the way.
        // currentVC
        currentViewController.zoomOut(animated: true)
        currentViewController.stopAnyVideo()

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
            self.presentingViewController?.dismiss(animated: true)

            return
        }

        if IsLandscapeOrientationEnabled() {
            mediaGalleryDataSource.dismissMediaDetailViewController(self,
                                                                    animated: isAnimated,
                                                                    completion: completion)
        } else {
            mediaGalleryDataSource.dismissMediaDetailViewController(self, animated: isAnimated) {
                UIDevice.current.ows_setOrientation(.portrait)
                completion?()
            }
        }
    }

    // MARK: MediaDetailViewControllerDelegate

    @objc
    public func mediaDetailViewControllerDidTapMedia(_ mediaDetailViewController: MediaDetailViewController) {
        Logger.debug("")

        self.shouldHideToolbars = !self.shouldHideToolbars
    }

    public func mediaDetailViewController(_ mediaDetailViewController: MediaDetailViewController, requestDelete attachment: TSAttachment) {
        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
            self.presentingViewController?.dismiss(animated: true)

            return
        }

        guard let galleryItem = self.mediaGalleryDataSource?.galleryItems.first(where: { $0.attachmentStream == attachment }) else {
            owsFailDebug("galleryItem was unexpectedly nil")
            self.presentingViewController?.dismiss(animated: true)

            return
        }

        dismissSelf(animated: true) {
            mediaGalleryDataSource.delete(items: [galleryItem], initiatedBy: self)
        }
    }

    public func mediaDetailViewController(_ mediaDetailViewController: MediaDetailViewController, isPlayingVideo: Bool) {
        guard mediaDetailViewController == currentViewController else {
            Logger.verbose("ignoring stale delegate.")
            return
        }

        self.shouldHideToolbars = isPlayingVideo
        self.updateFooterBarButtonItems(isPlayingVideo: isPlayingVideo)
    }

    // MARK: Dynamic Header

    private func senderName(message: TSMessage) -> String {
        switch message {
        case let incomingMessage as TSIncomingMessage:
            let publicKey = incomingMessage.authorId
            let context = Contact.context(for: incomingMessage.thread)
            return Storage.shared.getContact(with: publicKey)?.displayName(for: context) ?? publicKey
        case is TSOutgoingMessage:
            return NSLocalizedString("MEDIA_GALLERY_SENDER_NAME_YOU", comment: "Short sender label for media sent by you")
        default:
            owsFailDebug("Unknown message type: \(type(of: message))")
            return ""
        }
    }

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        return formatter
    }()

    lazy private var portraitHeaderNameLabel: UILabel = {
        let label = UILabel()
        label.textColor = Colors.text
        label.font = .systemFont(ofSize: Values.mediumFontSize)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        return label
    }()

    lazy private var portraitHeaderDateLabel: UILabel = {
        let label = UILabel()
        label.textColor = Colors.text
        label.font = .systemFont(ofSize: Values.verySmallFontSize)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8

        return label
    }()

    private lazy var portraitHeaderView: UIView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 0
        stackView.distribution = .fillProportionally
        stackView.addArrangedSubview(portraitHeaderNameLabel)
        stackView.addArrangedSubview(portraitHeaderDateLabel)

        let containerView = UIView()
        containerView.layoutMargins = UIEdgeInsets(top: 2, left: 8, bottom: 4, right: 8)

        containerView.addSubview(stackView)

        stackView.autoPinEdge(toSuperviewMargin: .top, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .bottom, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
        stackView.setContentHuggingHigh()
        stackView.autoCenterInSuperview()

        return containerView
    }()

    private func updateTitle() {
        guard let currentItem = self.currentItem else {
            owsFailDebug("currentItem was unexpectedly nil")
            return
        }
        updateTitle(item: currentItem)
    }

    private func updateCaption(item: MediaGalleryItem) {
        captionContainerView.currentText = item.captionForDisplay
    }

    private func updateTitle(item: MediaGalleryItem) {
        let name = senderName(message: item.message)
        portraitHeaderNameLabel.text = name

        // use sent date
        let date = Date(timeIntervalSince1970: Double(item.message.timestamp) / 1000)
        let formattedDate = dateFormatter.string(from: date)
        portraitHeaderDateLabel.text = formattedDate

        let landscapeHeaderFormat = NSLocalizedString("MEDIA_GALLERY_LANDSCAPE_TITLE_FORMAT", comment: "embeds {{sender name}} and {{sent datetime}}, e.g. 'Sarah on 10/30/18, 3:29'")
        let landscapeHeaderText = String(format: landscapeHeaderFormat, name, formattedDate)
        self.title = landscapeHeaderText
        self.navigationItem.title = landscapeHeaderText
    }
}

extension MediaGalleryItem: GalleryRailItem {
    public func buildRailItemView() -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        getRailImage().map { [weak imageView] image in
            guard let imageView = imageView else { return }
            imageView.image = image
        }.retainUntilComplete()

        return imageView
    }

    public func getRailImage() -> Guarantee<UIImage> {
        return Guarantee<UIImage> { fulfill in
            if let image = self.thumbnailImage(async: { fulfill($0) }) {
                fulfill(image)
            }
        }
    }
}

extension MediaGalleryAlbum: GalleryRailItemProvider {
    var railItems: [GalleryRailItem] {
        return self.items
    }
}

extension MediaPageViewController: GalleryRailViewDelegate {
    func galleryRailView(_ galleryRailView: GalleryRailView, didTapItem imageRailItem: GalleryRailItem) {
        guard let targetItem = imageRailItem as? MediaGalleryItem else {
            owsFailDebug("unexpected imageRailItem: \(imageRailItem)")
            return
        }

        let direction: UIPageViewController.NavigationDirection
        direction = currentItem.albumIndex < targetItem.albumIndex ? .forward : .reverse

        self.setCurrentItem(targetItem, direction: direction, animated: true)
    }
}

extension MediaPageViewController: CaptionContainerViewDelegate {

    func captionContainerViewDidUpdateText(_ captionContainerView: CaptionContainerView) {
        updateCaptionContainerVisibility()
    }

    // MARK: Helpers

    func updateCaptionContainerVisibility() {
        if let currentText = captionContainerView.currentText, currentText.count > 0 {
            captionContainerView.isHidden = false
            return
        }

        if let pendingText = captionContainerView.pendingText, pendingText.count > 0 {
            captionContainerView.isHidden = false
            return
        }

        captionContainerView.isHidden = true
    }
}
