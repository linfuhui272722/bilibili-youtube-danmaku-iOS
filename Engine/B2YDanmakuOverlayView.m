//
//  B2YDanmakuOverlayView.m
//
//  Rendering loop. Each CADisplayLink tick:
//    1. Ask the engine for the current playback time.
//    2. Emit any danmaku whose `time` has just passed.
//    3. Advance every active danmaku's frame by dt * speed.
//    4. Recycle labels that have scrolled off-screen.
//
//  Track layout: we divide the visible height into N horizontal tracks
//  of `trackHeight` points. A scrolling danmaku claims a track until its
//  tail clears the right edge; a top/bottom danmaku claims a track for
//  a fixed duration (4 seconds, matching the extension).
//

#import "B2YDanmakuOverlayView.h"
#import "B2YDanmakuEngine.h"
#import "B2YDanmakuModel.h"
#import "B2YSettings.h"

// Fixed display duration for top/bottom danmaku (seconds).
static const NSTimeInterval kFixedDanmakuDuration = 4.0;
// Maximum labels we keep alive simultaneously (memory cap).
static const NSInteger kMaxActiveLabels = 80;

@interface B2YDanmakuOverlayView ()

// Active danmaku: each entry holds the label, its metadata, and its
// current animation state.
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *activeItems;
// Recycled labels, keyed by font size, to avoid realloc.
@property (nonatomic, strong) NSMutableArray<UILabel *> *labelPool;

@property (nonatomic, strong, nullable) CADisplayLink *displayLink;
@property (nonatomic, assign) CFTimeInterval lastTimestamp;

// Track availability timestamps.
//   scrollTracks[i] = earliest time at which track i is free for a new scroll danmaku.
//   topTracks[i]    = same for top-fixed danmaku.
//   bottomTracks[i] = same for bottom-fixed danmaku.
@property (nonatomic, strong) NSMutableArray<NSNumber *> *scrollTracks;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *topTracks;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *bottomTracks;

@property (nonatomic, assign) CGFloat trackHeight;
@property (nonatomic, assign) NSInteger trackCount;

@end

@implementation B2YDanmakuOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.opaque = NO;
        self.clearsContextBeforeDrawing = NO;

        _activeItems = [NSMutableArray array];
        _labelPool = [NSMutableArray array];
        _scrollTracks = [NSMutableArray array];
        _topTracks = [NSMutableArray array];
        _bottomTracks = [NSMutableArray array];
        _trackHeight = 28.0;
        _trackCount = 0;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self recomputeTracks];
}

- (void)recomputeTracks {
    // Display area is stored as 0-100 in settings; convert to 0.0-1.0.
    CGFloat displayAreaPct = b2yFloat(kB2YDisplayAreaKey);
    if (displayAreaPct <= 0) displayAreaPct = 75;
    CGFloat displayArea = displayAreaPct / 100.0;
    if (displayArea > 1.0) displayArea = 1.0;
    CGFloat availableHeight = self.bounds.size.height * displayArea;

    CGFloat fontSize = b2yFloat(kB2YFontSizeKey);
    if (fontSize <= 0) fontSize = 18.0;
    CGFloat spacing = b2yFloat(kB2YTrackSpacingKey);
    if (spacing <= 0) spacing = 4.0;

    _trackHeight = fontSize + spacing + 6.0;
    NSInteger newCount = (NSInteger)(availableHeight / _trackHeight);
    if (newCount < 1) newCount = 1;
    if (newCount > 25) newCount = 25; // cap to keep things sane

    if (newCount != _trackCount) {
        _trackCount = newCount;
        [_scrollTracks removeAllObjects];
        [_topTracks removeAllObjects];
        [_bottomTracks removeAllObjects];
        for (NSInteger i = 0; i < _trackCount; i++) {
            [_scrollTracks addObject:@(0)];
            [_topTracks addObject:@(0)];
            [_bottomTracks addObject:@(0)];
        }
    }
}

#pragma mark - Animation loop

- (void)startRendering {
    if (self.displayLink) return;
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self
                                                     selector:@selector(tick:)];
    link.frameInterval = 1; // every refresh
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.displayLink = link;
    self.lastTimestamp = 0;
}

- (void)stopRendering {
    [self.displayLink invalidate];
    self.displayLink = nil;
    self.lastTimestamp = 0;
}

- (void)tick:(CADisplayLink *)link {
    if (!self.engine) return;

    NSTimeInterval currentTime = [self.engine currentPlaybackTime];
    if (currentTime < 0) return;

    CFTimeInterval now = link.timestamp;
    CFTimeInterval dt = self.lastTimestamp > 0 ? (now - self.lastTimestamp) : 0;
    self.lastTimestamp = now;

    // 1. Emit due danmaku.
    NSArray<B2YDanmaku *> *due = [self.engine dequeueDanmakuUpToTime:currentTime];
    for (B2YDanmaku *d in due) {
        [self emitDanmaku:d atTime:currentTime];
    }

    // 2. Advance active danmaku.
    [self advanceActiveDanmakuWithDt:dt currentTime:currentTime];

    // 3. Recycle off-screen labels.
    [self recycleOffscreenItems];
}

