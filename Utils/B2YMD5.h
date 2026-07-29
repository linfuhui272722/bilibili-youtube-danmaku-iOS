//
//  B2YMD5.h
//  B2YDanmaku
//
//  MD5 helper used by the WBI signature routine. We wrap CommonCrypto's
//  CC_MD5 so the rest of the codebase can stay in pure Foundation
//  without importing <CommonCrypto/CommonDigest.h> everywhere.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface B2YMD5 : NSObject

// Returns the lowercase hex MD5 digest of `string` (UTF-8 encoded).
+ (NSString *)md5OfString:(NSString *)string;

// Returns the lowercase hex MD5 digest of an arbitrary NSData.
+ (NSString *)md5OfData:(NSData *)data;

// Returns the raw 16-byte MD5 digest as NSData (used when we need the
// binary form, e.g. for HMAC-style constructions).
+ (NSData *)rawMd5OfData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
