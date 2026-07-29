//
//  B2YDanmakuModel.m
//

#import "B2YDanmakuModel.h"

@implementation B2YBilibiliVideo
@end

@implementation B2YDanmaku

+ (uint32_t)colorFromRGB:(uint32_t)rgb {
    // Bilibili stores color as a packed 0xRRGGBB integer. White is 0xFFFFFF.
    return rgb & 0xFFFFFF;
}

+ (UIColor *)uiColorFromRGB:(uint32_t)rgb {
    CGFloat r = ((rgb >> 16) & 0xFF) / 255.0;
    CGFloat g = ((rgb >> 8)  & 0xFF) / 255.0;
    CGFloat b = ( rgb        & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:1.0];
}

@end
