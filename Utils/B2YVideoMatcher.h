//
//  B2YVideoMatcher.h
//  B2YDanmaku
//
//  Decides which Bilibili search result corresponds to the YouTube video
//  currently being watched. Mirrors the matching heuristics of the
//  original browser extension:
//
//   1. Normalise both titles (strip emoji, fold whitespace, lowercase).
//   2. Compute a similarity score (Levenshtein-based ratio).
//   3. If multiple results clear the threshold, prefer the one with the
//      most danmaku (matches the extension's `order: 'dm'` behaviour).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class B2YBilibiliVideo;

@interface B2YVideoMatcher : NSObject

// Normalise a title for matching: trims, lowercases, collapses internal
// whitespace, strips bracketed annotations like "(4K)" or "[Official MV]".
+ (NSString *)normaliseTitle:(NSString *)title;

// Levenshtein edit distance between two strings.
+ (NSUInteger)levenshtein:(NSString *)a and:(NSString *)b;

// Similarity ratio in [0, 100]. 100 means identical after normalisation.
+ (NSInteger)similarityBetween:(NSString *)a and:(NSString *)b;

// Given a YouTube video title and an array of Bilibili search results,
// returns the best match whose similarity is >= the threshold, or nil
// if none qualifies. When several results tie, the one with the most
// danmaku (highest `video.danmakuCount`) wins.
+ (nullable B2YBilibiliVideo *)bestMatchForYouTubeTitle:(NSString *)ytTitle
                                            fromResults:(NSArray<B2YBilibiliVideo *> *)results
                                              threshold:(NSInteger)threshold;

@end

NS_ASSUME_NONNULL_END
