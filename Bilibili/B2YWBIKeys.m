//
//  B2YWBIKeys.m
//
//  WBI signature port. The mixin key permutation table and the overall
//  flow are lifted verbatim from the browser extension's background
//  script so that signatures match Bilibili's server-side validation.
//

#import "B2YWBIKeys.h"
#import "B2YMD5.h"

// The 64-entry permutation table Bilibili uses to derive the mixin key.
// Identical to `mixinKeyEncTab` in the original extension.
static const NSUInteger kMixinKeyEncTab[] = {
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
    33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61,
    26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36,
    20, 34, 44, 52
};

// Cache TTL: 6 hours, matching the extension.
static const NSTimeInterval kWBIKeysCacheTTL = 6 * 60 * 60;

@interface B2YWBIKeys ()
@property (nonatomic, copy) NSString *imgKey;
@property (nonatomic, copy) NSString *subKey;
@property (nonatomic, strong) NSDate *fetchedAt;
@end

// Module-level cache so every caller shares one fetch per TTL window.
static B2YWBIKeys *sCachedKeys = nil;
static NSDate *sCachedAt = nil;

@implementation B2YWBIKeys

+ (instancetype)fetchWithCookie:(NSString *)cookieHeader error:(NSError **)error {
    @synchronized(self) {
        if (sCachedKeys && sCachedAt &&
            [sCachedAt timeIntervalSinceNow] > -kWBIKeysCacheTTL) {
            return sCachedKeys;
        }
    }

    B2YWBIKeys *keys = [[B2YWBIKeys alloc] init];
    if (![keys refreshWithCookie:cookieHeader error:error]) {
        return nil;
    }

    @synchronized(self) {
        sCachedKeys = keys;
        sCachedAt = [NSDate date];
    }
    return keys;
}

- (BOOL)refreshWithCookie:(NSString *)cookieHeader error:(NSError **)error {
    // The nav endpoint returns the user's wbi_img keys alongside the
    // logged-in user info. We only need the two URL tails.
    NSString *urlStr = @"https://api.bilibili.com/x/web-interface/nav";
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:urlStr]];
    req.HTTPMethod = @"GET";
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) "
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1"
        forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"https://www.bilibili.com/" forHTTPHeaderField:@"Referer"];
    [req setValue:@"https://www.bilibili.com" forHTTPHeaderField:@"Origin"];
    if (cookieHeader.length > 0) {
        [req setValue:cookieHeader forHTTPHeaderField:@"Cookie"];
    }

    __block NSData *body = nil;
    __block NSError *localError = nil;

    // Synchronous wrapper - callers (search, segment fetch) are already
    // running on background queues, so blocking here is fine and keeps
    // the API trivially composable. Timeout: 15s (don't block forever).
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:req
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
              body = data;
              localError = err;
              dispatch_semaphore_signal(sem);
          }];
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));

    if (localError) {
        if (error) *error = localError;
        return NO;
    }

    NSError *jsonError = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body
                                                         options:0
                                                           error:&jsonError];
    if (jsonError || ![json isKindOfClass:[NSDictionary class]]) {
        if (error) *error = jsonError;
        return NO;
    }

    NSDictionary *data = json[@"data"];
    if (![data isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"B2YWBIKeys"
                                        code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"nav response missing data"}];
        }
        return NO;
    }

    NSDictionary *wbiImg = data[@"wbi_img"];
    NSString *imgURL = wbiImg[@"img_url"];
    NSString *subURL = wbiImg[@"sub_url"];
    if (!imgURL.length || !subURL.length) {
        if (error) {
            *error = [NSError errorWithDomain:@"B2YWBIKeys"
                                        code:2
                                    userInfo:@{NSLocalizedDescriptionKey: @"nav response missing wbi_img"}];
        }
        return NO;
    }

    // Extract the basename (without extension) of each URL.
    // e.g. https://i0.hdslb.com/bfs/wbi/7cd08e941c0a5c2c4c4c4c4c4c4c4c4c.png -> 7cd08e941c0a5c2c4c4c4c4c4c4c4c4c
    self.imgKey = [self basenameWithoutExtension:imgURL];
    self.subKey = [self basenameWithoutExtension:subURL];
    self.fetchedAt = [NSDate date];

    if (!self.imgKey.length || !self.subKey.length) {
        if (error) {
            *error = [NSError errorWithDomain:@"B2YWBIKeys"
                                        code:3
                                    userInfo:@{NSLocalizedDescriptionKey: @"failed to parse wbi keys from URLs"}];
        }
        return NO;
    }
    return YES;
}

