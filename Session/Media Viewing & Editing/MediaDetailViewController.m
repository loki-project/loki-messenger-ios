//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "MediaDetailViewController.h"
#import "AttachmentSharing.h"
#import "ConversationViewItem.h"
#import "Session-Swift.h"
#import "TSAttachmentStream.h"
#import "TSInteraction.h"
#import "UIColor+OWS.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import <AVKit/AVKit.h>
#import <MediaPlayer/MPMoviePlayerViewController.h>
#import <MediaPlayer/MediaPlayer.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <SessionUtilitiesKit/NSData+Image.h>
#import <YYImage/YYImage.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@interface MediaDetailViewController () <UIScrollViewDelegate,
    UIGestureRecognizerDelegate,
    PlayerProgressBarDelegate,
    OWSVideoPlayerDelegate>

@property (nonatomic) UIScrollView *scrollView;
@property (nonatomic) UIView *mediaView;
@property (nonatomic) UIView *presentationView;
@property (nonatomic) UIView *replacingView;
@property (nonatomic) UIButton *shareButton;

@property (nonatomic) TSAttachmentStream *attachmentStream;
@property (nonatomic, nullable) id<ConversationViewItem> viewItem;
@property (nonatomic, nullable) UIImage *image;

@property (nonatomic, nullable) OWSVideoPlayer *videoPlayer;
@property (nonatomic, nullable) UIButton *playVideoButton;
@property (nonatomic, nullable) PlayerProgressBar *videoProgressBar;
@property (nonatomic, nullable) UIBarButtonItem *videoPlayBarButton;
@property (nonatomic, nullable) UIBarButtonItem *videoPauseBarButton;

@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *presentationViewConstraints;
@property (nonatomic, nullable) NSLayoutConstraint *mediaViewBottomConstraint;
@property (nonatomic, nullable) NSLayoutConstraint *mediaViewLeadingConstraint;
@property (nonatomic, nullable) NSLayoutConstraint *mediaViewTopConstraint;
@property (nonatomic, nullable) NSLayoutConstraint *mediaViewTrailingConstraint;

@end

#pragma mark -

@implementation MediaDetailViewController

- (void)dealloc
{
    [self stopAnyVideo];
}

- (instancetype)initWithGalleryItemBox:(GalleryItemBox *)galleryItemBox
                              viewItem:(nullable id<ConversationViewItem>)viewItem
{
    self = [super initWithNibName:nil bundle:nil];
    if (!self) {
        return self;
    }

    _galleryItemBox = galleryItemBox;
    _viewItem = viewItem;

    // We cache the image data in case the attachment stream is deleted.
    __weak MediaDetailViewController *weakSelf = self;
    _image = [galleryItemBox.attachmentStream
        thumbnailImageLargeWithSuccess:^(UIImage *image) {
            weakSelf.image = image;
            [weakSelf updateContents];
            [weakSelf updateMinZoomScale];
        }
        failure:^{
            OWSLogWarn(@"Could not load media.");
        }];

    return self;
}

- (TSAttachmentStream *)attachmentStream
{
    return self.galleryItemBox.attachmentStream;
}

- (BOOL)isAnimated
{
    return self.attachmentStream.isAnimated;
}

- (BOOL)isVideo
{
    return self.attachmentStream.isVideo;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = LKColors.navigationBarBackground;

    [self updateContents];
    
    // Loki: Set navigation bar background color
    UINavigationBar *navigationBar = self.navigationController.navigationBar;
    [navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    navigationBar.shadowImage = [UIImage new];
    [navigationBar setTranslucent:NO];
    navigationBar.barTintColor = LKColors.navigationBarBackground;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self resetMediaFrame];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if ([self.mediaView isKindOfClass:[YYAnimatedImageView class]]) {
        // Add a slight delay before starting the gif animation to prevent it from looking buggy due to
        // the custom transition
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [(YYAnimatedImageView *)self.mediaView startAnimating];
        });
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    [self updateMinZoomScale];
    [self centerMediaViewConstraints];
}

