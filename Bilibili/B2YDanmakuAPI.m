//
//  B2YDanmakuAPI.m
//
//  Network layer. Uses NSURLSession with a custom configuration that
//  pins a desktop User-Agent and the Bilibili Referer/Origin headers,
//  matching the original extension's fetch options.
//

#import "B2YDanmakuAPI.h"
#import "B2YDanmakuModel.h"
#import "B2YWBIKeys.h"
#import "B2YProtobufParser.h"
#import "B2YVideoMatcher.h"
#import "B2YSettings.h"

// Endpoints (identical to the browser extension).
static NSString *const kSearchAllURL   = @"https://api.bilibili.com/x/web-interface/wbi/search/all/v2";
static NSString *const kViewURL         = @"https://api.bilibili.com/x/web-interface/view";
static NSString *const kSegmentURL       = @"https://api.bilibili.com/x/v2/dm/wbi/web/seg.so";
static NSString *const kNavURL           = @"https://api.bilibili.com/x/web-interface/nav";

// Segment length: 6 minutes (360 seconds), per Bilibili's convention.
static const NSTimeInterval kSegmentDuration = 360.0;
// Polite delay between segment fetches to avoid rate-limiting.
static const NSTimeInterval kSegmentFetchDelay = 0.3;

@interface B2YDanmakuAPI ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) B2YProtobufParser *parser;
@end

@implementation B2YDanmakuAPI

+ (instancetype)shared {
    static B2YDanmakuAPI *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[B2YDanmakuAPI alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 15;
        cfg.timeoutIntervalForResource = 60;
        cfg.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyAlways;
        cfg.HTTPShouldSetCookies = YES;
        // Use the shared cookie storage (not an app-group one, since the
        // tweak runs inside YouTube's process and has no app group).
        cfg.HTTPCookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        _session = [NSURLSession sessionWithConfiguration:cfg];
        _queue = dispatch_queue_create("com.ahaduoduoduo.b2y.api", DISPATCH_QUEUE_SERIAL);
        _parser = [[B2YProtobufParser alloc] init];
    }
    return self;
}

#pragma mark - URL building helpers

- (NSMutableURLRequest *)requestWithURL:(NSURL *)url cookie:(NSString *)cookie {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:15];
    // Desktop UA - Bilibili serves different payloads to mobile UAs.
    [req setValue:@"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
   forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"https://www.bilibili.com/" forHTTPHeaderField:@"Referer"];
    [req setValue:@"https://www.bilibili.com" forHTTPHeaderField:@"Origin"];
    if (cookie.length > 0) {
        [req setValue:cookie forHTTPHeaderField:@"Cookie"];
    }
    return req;
}

- (NSDictionary *)httpHeadersForSearch {
    return @{
        @"User-Agent": @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        @"Referer": @"https://search.bilibili.com/",
        @"Origin": @"https://www.bilibili.com"
    };
}

#pragma mark - Search

- (void)searchVideosWithKeyword:(NSString *)keyword
                         cookie:(NSString *)cookie
                     completion:(void (^)(NSArray<B2YBilibiliVideo *> * _Nullable,
                                          NSError * _Nullable))completion {
    dispatch_async(self.queue, ^{
        // 1. Get WBI keys.
        NSError *wbiErr = nil;
        B2YWBIKeys *wbi = [B2YWBIKeys fetchWithCookie:cookie error:&wbiErr];
        if (!wbi) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, wbiErr ?: [NSError errorWithDomain:@"B2Y" code:1
                                                          userInfo:@{NSLocalizedDescriptionKey: @"WBI key fetch failed"}]);
            });
            return;
        }

        // 2. Build signed query.
        NSDictionary *params = @{
            @"keyword": keyword ?: @"",
            @"order": @"dm",
            @"wts": @((NSInteger)[[NSDate date] timeIntervalSince1970])
        };
        NSString *query = [wbi signedQueryStringFromParams:params];
        NSString *urlStr = [NSString stringWithFormat:@"%@?%@", kSearchAllURL, query];

        NSMutableURLRequest *req = [self requestWithURL:[NSURL URLWithString:urlStr] cookie:cookie];
        for (NSString *k in self.httpHeadersForSearch) {
            [req setValue:self.httpHeadersForSearch[k] forHTTPHeaderField:k];
        }

        // 3. Fire request.
        NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, error);
                    });
                    return;
                }
                NSArray *results = [self parseSearchResults:data];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(results, nil);
                });
            }];
        [task resume];
    });
}

