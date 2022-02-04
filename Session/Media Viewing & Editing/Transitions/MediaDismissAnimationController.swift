//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit

class MediaDismissAnimationController: NSObject {
    private let item: Media
    public let interactionController: MediaInteractiveDismiss?

    var fromView: UIView?
    var transitionView: UIView?
    var fromTransitionalOverlayView: UIView?
    var toTransitionalOverlayView: UIView?
    var fromMediaFrame: CGRect?
    var pendingCompletion: (() -> ())?

    init(galleryItem: MediaGalleryItem, interactionController: MediaInteractiveDismiss? = nil) {
        self.item = .gallery(galleryItem)
        self.interactionController = interactionController
    }

    init(image: UIImage, interactionController: MediaInteractiveDismiss? = nil) {
        self.item = .image(image)
        self.interactionController = interactionController
    }
}

extension MediaDismissAnimationController: UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.3
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let containerView = transitionContext.containerView
        let fromContextProvider: MediaPresentationContextProvider
        let toContextProvider: MediaPresentationContextProvider

        guard let fromVC: UIViewController = transitionContext.viewController(forKey: .from) else {
            transitionContext.completeTransition(false)
            return
        }
        guard let toVC: UIViewController = transitionContext.viewController(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }
        
        switch fromVC {
            case let contextProvider as MediaPresentationContextProvider:
                fromContextProvider = contextProvider
            
            case let navController as UINavigationController:
                guard let contextProvider = navController.topViewController as? MediaPresentationContextProvider else {
                    transitionContext.completeTransition(false)
                    return
                }
                
                fromContextProvider = contextProvider
                
            default:
                transitionContext.completeTransition(false)
                return
        }
        
        switch toVC {
            case let contextProvider as MediaPresentationContextProvider:
                toContextProvider = contextProvider
                
            case let navController as UINavigationController:
                guard let contextProvider = navController.topViewController as? MediaPresentationContextProvider else {
                    transitionContext.completeTransition(false)
                    return
                }
                
                toContextProvider = contextProvider
                
            default:
                transitionContext.completeTransition(false)
                return
        }

        guard let fromMediaContext: MediaPresentationContext = fromContextProvider.mediaPresentationContext(item: item, in: containerView) else {
            transitionContext.completeTransition(false)
            return
        }
        
        guard let presentationImage: UIImage = item.image else {
            transitionContext.completeTransition(true)
            return
        }
        
        // fromView will be nil if doing a presentation, in which case we don't want to add the view -
        // it will automatically be added to the view hierarchy, in front of the VC we're presenting from
        if let fromView: UIView = transitionContext.view(forKey: .from) {
            self.fromView = fromView
            containerView.addSubview(fromView)
        }
        
        // toView will be nil if doing a modal dismiss, in which case we don't want to add the view -
        // it's already in the view hierarchy, behind the VC we're dismissing.
        if let toView: UIView = transitionContext.view(forKey: .to) {
            containerView.insertSubview(toView, at: 0)
        }
        
        let toMediaContext: MediaPresentationContext? = toContextProvider.mediaPresentationContext(item: item, in: containerView)
        let duration: CGFloat = transitionDuration(using: transitionContext)
        
        fromMediaContext.mediaView.alpha = 0.0
        toMediaContext?.mediaView.alpha = 0.0

        let transitionView = UIImageView(image: presentationImage)
        transitionView.frame = fromMediaContext.presentationFrame
        transitionView.contentMode = MediaView.contentMode
        transitionView.layer.masksToBounds = true
        transitionView.layer.cornerRadius = fromMediaContext.cornerRadius
        transitionView.layer.maskedCorners = (toMediaContext?.cornerMask ?? fromMediaContext.cornerMask)
        containerView.addSubview(transitionView)
        
        // Add any UI elements which should appear above the media view
        self.fromTransitionalOverlayView = {
            guard let (overlayView, overlayViewFrame) = fromContextProvider.snapshotOverlayView(in: containerView) else {
                return nil
            }
            
            overlayView.frame = overlayViewFrame
            containerView.addSubview(overlayView)
            
            return overlayView
        }()
        self.toTransitionalOverlayView = { [weak self] in
            guard let (overlayView, overlayViewFrame) = toContextProvider.snapshotOverlayView(in: containerView) else {
                return nil
            }
            
            // Only fade in the 'toTransitionalOverlayView' if it's bigger than the origin
            // one (makes it look cleaner as you don't get the crossfade effect)
            if (self?.fromTransitionalOverlayView?.frame.size.height ?? 0) > overlayViewFrame.height {
                overlayView.alpha = 0
            }
            
            overlayView.frame = overlayViewFrame
            
            if let fromTransitionalOverlayView = self?.fromTransitionalOverlayView {
                containerView.insertSubview(overlayView, belowSubview: fromTransitionalOverlayView)
            }
            else {
                containerView.addSubview(overlayView)
            }
            
            return overlayView
        }()
        
        self.transitionView = transitionView
        self.fromMediaFrame = transitionView.frame
        
        self.pendingCompletion = {
            let destinationFromAlpha: CGFloat
            let destinationFrame: CGRect
            let destinationCornerRadius: CGFloat
            
            if transitionContext.transitionWasCancelled {
                destinationFromAlpha = 1
                destinationFrame = fromMediaContext.presentationFrame
                destinationCornerRadius = fromMediaContext.cornerRadius
            }
            else if let toMediaContext: MediaPresentationContext = toMediaContext {
                destinationFromAlpha = 0
                destinationFrame = toMediaContext.presentationFrame
                destinationCornerRadius = toMediaContext.cornerRadius
            }
            else {
                // `toMediaContext` can be nil if the target item is scrolled off of the
                // contextProvider's screen, so we synthesize a context to dismiss the item
                // off screen
                destinationFromAlpha = 0
                destinationFrame = fromMediaContext.presentationFrame
                    .offsetBy(dx: 0, dy: (containerView.bounds.height * 2))
                destinationCornerRadius = fromMediaContext.cornerRadius
            }
            
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: { [weak self] in
                    self?.fromTransitionalOverlayView?.alpha = destinationFromAlpha
                    self?.fromView?.alpha = destinationFromAlpha
                    self?.toTransitionalOverlayView?.alpha = (1.0 - destinationFromAlpha)
                    transitionView.frame = destinationFrame
                    transitionView.layer.cornerRadius = destinationCornerRadius
                },
                completion: { [weak self] _ in
                    self?.fromView?.alpha = 1
                    fromMediaContext.mediaView.alpha = 1
                    toMediaContext?.mediaView.alpha = 1
                    transitionView.removeFromSuperview()
                    self?.fromTransitionalOverlayView?.removeFromSuperview()
                    self?.toTransitionalOverlayView?.removeFromSuperview()
                    
                    if transitionContext.transitionWasCancelled {
                        // the "to" view will be nil if we're doing a modal dismiss, in which case
                        // we wouldn't want to remove the toView.
                        transitionContext.view(forKey: .to)?.removeFromSuperview()
                    }
                    else {
                        transitionContext.view(forKey: .from)?.removeFromSuperview()
                    }

                    transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
                }
            )
        }

        // The interactive transition will call the 'pendingCompletion' when it completes so don't call it here
        guard !transitionContext.isInteractive else { return }
        
        self.pendingCompletion?()
        self.pendingCompletion = nil
    }
}

extension MediaDismissAnimationController: InteractiveDismissDelegate {
    func interactiveDismissUpdate(_ interactiveDismiss: UIPercentDrivenInteractiveTransition, didChangeTouchOffset offset: CGPoint) {
        guard let transitionView: UIView = transitionView else { return } // Transition hasn't started yet
        guard let fromMediaFrame: CGRect = fromMediaFrame else { return }

        fromView?.alpha = (1.0 - interactiveDismiss.percentComplete)
        transitionView.center = fromMediaFrame.offsetBy(dx: offset.x, dy: offset.y).center
    }

    func interactiveDismissDidFinish(_ interactiveDismiss: UIPercentDrivenInteractiveTransition) {
        self.pendingCompletion?()
        self.pendingCompletion = nil
    }
}
