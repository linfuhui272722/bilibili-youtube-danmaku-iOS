//
//  B2YDanmakuAPI.h
//  B2YDanmaku
//
//  High-level Bilibili client. Wraps the three endpoints the original
//  browser extension uses:
//
//   1. search/all/v2  - keyword search for videos (WBI-signed)
//   2. view           - fetch video info (cid, aid, duration) by bvid
//   3. dm/wbi/web/seg.so - protobuf danmaku segment (WBI-signed)
//
//  All methods are asynchronous and run their network work on a
//  dedicated serial queue so we never block the main thread.
//

#import <Foundation/Foundation.h>

@class B2YBilibiliVideo;
@class B2YDanmaku;

NS_ASSUME_NONNULL_BEGIN

@interface B2YDanmakuAPI : NSObject

+ (instancetype)shared;

// Search Bilibili for videos matching `keyword`, ordered by danmaku
// count (mirrors the extension's `order: 'dm'`).
- (void)searchVideosWithKeyword:(NSString *)keyword
                         cookie:(NSString *)cookie
                     completion:(void (^)(NSArray<B2YBilibiliVideo *> * _Nullable results,
                                          NSError * _Nullable error))completion;

// Fetch video metadata (cid, aid, duration, title) for a BV id.
- (void)fetchVideoInfoWithBVID:(NSString *)bvid
                        cookie:(NSString *)cookie
                    completion:(void (^)(B2YBilibiliVideo * _Nullable video,
                                         NSError * _Nullable error))completion;

// Download every danmaku segment for the given video. Bilibili splits
// danmaku into 6-minute segments; we fetch them sequentially with a
// small delay to avoid rate-limiting.
- (void)downloadAllDanmakuForVideo:(B2YBilibiliVideo *)video
                            cookie:(NSString *)cookie
                        completion:(void (^)(NSArray<B2YDanmaku *> * _Nullable danmakus,
                                             NSError * _Nullable error))completion;

// Convenience: search + match + fetch in one shot. Returns the chosen
// video (via `matchCallback`) before downloading danmaku, so the UI can
// show which video was matched.
- (void)loadDanmakuForYouTubeTitle:(NSString *)ytTitle
                        youTubeDuration:(NSTimeInterval)ytDuration
                            cookie:(NSString *)cookie
                       matchThreshold:(NSInteger)threshold
                     matchCallback:(void (^)(B2YBilibiliVideo * _Nullable matched,
                                             NSArray<B2YBilibiliVideo *> *allResults))matchCallback
                        completion:(void (^)(NSArray<B2YDanmaku *> * _Nullable danmakus,
                                             NSError * _Nullable error))completion;

// Direct download by BV id (manual mode). Skips search/match.
- (void)loadDanmakuForBVID:(NSString *)bvid
                    cookie:(NSString *)cookie
                completion:(void (^)(NSArray<B2YDanmaku *> * _Nullable danmakus,
                                     NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