// Parse the search/all/v2 response. The result is a nested structure of
// `result` -> `video` -> array of `type`-tagged renderers; we only care
// about `type == "video"` entries.
- (NSArray<B2YBilibiliVideo *> *)parseSearchResults:(NSData *)data {
    if (!data.length) return @[];
    NSError *jsonErr = nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data
                                                        options:0
                                                          error:&jsonErr];
    if (!root || ![root isKindOfClass:[NSDictionary class]]) return @[];

    NSInteger code = [root[@"code"] integerValue];
    if (code != 0) return @[];

    NSDictionary *dataDict = root[@"data"];
    if (![dataDict isKindOfClass:[NSDictionary class]]) return @[];

    NSMutableArray<B2YBilibiliVideo *> *results = [NSMutableArray array];
    NSArray *resultArray = dataDict[@"result"];
    if (![resultArray isKindOfClass:[NSArray class]]) return @[];

    for (NSDictionary *section in resultArray) {
        if (![section isKindOfClass:[NSDictionary class]]) continue;
        NSString *type = section[@"result_type"];
        if (![type isEqualToString:@"video"]) continue;

        NSArray *videos = section[@"data"];
        if (![videos isKindOfClass:[NSArray class]]) continue;

        for (NSDictionary *v in videos) {
            if (![v isKindOfClass:[NSDictionary class]]) continue;
            B2YBilibiliVideo *video = [[B2YBilibiliVideo alloc] init];
            video.bvid = v[@"bvid"] ?: @"";
            video.aid = [v[@"aid"] integerValue];
            video.title = [self stripHtmlTags:v[@"title"]];
            video.author = v[@"author"] ?: @"";
            video.duration = [self parseDurationString:v[@"duration"]];
            video.danmakuCount = [v[@"video_review"] integerValue]; // danmaku count field
            video.coverURL = v[@"pic"] ?: @"";
            if (video.bvid.length > 0) {
                [results addObject:video];
            }
        }
    }

    return results;
}

- (NSString *)stripHtmlTags:(NSString *)s {
    if (!s || ![s isKindOfClass:[NSString class]]) return @"";
    // Bilibili wraps matched keywords in <em class="keyword">...</em>.
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>"
                                                                       options:0
                                                                         error:&err];
    return [re stringByReplacingMatchesInString:s
                                         options:0
                                           range:NSMakeRange(0, s.length)
                                    withTemplate:@""];
}

- (NSTimeInterval)parseDurationString:(id)obj {
    if (!obj) return 0;
    if ([obj isKindOfClass:[NSNumber class]]) {
        return [obj doubleValue];
    }
    if ([obj isKindOfClass:[NSString class]]) {
        // Format: "HH:MM:SS" or "MM:SS"
        NSArray *parts = [obj componentsSeparatedByString:@":"];
        NSTimeInterval total = 0;
        for (NSString *p in parts) {
            total = total * 60 + [p integerValue];
        }
        return total;
    }
    return 0;
}

#pragma mark - Video info

- (void)fetchVideoInfoWithBVID:(NSString *)bvid
                        cookie:(NSString *)cookie
                    completion:(void (^)(B2YBilibiliVideo * _Nullable,
                                         NSError * _Nullable))completion {
    dispatch_async(self.queue, ^{
        NSString *urlStr = [NSString stringWithFormat:@"%@?bvid=%@", kViewURL, bvid];
        NSMutableURLRequest *req = [self requestWithURL:[NSURL URLWithString:urlStr] cookie:cookie];

        NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(nil, error);
                    });
                    return;
                }
                B2YBilibiliVideo *video = [self parseVideoInfo:data bvid:bvid];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(video, nil);
                });
            }];
        [task resume];
    });
}

- (B2YBilibiliVideo *)parseVideoInfo:(NSData *)data bvid:(NSString *)bvid {
    if (!data.length) return nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![root isKindOfClass:[NSDictionary class]]) return nil;
    if ([root[@"code"] integerValue] != 0) return nil;

    NSDictionary *d = root[@"data"];
    if (![d isKindOfClass:[NSDictionary class]]) return nil;

    B2YBilibiliVideo *video = [[B2YBilibiliVideo alloc] init];
    video.bvid = bvid;
    video.aid = [d[@"aid"] integerValue];
    video.cid = [d[@"cid"] integerValue];
    video.title = d[@"title"] ?: @"";
    NSDictionary *owner = d[@"owner"];
    if ([owner isKindOfClass:[NSDictionary class]]) {
        video.author = owner[@"name"] ?: @"";
    }
    video.duration = [d[@"duration"] doubleValue];
    NSDictionary *stat = d[@"stat"];
    if ([stat isKindOfClass:[NSDictionary class]]) {
        video.danmakuCount = [stat[@"danmaku"] integerValue];
    }
    video.coverURL = d[@"pic"] ?: @"";
    return video;
}

#pragma mark - Danmaku segments