- (void)updateMinZoomScale
{
    if (!self.image) {
        self.scrollView.minimumZoomScale = 1.f;
        self.scrollView.maximumZoomScale = 1.f;
        self.scrollView.zoomScale = 1.f;
        return;
    }

    CGSize viewSize = self.scrollView.bounds.size;
    UIImage *image = self.image;
    OWSAssertDebug(image);

    if (image.size.width == 0 || image.size.height == 0) {
        OWSFailDebug(@"Invalid image dimensions. %@", NSStringFromCGSize(image.size));
        return;
    }

    CGFloat scaleWidth = viewSize.width / image.size.width;
    CGFloat scaleHeight = viewSize.height / image.size.height;
    CGFloat minScale = MIN(scaleWidth, scaleHeight);

    if (minScale != self.scrollView.minimumZoomScale) {
        self.scrollView.minimumZoomScale = minScale;
        self.scrollView.maximumZoomScale = minScale * 8;
        self.scrollView.zoomScale = minScale;
    }
}

- (void)zoomOutAnimated:(BOOL)isAnimated
{
    if (self.scrollView.zoomScale != self.scrollView.minimumZoomScale) {
        [self.scrollView setZoomScale:self.scrollView.minimumZoomScale animated:isAnimated];
    }
}

#pragma mark - Initializers

- (void)updateContents
{
    [self.mediaView removeFromSuperview];
    [self.scrollView removeFromSuperview];
    [self.playVideoButton removeFromSuperview];
    [self.videoProgressBar removeFromSuperview];

    UIScrollView *scrollView = [UIScrollView new];
    [self.view addSubview:scrollView];
    self.scrollView = scrollView;
    scrollView.delegate = self;

    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
    scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;

    [scrollView ows_autoPinToSuperviewEdges];

    if (self.isAnimated) {
        if (self.attachmentStream.isValidImage) {
            YYImage *animatedGif = [YYImage imageWithContentsOfFile:self.attachmentStream.originalFilePath];
            YYAnimatedImageView *animatedView = [YYAnimatedImageView new];
            animatedView.autoPlayAnimatedImage = NO;
            animatedView.image = animatedGif;
            self.mediaView = animatedView;
        }
        else {
            self.mediaView = [UIView new];
            self.mediaView.backgroundColor = Theme.offBackgroundColor;
        }
    } else if (!self.image) {
        // Still loading thumbnail.
        self.mediaView = [UIView new];
        self.mediaView.backgroundColor = Theme.offBackgroundColor;
    } else if (self.isVideo) {
        if (self.attachmentStream.isValidVideo) {
            self.mediaView = [self buildVideoPlayerView];
        } else {
            self.mediaView = [UIView new];
            self.mediaView.backgroundColor = Theme.offBackgroundColor;
        }
    } else {
        // Present the static image using standard UIImageView
        UIImageView *imageView = [[UIImageView alloc] initWithImage:self.image];
        self.mediaView = imageView;
    }

    OWSAssertDebug(self.mediaView);

    // We add these gestures to mediaView rather than
    // the root view so that interacting with the video player
    // progres bar doesn't trigger any of these gestures.
    [self addGestureRecognizersToView:self.mediaView];

    [scrollView addSubview:self.mediaView];
    self.mediaViewLeadingConstraint = [self.mediaView autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    self.mediaViewTopConstraint = [self.mediaView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    self.mediaViewTrailingConstraint = [self.mediaView autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    self.mediaViewBottomConstraint = [self.mediaView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    self.mediaView.contentMode = UIViewContentModeScaleAspectFit;
    self.mediaView.userInteractionEnabled = YES;
    self.mediaView.clipsToBounds = YES;
    self.mediaView.layer.allowsEdgeAntialiasing = YES;
    self.mediaView.translatesAutoresizingMaskIntoConstraints = NO;

    // Use trilinear filters for better scaling quality at
    // some performance cost.
    self.mediaView.layer.minificationFilter = kCAFilterTrilinear;
    self.mediaView.layer.magnificationFilter = kCAFilterTrilinear;

    if (self.isVideo) {
        PlayerProgressBar *videoProgressBar = [PlayerProgressBar new];
        videoProgressBar.delegate = self;
        videoProgressBar.player = self.videoPlayer.avPlayer;

        // We hide the progress bar until either:
        // 1. Video completes playing
        // 2. User taps the screen
        videoProgressBar.hidden = YES;

        self.videoProgressBar = videoProgressBar;
        [self.view addSubview:videoProgressBar];
        [videoProgressBar autoPinWidthToSuperview];
        [videoProgressBar autoPinEdgeToSuperviewSafeArea:ALEdgeTop];
        CGFloat kVideoProgressBarHeight = 44;
        [videoProgressBar autoSetDimension:ALDimensionHeight toSize:kVideoProgressBarHeight];

        UIButton *playVideoButton = [UIButton new];
        self.playVideoButton = playVideoButton;

        [playVideoButton addTarget:self action:@selector(playVideo) forControlEvents:UIControlEventTouchUpInside];

        UIImage *playImage = [UIImage imageNamed:@"CirclePlay"];
        [playVideoButton setBackgroundImage:playImage forState:UIControlStateNormal];
        playVideoButton.contentMode = UIViewContentModeScaleAspectFill;

        [self.view addSubview:playVideoButton];

        CGFloat playVideoButtonWidth = 72.f;
        [playVideoButton autoSetDimensionsToSize:CGSizeMake(playVideoButtonWidth, playVideoButtonWidth)];
        [playVideoButton autoCenterInSuperview];
    }
}

- (UIView *)buildVideoPlayerView
{
    NSURL *_Nullable attachmentUrl = self.attachmentStream.originalMediaURL;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:[attachmentUrl path]]) {
        OWSFailDebug(@"Missing video file");
    }

    OWSVideoPlayer *player = [[OWSVideoPlayer alloc] initWithUrl:attachmentUrl];
    [player seekToTime:kCMTimeZero];
    player.delegate = self;
    self.videoPlayer = player;

    VideoPlayerView *playerView = [VideoPlayerView new];
    playerView.player = player.avPlayer;

    [NSLayoutConstraint autoSetPriority:UILayoutPriorityDefaultLow
                         forConstraints:^{
                             [playerView autoSetDimensionsToSize:self.image.size];
                         }];

    return playerView;
}

- (void)setShouldHideToolbars:(BOOL)shouldHideToolbars
{
    self.videoProgressBar.hidden = shouldHideToolbars;
}

- (void)addGestureRecognizersToView:(UIView *)view
{
    UITapGestureRecognizer *doubleTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didDoubleTapImage:)];
    doubleTap.numberOfTapsRequired = 2;
    [view addGestureRecognizer:doubleTap];

    UITapGestureRecognizer *singleTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didSingleTapImage:)];
    [singleTap requireGestureRecognizerToFail:doubleTap];
    [view addGestureRecognizer:singleTap];
}

