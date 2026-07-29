//
//  B2YWBIKeys.h
//  B2YDanmaku
//
//  Bilibili's WBI signature scheme.
//
//  Most modern Bilibili web API endpoints (search, danmaku segment, ...)
//  require a `w_rid` query parameter computed as:
//
//      w_rid = md5(sorted_query_string + mixin_key)
//
//  where `mixin_key` is derived from two keys (`img_key`, `sub_key`)
//  fetched from the navigation endpoint, by:
//
//      mixin_key = (img_key + sub_key)[mixinKeyEncTab].prefix(32)
//
//  This file ports the JS implementation in the original browser
//  extension (`entrypoints/background/index.js`) to Objective-C.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface B2YWBIKeys : NSObject

@property (nonatomic, copy, readonly) NSString *imgKey;
@property (nonatomic, copy, readonly) NSString *subKey;

// Fetch a fresh pair of WBI keys from the Bilibili nav endpoint.
// Caches them in-memory for 6 hours (matching the extension's TTL).
// `cookieHeader` is the raw Cookie header value (may be empty).
+ (nullable instancetype)fetchWithCookie:(NSString *)cookieHeader
                                   error:(NSError **)error;

// Build the signed query string for a set of parameters.
// Adds `wts` (current unix timestamp) and `w_rid` automatically.
- (NSString *)signedQueryStringFromParams:(NSDictionary<NSString *, id> *)params;

// Per-instance fetch (used by tests / when you want to reuse a pair).
- (BOOL)refreshWithCookie:(NSString *)cookieHeader error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
