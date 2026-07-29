//
//  B2YDanmakuModel.h
//  B2YDanmaku
//
//  Plain data objects representing the Bilibili entities we care about:
//   - B2YBilibiliVideo: a search result (bvid, title, author, duration, ...)
//   - B2YDanmaku:       a single danmaku entry (text, time, color, mode, ...)
//
//  Both are immutable value types; we expose mutable copies of the few
//  fields the matcher needs to annotate (matchScore).
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, B2YDanmakuMode) {
    B2YDanmakuModeScroll   = 1,  // right-to-left scrolling (default)
    B2YDanmakuModeScrollReverse = 6, // left-to-right (rare)
    B2YDanmakuModeBottom   = 4,  // bottom-fixed
    B2YDanmakuModeTop      = 5,  // top-fixed
    B2YDanmakuModeAdvanced = 7,  // advanced (treated as scroll)
    B2YDanmakuModeCode     = 8,  // code/BAS (ignored)
};

@interface B2YBilibiliVideo : NSObject

@property (nonatomic, copy)   NSString *bvid;       // BV1xx411c7mD
@property (nonatomic, assign) NSInteger aid;        // av123456
@property (nonatomic, assign) NSInteger cid;        // danmaku segment key
@property (nonatomic, copy)   NSString *title;
@property (nonatomic, copy)   NSString *author;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) NSInteger danmakuCount; // from search hit
@property (nonatomic, copy)   NSString *coverURL;
@property (nonatomic, assign) NSInteger matchScore;   // filled by matcher

@end

@interface B2YDanmaku : NSObject

// Core fields parsed from the protobuf segment.
@property (nonatomic, copy)   NSString *text;
@property (nonatomic, assign) NSTimeInterval time;   // seconds (progress / 1000)
@property (nonatomic, assign) uint32_t color;        // 0xRRGGBB
@property (nonatomic, assign) B2YDanmakuMode mode;
@property (nonatomic, assign) NSInteger fontsize;
@property (nonatomic, assign) NSInteger weight;

// Runtime state managed by the engine. Not part of the wire format.
@property (nonatomic, assign) BOOL emitted;
@property (nonatomic, strong, nullable) id animationHandle;

+ (uint32_t)colorFromRGB:(uint32_t)rgb;
+ (UIColor *)uiColorFromRGB:(uint32_t)rgb;

@end

NS_ASSUME_NONNULL_END