#pragma mark - Gesture Recognizers

- (void)didSingleTapImage:(UITapGestureRecognizer *)gesture
{
    [self.delegate mediaDetailViewControllerDidTapMedia:self];
}

- (void)didDoubleTapImage:(UITapGestureRecognizer *)gesture
{
    OWSLogVerbose(@"did double tap image.");
    if (self.scrollView.zoomScale == self.scrollView.minimumZoomScale) {
        CGFloat kDoubleTapZoomScale = 2;

        CGFloat zoomWidth = self.scrollView.width / kDoubleTapZoomScale;
        CGFloat zoomHeight = self.scrollView.height / kDoubleTapZoomScale;

        // center zoom rect around tapLocation
        CGPoint tapLocation = [gesture locationInView:self.scrollView];
        CGFloat zoomX = MAX(0, tapLocation.x - zoomWidth / 2);
        CGFloat zoomY = MAX(0, tapLocation.y - zoomHeight / 2);

        CGRect zoomRect = CGRectMake(zoomX, zoomY, zoomWidth, zoomHeight);

        CGRect translatedRect = [self.mediaView convertRect:zoomRect fromView:self.scrollView];

        [self.scrollView zoomToRect:translatedRect animated:YES];
    } else {
        // If already zoomed in at all, zoom out all the way.
        [self zoomOutAnimated:YES];
    }
}

- (void)didPressPlayBarButton:(id)sender
{
    OWSAssertDebug(self.isVideo);
    OWSAssertDebug(self.videoPlayer);
    [self playVideo];
}

- (void)didPressPauseBarButton:(id)sender
{
    OWSAssertDebug(self.isVideo);
    OWSAssertDebug(self.videoPlayer);
    [self pauseVideo];
}

#pragma mark - UIScrollViewDelegate

- (nullable UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return self.mediaView;
}

