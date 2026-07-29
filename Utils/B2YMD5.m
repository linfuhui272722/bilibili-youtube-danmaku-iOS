//
//  B2YMD5.m
//

#import "B2YMD5.h"
#import <CommonCrypto/CommonDigest.h>

@implementation B2YMD5

+ (NSString *)md5OfString:(NSString *)string {
    if (!string) return @"";
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    return [self md5OfData:data];
}

+ (NSString *)md5OfData:(NSData *)data {
    NSData *digest = [self rawMd5OfData:data];
    if (!digest) return @"";

    // Convert 16 raw bytes to a 32-char lowercase hex string.
    const unsigned char *bytes = digest.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:32];
    for (NSUInteger i = 0; i < digest.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return hex;
}

+ (NSData *)rawMd5OfData:(NSData *)data {
    if (!data) return nil;
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, digest);
    return [NSData dataWithBytes:digest length:CC_MD5_DIGEST_LENGTH];
}

@end
