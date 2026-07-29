//
//  B2YDanmaku.x
//
//  Main Logos hook file. Wires the B2Y engine into the YouTube iOS app.
//
//  Hook points:
//   1. YTPlayerViewController  - detect video changes, read playback time.
//   2. YTPlayerView            - inject the danmaku overlay view.
//   3. YTMainAppVideoPlayerOverlayViewController - alternate time source.
//
//  The engine + overlay are stored as associated objects on the player
//  controller so they share its lifecycle (one per video).
//

#import "B2YDanmaku.h"
#import <objc/runtime.h>

// ---- Associated-object keys ----
static const void *kEngineKey = &kEngineKey;
static const void *kOverlayKey = &kOverlayKey;
static const void *kLastVideoIDKey = &kLastVideoIDKey;
static const void *kTimePollTimerKey = &kTimePollTimerKey;

// ---- YouTube private class interfaces ----
// We only declare the surface we actually use; the rest is opaque.

@interface YTPlayerResponse : NSObject
@property (nonatomic, copy, readonly) NSString *videoID;
@end

@interface YTPlayerData : NSObject
@property (nonatomic, strong, readonly) YTPlayerResponse *playerResponse;
@end

@interface YTSingleVideoController : NSObject
@property (nonatomic, assign, readonly) NSTimeInterval totalMediaTime;
@property (nonatomic, assign, readonly) float playbackRate;
@property (nonatomic, copy, readonly) NSString *videoID;
- (NSTimeInterval)currentMediaTime;
@end

@interface YTPlayerViewController : UIViewController
@property (nonatomic, copy, readonly) NSString *contentVideoID;
@property (nonatomic, strong, readonly) YTPlayerData *playerData;
@property (nonatomic, strong, readonly) YTSingleVideoController *activeVideo;
- (void)playbackDidStart;
- (void)playbackDidPause;
@end

@interface YTPlayerView : UIView
@end

@interface YTMainAppVideoPlayerOverlayViewController : UIViewController
@property (nonatomic, copy, readonly) NSString *videoID;
@property (nonatomic, assign, readonly) NSTimeInterval mediaTime;
@property (nonatomic, assign, readonly) float currentPlaybackRate;
@end

@interface YTWatchViewController : UIViewController
@property (nonatomic, strong, readonly) YTPlayerViewController *playerViewController;
@end

// ---- Helper: associated-object storage ----

static inline B2YDanmakuEngine *b2y_engine(id obj) {
    return objc_getAssociatedObject(obj, kEngineKey);
}