- (void)centerMediaViewConstraints
{
    OWSAssertDebug(self.scrollView);

    CGSize scrollViewSize = self.scrollView.bounds.size;
    CGSize imageViewSize = self.mediaView.frame.size;
    
    
    // We want to modify the yOffset so the content remains centered on the screen (we can do this
    // by subtracting half the parentViewController's y position)
    //
    // Note: Due to weird partial-pixel value rendering behaviours we need to round the inset either
    // up or down depending on which direction the partial-pixel would end up rounded to make it
    // align correctly
    CGFloat halfHeightDiff = ((self.scrollView.bounds.size.height - self.mediaView.frame.size.height) / 2);
    BOOL shouldRoundUp = (round(halfHeightDiff) - halfHeightDiff > 0);

    CGFloat yOffset = (
        round((scrollViewSize.height - imageViewSize.height) / 2) -
        (shouldRoundUp ?
            ceil(self.parentViewController.view.frame.origin.y / 2) :
            floor(self.parentViewController.view.frame.origin.y / 2)
        )
    );
    
    self.mediaViewTopConstraint.constant = yOffset;
    self.mediaViewBottomConstraint.constant = yOffset;

    CGFloat xOffset = MAX(0, (scrollViewSize.width - imageViewSize.width) / 2);
    self.mediaViewLeadingConstraint.constant = xOffset;
    self.mediaViewTrailingConstraint.constant = xOffset;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView
{
    [self centerMediaViewConstraints];
    [self.view layoutIfNeeded];
}

- (void)resetMediaFrame
{
    // HACK: Setting the frame to itself *seems* like it should be a no-op, but
    // it ensures the content is drawn at the right frame. In particular I was
    // reproducibly seeing some images squished (they were EXIF rotated, maybe
    // related). similar to this report:
    // https://stackoverflow.com/questions/27961884/swift-uiimageview-stretched-aspect
    [self.view layoutIfNeeded];
    self.mediaView.frame = self.mediaView.frame;
}

#pragma mark - Video Playback

- (void)playVideo
{
    OWSAssertDebug(self.videoPlayer);

    self.playVideoButton.hidden = YES;

    [self.videoPlayer play];

    [self.delegate mediaDetailViewController:self isPlayingVideo:YES];
}

- (void)pauseVideo
{
    OWSAssertDebug(self.isVideo);
    OWSAssertDebug(self.videoPlayer);

    [self.videoPlayer pause];

    [self.delegate mediaDetailViewController:self isPlayingVideo:NO];
}

- (void)stopAnyVideo
{
    if (self.isVideo) {
        [self stopVideo];
    }
}

- (void)stopVideo
{
    OWSAssertDebug(self.isVideo);
    OWSAssertDebug(self.videoPlayer);

    [self.videoPlayer stop];

    self.playVideoButton.hidden = NO;

    [self.delegate mediaDetailViewController:self isPlayingVideo:NO];
}

#pragma mark - OWSVideoPlayer

- (void)videoPlayerDidPlayToCompletion:(OWSVideoPlayer *)videoPlayer
{
    OWSAssertDebug(self.isVideo);
    OWSAssertDebug(self.videoPlayer);
    OWSLogVerbose(@"");

    [self stopVideo];
}

#pragma mark - PlayerProgressBarDelegate

- (void)playerProgressBarDidStartScrubbing:(PlayerProgressBar *)playerProgressBar
{
    OWSAssertDebug(self.videoPlayer);
    [self.videoPlayer pause];
}

- (void)playerProgressBar:(PlayerProgressBar *)playerProgressBar scrubbedToTime:(CMTime)time
{
    OWSAssertDebug(self.videoPlayer);
    [self.videoPlayer seekToTime:time];
}

- (void)playerProgressBar:(PlayerProgressBar *)playerProgressBar
    didFinishScrubbingAtTime:(CMTime)time
        shouldResumePlayback:(BOOL)shouldResumePlayback
{
    OWSAssertDebug(self.videoPlayer);
    [self.videoPlayer seekToTime:time];

    if (shouldResumePlayback) {
        [self.videoPlayer play];
    }
}

#pragma mark - Saving images to Camera Roll

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    if (error) {
        OWSLogWarn(@"There was a problem saving <%@> to camera roll.", error.localizedDescription);
    }
}

@end

NS_ASSUME_NONNULL_END