#pragma mark - Emission

- (void)emitDanmaku:(B2YDanmaku *)d atTime:(NSTimeInterval)currentTime {
    if (self.activeItems.count >= kMaxActiveLabels) return;

    UILabel *label = [self dequeueLabelForDanmaku:d];
    if (!label) return;

    CGFloat fontSize = b2yFloat(kB2YFontSizeKey);
    if (fontSize <= 0) fontSize = 18.0;
    label.font = [UIFont boldSystemFontOfSize:fontSize];
    label.text = d.text;
    label.textColor = [B2YDanmaku uiColorFromRGB:d.color];
    // Opacity is stored as 0-100 in settings; convert to 0.0-1.0 for alpha.
    CGFloat opacityPct = b2yFloat(kB2YOpacityKey);
    if (opacityPct <= 0) opacityPct = 100;
    label.alpha = opacityPct / 100.0;

    [label sizeToFit];

    // Add a small padding so text isn't flush against the edge.
    CGRect f = label.frame;
    f.size.width += 8;
    f.size.height = _trackHeight;
    label.frame = f;

    NSMutableDictionary *item = [NSMutableDictionary dictionary];
    item[@"label"] = label;
    item[@"danmaku"] = d;
    item[@"mode"] = @(d.mode);
    item[@"bornAt"] = @(currentTime);

    switch (d.mode) {
        case B2YDanmakuModeTop:
        case B2YDanmakuModeBottom: {
            NSInteger trackIdx = [self findFreeTrackForFixedDanmaku:d.mode atTime:currentTime];
            if (trackIdx < 0) {
                // No free track - drop this danmaku.
                [self enqueueLabel:label];
                return;
            }
            CGFloat y = [self yForTrack:trackIdx mode:d.mode];
            CGFloat x = (self.bounds.size.width - f.size.width) / 2.0;
            label.frame = CGRectMake(x, y, f.size.width, f.size.height);
            item[@"track"] = @(trackIdx);
            item[@"expiresAt"] = @(currentTime + kFixedDanmakuDuration);
            break;
        }
        default: {
            // Scrolling danmaku.
            NSInteger trackIdx = [self findFreeTrackForScrollDanmakuAtTime:currentTime
                                                                   labelWidth:f.size.width];
            if (trackIdx < 0) {
                [self enqueueLabel:label];
                return;
            }
            CGFloat y = [self yForTrack:trackIdx mode:B2YDanmakuModeScroll];
            CGFloat startX = self.bounds.size.width;
            label.frame = CGRectMake(startX, y, f.size.width, f.size.height);
            item[@"track"] = @(trackIdx);
            item[@"startX"] = @(startX);
            item[@"speed"] = @([self scrollSpeedForLabelWidth:f.size.width]);
            break;
        }
    }

    [self addSubview:label];
    [self.activeItems addObject:item];
}

- (CGFloat)scrollSpeedForLabelWidth:(CGFloat)width {
    // Speed in points/second. Longer danmaku move slightly faster so they
    // don't linger; the base speed is user-configurable.
    // Settings stores scroll speed as a multiplier (1.0 = normal).
    CGFloat speedMult = b2yFloat(kB2YScrollSpeedKey);
    if (speedMult <= 0) speedMult = 1.0;
    CGFloat base = 100.0 * speedMult;
    // Scale by screen width so the perceived speed is similar across devices.
    CGFloat screenWidth = self.bounds.size.width;
    if (screenWidth <= 0) screenWidth = 375;
    // Time to cross screen = screenWidth / base. We want roughly 8-12s.
    // Adjust base so a typical danmaku crosses in ~10s.
    CGFloat crossTime = screenWidth / base;
    if (crossTime < 6) base = screenWidth / 10.0;
    return base;
}

- (NSInteger)findFreeTrackForScrollDanmakuAtTime:(NSTimeInterval)time
                                      labelWidth:(CGFloat)width {
    // A track is free if the previous danmaku's tail has cleared the
    // right edge. We approximate using the track's `freeAt` timestamp
    // and the previous danmaku's speed.
    for (NSInteger i = 0; i < _trackCount && i < (NSInteger)self.scrollTracks.count; i++) {
        NSTimeInterval freeAt = [self.scrollTracks[i] doubleValue];
        if (time >= freeAt) {
            // Reserve this track. Estimate when the tail will clear the
            // right edge: time = (width + screenWidth) / speed.
            CGFloat speed = [self scrollSpeedForLabelWidth:width];
            CGFloat screenWidth = self.bounds.size.width;
            if (speed <= 0) speed = 100;
            NSTimeInterval tailClearTime = (width + screenWidth) / speed;
            self.scrollTracks[i] = @(time + tailClearTime * 0.6); // 60% to avoid overlap
            return i;
        }
    }
    return -1;
}

