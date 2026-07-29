//
//  B2YSettings.h
//  B2YDanmaku
//
//  Thin wrapper around NSUserDefaults that scopes every key under a single
//  prefix so we never collide with YouTube's own preferences.
//
//  Why a wrapper instead of using NSUserDefaults directly?
//   - Centralises the key list (compiler-checked, refactor-friendly).
//   - Lets us ship a "reset" entrypoint from the settings panel.
//   - Survives YouTube reinstalls because we write to the app group
//     container when one is available (rootless jailbreaks), falling
//     back to standard NSUserDefaults otherwise.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Preference keys. Keep these stable across versions - changing a key
// name silently resets the user's settings.
extern NSString *const kB2YEnabledKey;
extern NSString *const kB2YAutoMatchKey;
extern NSString *const kB2YManualBVIDKey;
extern NSString *const kB2YTimeOffsetKey;
extern NSString *const kB2YOpacityKey;
extern NSString *const kB2YFontSizeKey;
extern NSString *const kB2YScrollSpeedKey;
extern NSString *const kB2YTrackSpacingKey;
extern NSString *const kB2YDisplayAreaKey;
extern NSString *const kB2YWeightThresholdKey;
extern NSString *const kB2YFilterColorKey;
extern NSString *const kB2YFilterLowWeightKey;
extern NSString *const kB2YShowDebugLogKey;
extern NSString *const kB2YCookieSESSDATAKey;
extern NSString *const kB2YMatchThresholdKey;
extern NSString *const kB2YMaxDanmakuKey;

@interface B2YSettings : NSObject

+ (instancetype)shared;

// Typed accessors.
- (BOOL)boolForKey:(NSString *)key;
- (NSInteger)integerForKey:(NSString *)key;
- (float)floatForKey:(NSString *)key;
- (NSString * _Nullable)stringForKey:(NSString *)key;

- (void)setBool:(BOOL)value forKey:(NSString *)key;
- (void)setInteger:(NSInteger)value forKey:(NSString *)key;
- (void)setFloat:(float)value forKey:(NSString *)key;
- (void)setString:(NSString *)value forKey:(NSString *)key;

// Register the default values. Called once at tweak load.
- (void)registerDefaults;

// Wipe every B2Y* key (used by the "Reset Settings" cell).
- (void)resetAll;

// Convenience: returns the cookie header value to attach to Bilibili
// requests, built from the user-supplied SESSDATA. Empty string if the
// user hasn't logged in.
- (NSString *)bilibiliCookieHeader;

@end

NS_ASSUME_NONNULL_END