- (void)downloadAllDanmakuForVideo:(B2YBilibiliVideo *)video
                            cookie:(NSString *)cookie
                        completion:(void (^)(NSArray<B2YDanmaku *> * _Nullable,
                                             NSError * _Nullable))completion {
    dispatch_async(self.queue, ^{
        if (video.cid == 0) {
            // Need to fetch cid first.
            NSError *infoErr = nil;
            B2YBilibiliVideo *full = [self syncFetchVideoInfo:video.bvid cookie:cookie error:&infoErr];
            if (!full) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, infoErr ?: [NSError errorWithDomain:@"B2Y" code:2
                                                              userInfo:@{NSLocalizedDescriptionKey: @"Failed to fetch video info"}]);
                });
                return;
            }
            video.cid = full.cid;
            video.aid = full.aid;
            video.duration = full.duration;
        }

        NSError *wbiErr = nil;
        B2YWBIKeys *wbi = [B2YWBIKeys fetchWithCookie:cookie error:&wbiErr];
        if (!wbi) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, wbiErr);
            });
            return;
        }

        NSInteger segmentCount = (NSInteger)ceil(video.duration / kSegmentDuration);
        if (segmentCount < 1) segmentCount = 1;

        NSMutableArray<B2YDanmaku *> *all = [NSMutableArray array];

        for (NSInteger i = 1; i <= segmentCount; i++) {
            NSArray<B2YDanmaku *> *seg = [self syncFetchSegment:video.cid
                                                            aid:video.aid
                                                       segment:i
                                                          wbi:wbi
                                                        cookie:cookie];
            [all addObjectsFromArray:seg];

            if (i < segmentCount) {
                [NSThread sleepForTimeInterval:kSegmentFetchDelay];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(all, nil);
        });
    });
}

// Synchronous segment fetch (called from self.queue).
- (NSArray<B2YDanmaku *> *)syncFetchSegment:(NSInteger)cid
                                         aid:(NSInteger)aid
                                    segment:(NSInteger)segmentIndex
                                       wbi:(B2YWBIKeys *)wbi
                                     cookie:(NSString *)cookie {
    NSDictionary *params = @{
        @"oid": @(cid),
        @"pid": @(aid),
        @"segment_index": @(segmentIndex),
        @"type": @"1",
        @"web_location": @"1315875",
        @"wts": @((NSInteger)[[NSDate date] timeIntervalSince1970])
    };
    NSString *query = [wbi signedQueryStringFromParams:params];
    NSString *urlStr = [NSString stringWithFormat:@"%@?%@", kSegmentURL, query];

    NSMutableURLRequest *req = [self requestWithURL:[NSURL URLWithString:urlStr] cookie:cookie];

    __block NSData *responseData = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            responseData = data;
            dispatch_semaphore_signal(sem);
        }];
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));

    if (!responseData.length) return @[];

    // The segment endpoint returns raw protobuf bytes.
    return [self.parser parseDanmakuSegment:responseData];
}

// Synchronous video info fetch (called from self.queue).
- (B2YBilibiliVideo *)syncFetchVideoInfo:(NSString *)bvid
                                  cookie:(NSString *)cookie
                                   error:(NSError **)error {
    NSString *urlStr = [NSString stringWithFormat:@"%@?bvid=%@", kViewURL, bvid];
    NSMutableURLRequest *req = [self requestWithURL:[NSURL URLWithString:urlStr] cookie:cookie];

    __block NSData *responseData = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
            responseData = data;
            if (err && error) *error = err;
            dispatch_semaphore_signal(sem);
        }];
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));

    return [self parseVideoInfo:responseData bvid:bvid];
}

#pragma mark - Combined flow

- (void)loadDanmakuForYouTubeTitle:(NSString *)ytTitle
                    youTubeDuration:(NSTimeInterval)ytDuration
                            cookie:(NSString *)cookie
                       matchThreshold:(NSInteger)threshold
                     matchCallback:(void (^)(B2YBilibiliVideo * _Nullable,
                                             NSArray<B2YBilibiliVideo *> *))matchCallback
                        completion:(void (^)(NSArray<B2YDanmaku *> * _Nullable,
                                             NSError * _Nullable))completion {
    [self searchVideosWithKeyword:ytTitle cookie:cookie completion:^(NSArray<B2YBilibiliVideo *> *results, NSError *error) {
        if (error || results.count == 0) {
            if (matchCallback) matchCallback(nil, results ?: @[]);
            if (completion) completion(nil, error);
            return;
        }

        B2YBilibiliVideo *matched = [B2YVideoMatcher bestMatchForYouTubeTitle:ytTitle
                                                                   fromResults:results
                                                                     threshold:threshold];
        if (matchCallback) matchCallback(matched, results);

        if (!matched) {
            if (completion) completion(nil, [NSError errorWithDomain:@"B2Y" code:3
                                                          userInfo:@{NSLocalizedDescriptionKey: @"No matching Bilibili video found"}]);
            return;
        }

        [self downloadAllDanmakuForVideo:matched cookie:cookie completion:completion];
    }];
}

- (void)loadDanmakuForBVID:(NSString *)bvid
                    cookie:(NSString *)cookie
                completion:(void (^)(NSArray<B2YDanmaku *> * _Nullable,
                                     NSError * _Nullable))completion {
    [self fetchVideoInfoWithBVID:bvid cookie:cookie completion:^(B2YBilibiliVideo *video, NSError *error) {
        if (error || !video) {
            if (completion) completion(nil, error);
            return;
        }
        [self downloadAllDanmakuForVideo:video cookie:cookie completion:completion];
    }];
}

@end
