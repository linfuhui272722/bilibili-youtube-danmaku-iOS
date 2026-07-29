//
//  B2YDanmakuOverlayView.h
//  B2YDanmaku
//
//  The transparent UIView that sits on top of the YouTube player and
//  renders danmaku. It owns:
//   - a CADisplayLink that drives the animation loop (the iOS analogue
//     of the browser extension's requestAnimationFrame loop);
//   - a pool of UILabel subviews that are recycled as danmaku enter and
//     leave the visible area (avoiding per-frame alloc);
//   - the track layout state (which horizontal slot is free).
//
//  The view is added as a subview of YTPlayerView's overlay container
//  by the Logos hook in B2YDanmaku.x.
//

#import <UIKit/UIKit.h>

@class B2YDanmaku;
@class B2YDanmakuEngine;

NS_ASSUME_NONNULL_BEGIN

@interface B2YDanmakuOverlayView : UIView

// The engine that feeds us danmaku to render.
@property (nonatomic, weak, nullable) B2YDanmakuEngine *engine;

// Start / stop the animation loop. Tied to the player's play/pause state.
- (void)startRendering;
- (void)stopRendering;

// Clear all visible danmaku immediately (e.g. when seeking).
- (void)clearAll;

// Called by the engine when the player seeks. Removes on-screen danmaku
// and resets the emission cursor.
- (void)handleSeekToTime:(NSTimeInterval)time;

@end

NS_ASSUME_NONNULL_END