static inline void b2y_set_engine(id obj, B2YDanmakuEngine *engine) {
    objc_setAssociatedObject(obj, kEngineKey, engine, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static inline B2YDanmakuOverlayView *b2y_overlay(id obj) {
    return objc_getAssociatedObject(obj, kOverlayKey);
}

static inline void b2y_set_overlay(id obj, B2YDanmakuOverlayView *overlay) {
    objc_setAssociatedObject(obj, kOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static inline NSString *b2y_last_video_id(id obj) {
    return objc_getAssociatedObject(obj, kLastVideoIDKey);
}

static inline void b2y_set_last_video_id(id obj, NSString *videoID) {
    objc_setAssociatedObject(obj, kLastVideoIDKey, videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// ---- Helper: get the YouTube video title ----
// YouTube doesn't expose the title via a clean property, so we read it
// from the player response's playback tracking / videoDetails. If that
// fails, we fall back to the navigation title.

static NSString *b2y_video_title(YTPlayerViewController *pvc) {
    @try {
        // playerData.playerResponse has a `videoDetails` dict on newer
        // versions; we try a few KVC paths to be resilient.
        id playerData = [pvc valueForKey:@"playerData"];
        if (!playerData) return nil;

        id playerResponse = [playerData valueForKey:@"playerResponse"];
        if (!playerResponse) return nil;

        // Try `videoDetails.title` (the canonical path).
        id videoDetails = [playerResponse valueForKey:@"videoDetails"];
        if (videoDetails) {
            NSString *title = [videoDetails valueForKey:@"title"];
            if ([title isKindOfClass:[NSString class]] && title.length > 0) {
                return title;
            }
        }

        // Fallback: `playabilityStatus.title` (older builds).
        id playability = [playerResponse valueForKey:@"playabilityStatus"];
        if (playability) {
            NSString *title = [playability valueForKey:@"title"];
            if ([title isKindOfClass:[NSString class]] && title.length > 0) {
                return title;
            }
        }
    } @catch (NSException *e) {
        // KVC failures are expected on some YouTube versions; we'll fall
        // back to the video ID as the search keyword.
    }
    return nil;
}

// ---- Helper: get the YouTube video duration ----

static NSTimeInterval b2y_video_duration(YTPlayerViewController *pvc) {
    @try {
        YTSingleVideoController *av = pvc.activeVideo;
        if (av && av.totalMediaTime > 0) {
            return av.totalMediaTime;
        }
    } @catch (NSException *e) {}
    return 0;
}

// ---- Helper: ensure engine + overlay exist for a player controller ----

static void b2y_ensure_engine_for(YTPlayerViewController *pvc) {
    if (!b2yBool(kB2YEnabledKey)) return;
    if (!pvc) return;

    B2YDanmakuEngine *engine = b2y_engine(pvc);
    if (!engine) {
        engine = [[B2YDanmakuEngine alloc] init];
        b2y_set_engine(pvc, engine);
    }

    // Find or create the overlay view.
    B2YDanmakuOverlayView *overlay = b2y_overlay(pvc);
    if (!overlay) {
        // Accessing .view triggers loadView if needed; guard with viewIfLoaded
        // to avoid forcing early view creation on some YouTube versions.
        UIView *hostView = pvc.view;
        if (!hostView) return;
        overlay = [[B2YDanmakuOverlayView alloc] initWithFrame:hostView.bounds];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlay.engine = engine;
        engine.overlay = overlay;
        b2y_set_overlay(pvc, overlay);

        // Insert on top of the player view but below YouTube's own
        // controls (so the play/pause button stays tappable).
        [hostView addSubview:overlay];
    }
}

// ---- Helper: trigger danmaku load for a new video ----

static void b2y_load_for_video(YTPlayerViewController *pvc, NSString *videoID) {
    if (!b2yBool(kB2YEnabledKey)) return;
    if (!videoID || videoID.length == 0) return;

    // Skip if we already loaded this video.
    if ([videoID isEqualToString:b2y_last_video_id(pvc)]) return;
    b2y_set_last_video_id(pvc, videoID);

    b2y_ensure_engine_for(pvc);
    B2YDanmakuEngine *engine = b2y_engine(pvc);
    B2YDanmakuOverlayView *overlay = b2y_overlay(pvc);

    NSString *title = b2y_video_title(pvc);
    NSTimeInterval duration = b2y_video_duration(pvc);

    // If we couldn't read the title, fall back to the video ID as the
    // search keyword (works for videos whose title is the BV id, etc.).
    if (title.length == 0) title = videoID;

    [overlay clearAll];
    [engine loadForYouTubeVideoID:videoID
                           title:title
                        duration:duration
                       completion:^(BOOL success, NSString *message) {
        if (success) {
            [overlay startRendering];
        }
    }];
}

// ---- Helper: poll playback time ----
// We use a CADisplayLink-free timer because the overlay already runs a
// display link; we just need to feed the engine a current time value.
// Reading `mediaTime` from the overlay controller every 100ms is cheap.

static void b2y_start_time_polling(YTPlayerViewController *pvc) {
    NSTimer *existing = objc_getAssociatedObject(pvc, kTimePollTimerKey);
    if (existing) return;

    B2YDanmakuEngine *engine = b2y_engine(pvc);
    if (!engine) return;

    __weak typeof(pvc) weakPVC = pvc;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                      repeats:YES
                                                        block:^(NSTimer *t) {
        __strong typeof(weakPVC) strongPVC = weakPVC;
        if (!strongPVC) {
            [t invalidate];
            return;
        }
        B2YDanmakuEngine *eng = b2y_engine(strongPVC);
        if (!eng) return;

        NSTimeInterval time = 0;
        @try {
            YTSingleVideoController *av = strongPVC.activeVideo;
            if (av && [av respondsToSelector:@selector(currentMediaTime)]) {
                time = [av currentMediaTime];
            }
        } @catch (NSException *e) {}

        [eng setPlaybackTime:time];
    }];
    objc_setAssociatedObject(pvc, kTimePollTimerKey, timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void b2y_stop_time_polling(YTPlayerViewController *pvc) {
    NSTimer *timer = objc_getAssociatedObject(pvc, kTimePollTimerKey);
    [timer invalidate];
    objc_setAssociatedObject(pvc, kTimePollTimerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
// ===========================================================================
//  Hooks
// ===========================================================================

// Hook YTPlayerViewController to detect when a video becomes active.
// We hook `viewDidAppear:` (called when the player view is shown) and
// `viewWillDisappear:` (cleanup).

%hook YTPlayerViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (!b2yBool(kB2YEnabledKey)) return;

    NSString *videoID = self.contentVideoID;
    if (videoID.length > 0) {
        b2y_ensure_engine_for(self);
        b2y_load_for_video(self, videoID);
        b2y_start_time_polling(self);
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;

    b2y_stop_time_polling(self);
    B2YDanmakuOverlayView *overlay = b2y_overlay(self);
    [overlay stopRendering];
    [overlay clearAll];
    B2YDanmakuEngine *engine = b2y_engine(self);
    [engine reset];
    b2y_set_last_video_id(self, nil);
}

%end

// Hook YTMainAppVideoPlayerOverlayViewController as a backup time source
// and to detect video switches when the player view controller isn't
// re-created (e.g. autoplay next video).

%hook YTMainAppVideoPlayerOverlayViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (!b2yBool(kB2YEnabledKey)) return;

    // Walk up the view controller hierarchy to find the player view
    // controller, then ensure the engine is wired up.
    UIViewController *vc = self;
    NSInteger safetyCount = 0;
    while (vc && ![vc isKindOfClass:%c(YTPlayerViewController)] && safetyCount < 10) {
        UIViewController *parent = vc.parentViewController;
        if (!parent) {
            // Try the watch VC's playerViewController property via KVC.
            if ([vc isKindOfClass:%c(YTWatchViewController)]) {
                parent = [vc valueForKey:@"playerViewController"];
            }
        }
        vc = parent;
        safetyCount++;
    }
    if (!vc) return;

    YTPlayerViewController *pvc = (YTPlayerViewController *)vc;
    NSString *videoID = pvc.contentVideoID;
    if (videoID.length > 0) {
        b2y_ensure_engine_for(pvc);
        b2y_load_for_video(pvc, videoID);
        b2y_start_time_polling(pvc);
    }
}

%end

// Hook YTPlayerView's layoutSubviews to keep our overlay sized correctly
// and to ensure it's on top of the video layer but below the controls.

%hook YTPlayerView

- (void)layoutSubviews {
    %orig;

    if (!b2yBool(kB2YEnabledKey)) return;

    // Find any B2YDanmakuOverlayView among our subviews and bring it
    // to the front (but below YouTube's control overlay, which is added
    // later in the subview order).
    for (UIView *sub in self.subviews) {
        if ([sub isKindOfClass:[B2YDanmakuOverlayView class]]) {
            [self bringSubviewToFront:sub];
            break;
        }
    }
}

%end

// Hook YTWatchViewController to catch the initial player setup.

%hook YTWatchViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (!b2yBool(kB2YEnabledKey)) return;

    YTPlayerViewController *pvc = nil;
    @try {
        pvc = [self valueForKey:@"playerViewController"];
    } @catch (NSException *e) {
        // KVC failure - YouTube may have renamed the property.
        return;
    }
    if (pvc && pvc.contentVideoID.length > 0) {
        b2y_ensure_engine_for(pvc);
        b2y_load_for_video(pvc, pvc.contentVideoID);
        b2y_start_time_polling(pvc);
    }
}

%end

// ---- Constructor: register defaults and log version ----

%ctor {
    @autoreleasepool {
        [[B2YSettings shared] registerDefaults];
        NSLog(@"[B2YDanmaku] loaded v%@", B2Y_VERSION);
    }
}
