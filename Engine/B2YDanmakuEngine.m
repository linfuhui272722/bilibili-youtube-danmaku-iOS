//
//  B2YDanmakuEngine.m
//

#import "B2YDanmakuEngine.h"
#import "B2YDanmakuModel.h"
#import "B2YDanmakuAPI.h"
#import "B2YDanmakuOverlayView.h"
#import "B2YSettings.h"
#import "B2YVideoMatcher.h"

@interface B2YDanmakuEngine ()
@property (nonatomic, copy) NSString *currentVideoID;
@property (nonatomic, strong) B2YBilibiliVideo *matchedVideo;
@property (nonatomic, strong) NSArray<B2YDanmaku *> *danmakus;
@property (nonatomic, assign) NSInteger emissionCursor; // index into danmakus
@property (nonatomic, assign) NSTimeInterval playbackTime;
@property (nonatomic, strong) id loadTaskIdentifier;
@property (nonatomic, assign) BOOL loading;
@end

@implementation B2YDanmakuEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _danmakus = @[];
        _emissionCursor = 0;
        _playbackTime = 0;
    }
    return self;
}

- (void)loadForYouTubeVideoID:(NSString *)videoID
                        title:(NSString *)title
                     duration:(NSTimeInterval)duration
                    completion:(void (^)(BOOL, NSString * _Nullable))completion {
    // Cancel any in-flight load for a different video.
    if ([videoID isEqualToString:self.currentVideoID] && self.danmakus.count > 0) {
        if (completion) completion(YES, @"Already loaded");
        return;
    }

    [self reset];
    self.currentVideoID = videoID;
    self.loading = YES;

    NSString *cookie = [[B2YSettings shared] bilibiliCookieHeader];
    NSInteger threshold = b2yInt(kB2YMatchThresholdKey);
    if (threshold <= 0) threshold = 60;

    BOOL autoMatch = b2yBool(kB2YAutoMatchKey);
    if (!autoMatch) {
        // Manual mode: use the BV id from settings.
        NSString *manualBVID = b2yString(kB2YManualBVIDKey);
        if (manualBVID.length == 0) {
            self.loading = NO;
            if (completion) completion(NO, @"No BV id set and auto-match is off");
            return;
        }
        [self loadForBVID:manualBVID completion:completion];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[B2YDanmakuAPI shared] loadDanmakuForYouTubeTitle:title
                                        youTubeDuration:duration
                                                cookie:cookie
                                       matchThreshold:threshold
                                         matchCallback:^(B2YBilibiliVideo *matched, NSArray *allResults) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.matchedVideo = matched;
    } completion:^(NSArray<B2YDanmaku *> *danmakus, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.loading = NO;

        if (error || !danmakus) {
            if (completion) completion(NO, error.localizedDescription ?: @"Unknown error");
            return;
        }

        // Apply filters.
        NSArray<B2YDanmaku *> *filtered = [strongSelf applyFilters:danmakus];
        strongSelf.danmakus = filtered;
        strongSelf.emissionCursor = 0;

        if (completion) {
            completion(YES, [NSString stringWithFormat:@"Loaded %lu danmaku from %@",
                              (unsigned long)filtered.count,
                              strongSelf.matchedVideo.bvid ?: @"?"]);
        }
    }];
}

- (void)loadForBVID:(NSString *)bvid
         completion:(void (^)(BOOL, NSString * _Nullable))completion {
    self.loading = YES;
    NSString *cookie = [[B2YSettings shared] bilibiliCookieHeader];

    __weak typeof(self) weakSelf = self;
    [[B2YDanmakuAPI shared] loadDanmakuForBVID:bvid
                                        cookie:cookie
                                    completion:^(NSArray<B2YDanmaku *> *danmakus, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.loading = NO;

        if (error || !danmakus) {
            if (completion) completion(NO, error.localizedDescription ?: @"Unknown error");
            return;
        }

        NSArray<B2YDanmaku *> *filtered = [strongSelf applyFilters:danmakus];
        strongSelf.danmakus = filtered;
        strongSelf.emissionCursor = 0;

        if (completion) {
            completion(YES, [NSString stringWithFormat:@"Loaded %lu danmaku from %@",
                              (unsigned long)filtered.count, bvid]);
        }
    }];
}

- (NSArray<B2YDanmaku *> *)applyFilters:(NSArray<B2YDanmaku *> *)danmakus {
    BOOL filterLowWeight = b2yBool(kB2YFilterLowWeightKey);
    NSInteger weightThreshold = b2yInt(kB2YWeightThresholdKey);
    if (weightThreshold <= 0) weightThreshold = 0;

    NSInteger maxDanmaku = b2yInt(kB2YMaxDanmakuKey);
    if (maxDanmaku <= 0) maxDanmaku = 5000;

    NSMutableArray<B2YDanmaku *> *filtered = [NSMutableArray array];
    for (B2YDanmaku *d in danmakus) {
        // Drop code/BAS danmaku (mode 8) - we can't render them.
        if (d.mode == B2YDanmakuModeCode) continue;
        // Drop empty text.
        if (d.text.length == 0) continue;
        // Optional low-weight filter.
        if (filterLowWeight && d.weight < weightThreshold) continue;
        [filtered addObject:d];
        if ((NSInteger)filtered.count >= maxDanmaku) break;
    }

    // Sort by time so the emission cursor can binary-search.
    [filtered sortUsingComparator:^NSComparisonResult(B2YDanmaku *a, B2YDanmaku *b) {
        if (a.time < b.time) return NSOrderedAscending;
        if (a.time > b.time) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    return filtered;
}

- (NSTimeInterval)currentPlaybackTime {
    return _playbackTime;
}

- (void)setPlaybackTime:(NSTimeInterval)time {
    _playbackTime = time;
}

- (NSArray<B2YDanmaku *> *)dequeueDanmakuUpToTime:(NSTimeInterval)time {
    if (self.danmakus.count == 0) return @[];

    // Binary search for the first danmaku with time > `time`.
    // Everything from emissionCursor up to (but not including) that index
    // is due for emission.
    NSInteger lo = self.emissionCursor;
    NSInteger hi = (NSInteger)self.danmakus.count;

    // Linear scan from cursor (danmaku are sorted, so this is O(k) where
    // k is the number of newly-due danmaku, not O(n)).
    NSMutableArray<B2YDanmaku *> *due = [NSMutableArray array];
    while (lo < hi) {
        B2YDanmaku *d = self.danmakus[lo];
        if (d.time > time) break;
        [due addObject:d];
        lo++;
    }
    self.emissionCursor = lo;
    return due;
}

- (void)resetEmissionCursorToTime:(NSTimeInterval)time {
    // After a seek, find the first danmaku at or after `time`.
    if (self.danmakus.count == 0) {
        self.emissionCursor = 0;
        return;
    }
    // Binary search.
    NSInteger lo = 0, hi = (NSInteger)self.danmakus.count;
    while (lo < hi) {
        NSInteger mid = lo + (hi - lo) / 2;
        if (self.danmakus[mid].time < time) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    self.emissionCursor = lo;
}

- (void)reset {
    self.danmakus = @[];
    self.emissionCursor = 0;
    self.playbackTime = 0;
    self.matchedVideo = nil;
    self.currentVideoID = nil;
    self.loading = NO;
}

@end
