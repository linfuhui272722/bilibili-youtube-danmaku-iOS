//
//  B2YDanmakuEngine.h
//  B2YDanmaku
//
//  The engine is the bridge between the Bilibili API layer and the
//  rendering overlay. It owns:
//   - the sorted danmaku list for the current video;
//   - the current playback time (read from the YouTube player);
//   - the emission cursor (so we don't re-emit danmaku after seeking);
//   - the active load task (cancelled when the video changes).
//
//  The engine is created per video and discarded when the video ends,
//  matching the lifecycle of the browser extension's per-tab state.
//

#import <Foundation/Foundation.h>

@class B2YDanmaku;
@class B2YBilibiliVideo;
@class B2YDanmakuOverlayView;

NS_ASSUME_NONNULL_BEGIN

@interface B2YDanmakuEngine : NSObject

// The overlay view that renders our danmaku. Weak ref to avoid a cycle.
@property (nonatomic, weak, nullable) B2YDanmakuOverlayView *overlay;

// The YouTube video being watched (for logging / dedup).
@property (nonatomic, copy, readonly) NSString *currentVideoID;

// The Bilibili video we matched (nil until matching completes).
@property (nonatomic, strong, readonly, nullable) B2YBilibiliVideo *matchedVideo;

// Load danmaku for a YouTube video. Triggers search + match + download.
// `title` is the YouTube video title; `duration` is its length in seconds.
- (void)loadForYouTubeVideoID:(NSString *)videoID
                        title:(NSString *)title
                     duration:(NSTimeInterval)duration
                    completion:(void (^)(BOOL success, NSString * _Nullable message))completion;

// Load danmaku for a specific BV id (manual mode).
- (void)loadForBVID:(NSString *)bvid
         completion:(void (^)(BOOL success, NSString * _Nullable message))completion;

// Playback time source. Called by the overlay every frame.
- (NSTimeInterval)currentPlaybackTime;

// Pop danmaku whose `time` <= `time` and haven't been emitted yet.
- (NSArray<B2YDanmaku *> *)dequeueDanmakuUpToTime:(NSTimeInterval)time;

// Reset the emission cursor (after a seek).
- (void)resetEmissionCursorToTime:(NSTimeInterval)time;

// Discard everything (video ended / changed).
- (void)reset;

// Set the playback time directly (used when the hook reports a new time).
- (void)setPlaybackTime:(NSTimeInterval)time;

@end

NS_ASSUME_NONNULL_END