- (NSInteger)findFreeTrackForFixedDanmaku:(B2YDanmakuMode)mode atTime:(NSTimeInterval)time {
    NSMutableArray *tracks = (mode == B2YDanmakuModeTop) ? self.topTracks : self.bottomTracks;
    for (NSInteger i = 0; i < _trackCount && i < (NSInteger)tracks.count; i++) {
        NSTimeInterval freeAt = [tracks[i] doubleValue];
        if (time >= freeAt) {
            tracks[i] = @(time + kFixedDanmakuDuration);
            return i;
        }
    }
    return -1;
}

- (CGFloat)yForTrack:(NSInteger)track mode:(B2YDanmakuMode)mode {
    CGFloat y;
    if (mode == B2YDanmakuModeBottom) {
        // Bottom tracks fill from the bottom up.
        y = self.bounds.size.height - (track + 1) * _trackHeight;
    } else {
        // Top and scroll fill from the top down.
        y = track * _trackHeight;
    }
    return y;
}

#pragma mark - Advancement

- (void)advanceActiveDanmakuWithDt:(CFTimeInterval)dt
                       currentTime:(NSTimeInterval)currentTime {
    if (dt <= 0) return;

    for (NSInteger i = self.activeItems.count - 1; i >= 0; i--) {
        NSMutableDictionary *item = self.activeItems[i];
        UILabel *label = item[@"label"];
        B2YDanmakuMode mode = [item[@"mode"] integerValue];

        if (mode == B2YDanmakuModeTop || mode == B2YDanmakuModeBottom) {
            NSTimeInterval expiresAt = [item[@"expiresAt"] doubleValue];
            if (currentTime >= expiresAt) {
                [label removeFromSuperview];
                [self enqueueLabel:label];
                [self.activeItems removeObjectAtIndex:i];
            }
        } else {
            // Scrolling: move left by speed * dt.
            CGFloat speed = [item[@"speed"] doubleValue];
            CGRect f = label.frame;
            f.origin.x -= speed * dt;
            label.frame = f;

            // Recycle if fully off-screen.
            if (f.origin.x + f.size.width < 0) {
                [label removeFromSuperview];
                [self enqueueLabel:label];
                [self.activeItems removeObjectAtIndex:i];
            }
        }
    }
}

- (void)recycleOffscreenItems {
    // Already handled in advanceActiveDanmaku for scrolling; fixed
    // danmaku are handled by expiry. This is a no-op kept for clarity.
}

#pragma mark - Label pool

- (UILabel *)dequeueLabelForDanmaku:(B2YDanmaku *)d {
    UILabel *label = self.labelPool.lastObject;
    if (label) {
        [self.labelPool removeLastObject];
    } else {
        label = [[UILabel alloc] init];
        label.backgroundColor = [UIColor clearColor];
        label.numberOfLines = 1;
        label.adjustsFontSizeToFitWidth = NO;
        label.lineBreakMode = NSLineBreakByClipping;
        // Subtle dark shadow for readability over bright video frames.
        label.shadowColor = [UIColor blackColor];
        label.shadowOffset = CGSizeMake(1, 1);
    }
    return label;
}

- (void)enqueueLabel:(UILabel *)label {
    if (self.labelPool.count < kMaxActiveLabels) {
        [self.labelPool addObject:label];
    }
}

#pragma mark - Seek / clear

- (void)clearAll {
    for (NSMutableDictionary *item in self.activeItems) {
        UILabel *label = item[@"label"];
        [label removeFromSuperview];
    }
    [self.activeItems removeAllObjects];
    // Reset track availability (guard against empty arrays).
    for (NSInteger i = 0; i < _trackCount && i < (NSInteger)self.scrollTracks.count; i++) {
        self.scrollTracks[i] = @(0);
    }
    for (NSInteger i = 0; i < _trackCount && i < (NSInteger)self.topTracks.count; i++) {
        self.topTracks[i] = @(0);
    }
    for (NSInteger i = 0; i < _trackCount && i < (NSInteger)self.bottomTracks.count; i++) {
        self.bottomTracks[i] = @(0);
    }
}

- (void)handleSeekToTime:(NSTimeInterval)time {
    [self clearAll];
    [self.engine resetEmissionCursorToTime:time];
}

- (void)dealloc {
    [self stopRendering];
}

@end
