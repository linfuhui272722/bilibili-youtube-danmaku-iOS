//
//  B2YVideoMatcher.m
//

#import "B2YVideoMatcher.h"
#import "B2YDanmakuModel.h"

@implementation B2YVideoMatcher

+ (NSString *)normaliseTitle:(NSString *)title {
    if (!title) return @"";

    NSString *s = [title copy];

    // Strip bracketed annotations: (4K), [Official MV], 【字幕】, etc.
    // We remove the contents too because they rarely help matching and
    // often differ between Bilibili and YouTube uploads.
    NSRegularExpression *bracketRe =
        [NSRegularExpression regularExpressionWithPattern:
            @"[\\(\\[【{<][^\\)\\]】}>]*[\\)\\]】}>]"
                                                  options:0
                                                    error:nil];
    s = [bracketRe stringByReplacingMatchesInString:s
                                            options:0
                                              range:NSMakeRange(0, s.length)
                                       withTemplate:@""];

    // Strip emoji and other symbols outside the basic multilingual plane.
    // Bilibili titles frequently carry emoji that YouTube uploads omit.
    NSRegularExpression *emojiRe =
        [NSRegularExpression regularExpressionWithPattern:
            @"[\\u{1F000}-\\u{1FFFF}\\u{2600}-\\u{27BF}\\u{2B00}-\\u{2BFF}]"
                                                  options:0
                                                    error:nil];
    s = [emojiRe stringByReplacingMatchesInString:s
                                          options:0
                                            range:NSMakeRange(0, s.length)
                                     withTemplate:@""];

    // Collapse whitespace and lowercase.
    NSMutableString *clean = [s mutableCopy];
    [clean replaceOccurrencesOfString:@"\t" withString:@" "
                              options:0 range:NSMakeRange(0, clean.length)];
    [clean replaceOccurrencesOfString:@"\n" withString:@" "
                              options:0 range:NSMakeRange(0, clean.length)];
    [clean replaceOccurrencesOfString:@"  " withString:@" "
                              options:0 range:NSMakeRange(0, clean.length)
                                 whileMatching:NO];
    NSString *trimmed = [clean stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceCharacterSet]];

    return trimmed.lowercaseString ?: @"";
}

+ (NSUInteger)levenshtein:(NSString *)a and:(NSString *)b {
    if (a.length == 0) return b.length;
    if (b.length == 0) return a.length;

    NSUInteger n = a.length;
    NSUInteger m = b.length;

    // Two rolling rows to keep memory O(min(n,m)).
    NSMutableArray *prev = [NSMutableArray arrayWithCapacity:m + 1];
    NSMutableArray *curr = [NSMutableArray arrayWithCapacity:m + 1];
    for (NSUInteger j = 0; j <= m; j++) {
        [prev addObject:@(j)];
        [curr addObject:@0];
    }

    for (NSUInteger i = 1; i <= n; i++) {
        curr[0] = @(i);
        unichar ci = [a characterAtIndex:i - 1];
        for (NSUInteger j = 1; j <= m; j++) {
            NSUInteger cost = (ci == [b characterAtIndex:j - 1]) ? 0 : 1;
            NSUInteger del = [prev[j] unsignedIntegerValue] + 1;
            NSUInteger ins = [curr[j - 1] unsignedIntegerValue] + 1;
            NSUInteger sub = [prev[j - 1] unsignedIntegerValue] + cost;
            NSUInteger minVal = MIN(del, ins);
            minVal = MIN(minVal, sub);
            curr[j] = @(minVal);
        }
        // Swap prev and curr.
        NSMutableArray *tmp = prev;
        prev = curr;
        curr = tmp;
    }
    return [prev[m] unsignedIntegerValue];
}

+ (NSInteger)similarityBetween:(NSString *)a and:(NSString *)b {
    NSString *na = [self normaliseTitle:a];
    NSString *nb = [self normaliseTitle:b];
    if (na.length == 0 && nb.length == 0) return 100;
    NSUInteger maxLen = MAX(na.length, nb.length);
    if (maxLen == 0) return 100;
    NSUInteger dist = [self levenshtein:na and:nb];
    double ratio = 1.0 - (double)dist / (double)maxLen;
    return (NSInteger)(ratio * 100.0);
}

+ (B2YBilibiliVideo *)bestMatchForYouTubeTitle:(NSString *)ytTitle
                                    fromResults:(NSArray<B2YBilibiliVideo *> *)results
                                      threshold:(NSInteger)threshold {
    if (ytTitle.length == 0 || results.count == 0) return nil;

    // Score every result, keep those above threshold.
    NSMutableArray<B2YBilibiliVideo *> *qualified = [NSMutableArray array];
    for (B2YBilibiliVideo *v in results) {
        NSInteger score = [self similarityBetween:ytTitle and:v.title];
        v.matchScore = score;
        if (score >= threshold) {
            [qualified addObject:v];
        }
    }
    if (qualified.count == 0) return nil;

    // Sort: highest score first; on tie, most danmaku first.
    [qualified sortUsingComparator:^NSComparisonResult(B2YBilibiliVideo *a,
                                                       B2YBilibiliVideo *b) {
        if (a.matchScore != b.matchScore) {
            return a.matchScore > b.matchScore ? NSOrderedAscending : NSOrderedDescending;
        }
        if (a.danmakuCount != b.danmakuCount) {
            return a.danmakuCount > b.danmakuCount ? NSOrderedAscending : NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    return qualified.firstObject;
}

@end
