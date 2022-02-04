//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit

class MediaZoomAnimationController: NSObject {
    private let item: Media

    init(image: UIImage) {
        item = .image(image)
    }

    init(galleryItem: MediaGalleryItem) {
        item = .gallery(galleryItem)
    }
}

extension MediaZoomAnimationController: UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.4
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
        
        // 'view(forKey: .to)' will be nil when using this transition for a modal dismiss, in which
        // case we want to use the 'toVC.view' but need to ensure we add it back to it's original
        // parent afterwards so we don't break the view hierarchy
        //
        // Note: We *MUST* call 'layoutIfNeeded' prior to 'toContextProvider.mediaPresentationContext'
        // as the 'toContextProvider.mediaPresentationContext' is dependant on it having the correct
        // positioning (and the navBar sizing isn't correct until after layout)
        let toView: UIView = (transitionContext.view(forKey: .to) ?? toVC.view)
        let oldToViewSuperview: UIView? = toView.superview
        toView.layoutIfNeeded()

        guard let fromMediaContext: MediaPresentationContext = fromContextProvider.mediaPresentationContext(item: item, in: containerView) else {
            transitionContext.completeTransition(false)
            return
        }
        
        guard let toMediaContext: MediaPresentationContext = toContextProvider.mediaPresentationContext(item: item, in: containerView) else {
            transitionContext.completeTransition(false)
            return
        }

        guard let presentationImage: UIImage = item.image else {
            transitionContext.completeTransition(true)
            return
        }
        
        let duration: CGFloat = transitionDuration(using: transitionContext)
        
        fromMediaContext.mediaView.alpha = 0
        toMediaContext.mediaView.alpha = 0
        
        let fromSnapshotView: UIView = (fromVC.view.snapshotView(afterScreenUpdates: false) ?? UIView())
        containerView.addSubview(fromSnapshotView)
        
        toView.frame = containerView.bounds
        toView.alpha = 0
        containerView.addSubview(toView)
        
        let transitionView = UIImageView(image: presentationImage)
        transitionView.frame = fromMediaContext.presentationFrame
        transitionView.contentMode = MediaView.contentMode
        transitionView.layer.masksToBounds = true
        transitionView.layer.cornerRadius = fromMediaContext.cornerRadius
        transitionView.layer.maskedCorners = fromMediaContext.cornerMask
        containerView.addSubview(transitionView)
        
        let overshootPercentage: CGFloat = 0.15
        let overshootFrame: CGRect = CGRect(
            x: (toMediaContext.presentationFrame.minX + ((toMediaContext.presentationFrame.minX - fromMediaContext.presentationFrame.minX) * overshootPercentage)),
            y: (toMediaContext.presentationFrame.minY + ((toMediaContext.presentationFrame.minY - fromMediaContext.presentationFrame.minY) * overshootPercentage)),
            width: (toMediaContext.presentationFrame.width + ((toMediaContext.presentationFrame.width - fromMediaContext.presentationFrame.width) * overshootPercentage)),
            height: (toMediaContext.presentationFrame.height + ((toMediaContext.presentationFrame.height - fromMediaContext.presentationFrame.height) * overshootPercentage))
        )
        
        // Add any UI elements which should appear above the media view
        let fromTransitionalOverlayView: UIView? = {
            guard let (overlayView, overlayViewFrame) = fromContextProvider.snapshotOverlayView(in: containerView) else {
                return nil
            }
            
            overlayView.frame = overlayViewFrame
            containerView.addSubview(overlayView)
            
            return overlayView
        }()
        let toTransitionalOverlayView: UIView? = {
            guard let (overlayView, overlayViewFrame) = toContextProvider.snapshotOverlayView(in: containerView) else {
                return nil
            }
            
            overlayView.alpha = 0
            overlayView.frame = overlayViewFrame
            containerView.addSubview(overlayView)
            
            return overlayView
        }()
        
        UIView.animate(
            withDuration: (duration / 2),
            delay: 0,
            options: .curveEaseOut,
            animations: {
                // Only fade out the 'fromTransitionalOverlayView' if it's bigger than the destination
                // one (makes it look cleaner as you don't get the crossfade effect)
                if (fromTransitionalOverlayView?.frame.size.height ?? 0) > (toTransitionalOverlayView?.frame.size.height ?? 0) {
                    fromTransitionalOverlayView?.alpha = 0
                }
                
                toView.alpha = 1
                toTransitionalOverlayView?.alpha = 1
                transitionView.frame = overshootFrame
                transitionView.layer.cornerRadius = toMediaContext.cornerRadius
            },
            completion: { _ in
                UIView.animate(
                    withDuration: (duration / 2),
                    delay: 0,
                    options: .curveEaseInOut,
                    animations: {
                        transitionView.frame = toMediaContext.presentationFrame
                    },
                    completion: { _ in
                        transitionView.removeFromSuperview()
                        fromSnapshotView.removeFromSuperview()
                        fromTransitionalOverlayView?.removeFromSuperview()
                        toTransitionalOverlayView?.removeFromSuperview()
                        
                        toMediaContext.mediaView.alpha = 1
                        fromMediaContext.mediaView.alpha = 1
                        
                        // Need to ensure we add the 'toView' back to it's old superview if it had one
                        oldToViewSuperview?.addSubview(toView)
                        
                        transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
                    }
                )
            }
        )
    }
}