- (NSString *)basenameWithoutExtension:(NSString *)urlString {
    // Last path component, strip the file extension.
    NSString *last = urlString.lastPathComponent;
    NSString *stem = [last stringByDeletingPathExtension];
    return stem ?: @"";
}

- (NSString *)mixinKey {
    // Concatenate img_key + sub_key, then pick characters at the indices
    // given by kMixinKeyEncTab, take the first 32.
    NSString *combined = [self.imgKey stringByAppendingString:self.subKey];
    NSMutableString *mixed = [NSMutableString stringWithCapacity:32];
    for (NSUInteger i = 0; i < 64; i++) {
        NSUInteger idx = kMixinKeyEncTab[i];
        if (idx < combined.length) {
            [mixed appendFormat:@"%C", [combined characterAtIndex:idx]];
        }
        if (mixed.length >= 32) break;
    }
    // The JS slice(0, 32) guarantees exactly 32 chars.
    if (mixed.length > 32) {
        return [mixed substringToIndex:32];
    }
    return mixed;
}

- (NSString *)signedQueryStringFromParams:(NSDictionary<NSString *, id> *)params {
    // 1. Drop nil/empty values, stringify the rest, strip a few punctuation
    //    chars that Bilibili's server rejects.
    NSMutableString *query = [NSMutableString string];
    NSArray *sortedKeys = [[params allKeys] sortedArrayUsingSelector:@selector(compare:)];
    BOOL first = YES;
    for (NSString *key in sortedKeys) {
        id value = params[key];
        if (value == nil) continue;
        NSString *valueStr = [NSString stringWithFormat:@"%@", value];
        if (valueStr.length == 0) continue;

        // chr_filter: /[!'()*]/g  -> remove these chars.
        NSString *filtered = [self stripUnsafeChars:valueStr];

        if (!first) [query appendString:@"&"];
        [query appendFormat:@"%@=%@",
            [self percentEncode:key],
            [self percentEncode:filtered]];
        first = NO;
    }

    // 2. Append wts (current unix time).
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (!first) [query appendString:@"&"];
    [query appendFormat:@"wts=%ld", (long)now];

    // 3. Compute w_rid = md5(query + mixin_key).
    NSString *mixin = [self mixinKey];
    NSString *toSign = [query stringByAppendingString:mixin];
    NSString *wRid = [B2YMD5 md5OfString:toSign];
    [query appendFormat:@"&w_rid=%@", wRid];

    return query;
}

- (NSString *)stripUnsafeChars:(NSString *)s {
    // Bilibili's chr_filter removes single-quote, parens, and star.
    NSMutableCharacterSet *unsafe = [NSMutableCharacterSet characterSetWithCharactersInString:@"!'()*"];
    NSArray *parts = [s componentsSeparatedByCharactersInSet:unsafe];
    return [parts componentsJoinedByString:@""];
}

- (NSString *)percentEncode:(NSString *)s {
    // encodeURIComponent equivalent. NSCharacterSet.URLHostAllowedCharacterSet
    // is close but not identical; we build the set explicitly to match JS.
    NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@"-_.!~*'()"];
    // Note: we encode the unsafe chars above separately, so they won't
    // survive to this point.
    NSString *encoded = [s stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    return encoded ?: @"";
}

@end
