//
//  B2YSettings.m
//

#import "B2YSettings.h"

// Preference keys - all prefixed with `b2y_` so a future `defaults read`
// never picks up unrelated YouTube keys.
NSString *const kB2YEnabledKey          = @"b2y_enabled";
NSString *const kB2YAutoMatchKey        = @"b2y_auto_match";
NSString *const kB2YManualBVIDKey        = @"b2y_manual_bvid";
NSString *const kB2YTimeOffsetKey       = @"b2y_time_offset";
NSString *const kB2YOpacityKey           = @"b2y_opacity";
NSString *const kB2YFontSizeKey          = @"b2y_font_size";
NSString *const kB2YScrollSpeedKey       = @"b2y_scroll_speed";
NSString *const kB2YTrackSpacingKey      = @"b2y_track_spacing";
NSString *const kB2YDisplayAreaKey       = @"b2y_display_area";
NSString *const kB2YWeightThresholdKey   = @"b2y_weight_threshold";
NSString *const kB2YFilterColorKey       = @"b2y_filter_color";
NSString *const kB2YFilterLowWeightKey   = @"b2y_filter_low_weight";
NSString *const kB2YShowDebugLogKey      = @"b2y_debug_log";
NSString *const kB2YCookieSESSDATAKey    = @"b2y_sessdata";
NSString *const kB2YMatchThresholdKey    = @"b2y_match_threshold";
NSString *const kB2YMaxDanmakuKey        = @"b2y_max_danmaku";

@implementation B2YSettings

+ (instancetype)shared {
    static B2YSettings *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[B2YSettings alloc] init];
        [instance registerDefaults];
    });
    return instance;
}

- (NSUserDefaults *)defaults {
    // We deliberately use standardDefaults so the values survive across
    // YouTube app upgrades. On rootless jailbreaks the tweak is injected
    // into the YouTube process, so standardDefaults still points at
    // YouTube's own preference domain - exactly what we want.
    return [NSUserDefaults standardUserDefaults];
}

- (void)registerDefaults {
    NSDictionary *defaults = @{
        kB2YEnabledKey:          @YES,
        kB2YAutoMatchKey:        @YES,
        kB2YManualBVIDKey:       @"",
        kB2YTimeOffsetKey:       @0.0,
        kB2YOpacityKey:          @100,
        kB2YFontSizeKey:         @24,
        kB2YScrollSpeedKey:      @1.0,
        kB2YTrackSpacingKey:     @8,
        kB2YDisplayAreaKey:      @100,
        kB2YWeightThresholdKey:  @0,
        kB2YFilterColorKey:      @NO,
        kB2YFilterLowWeightKey:  @NO,
        kB2YShowDebugLogKey:      @NO,
        kB2YCookieSESSDATAKey:    @"",
        kB2YMatchThresholdKey:    @60,
        kB2YMaxDanmakuKey:        @5000
    };
    [[self defaults] registerDefaults:defaults];
}

#pragma mark - Typed accessors

- (BOOL)boolForKey:(NSString *)key   { return [[self defaults] boolForKey:key]; }
- (NSInteger)integerForKey:(NSString *)key { return [[self defaults] integerForKey:key]; }
- (float)floatForKey:(NSString *)key { return [[self defaults] floatForKey:key]; }
- (NSString *)stringForKey:(NSString *)key { return [[self defaults] stringForKey:key]; }

- (void)setBool:(BOOL)v forKey:(NSString *)key        { [[self defaults] setBool:v forKey:key]; [self synchronize]; }
- (void)setInteger:(NSInteger)v forKey:(NSString *)key { [[self defaults] setInteger:v forKey:key]; [self synchronize]; }
- (void)setFloat:(float)v forKey:(NSString *)key       { [[self defaults] setFloat:v forKey:key]; [self synchronize]; }
- (void)setString:(NSString *)v forKey:(NSString *)key { [[self defaults] setObject:v forKey:key]; [self synchronize]; }

- (void)synchronize {
    // NSUserDefaults is async; force a flush so settings changed from the
    // YouTube UI are visible to the player overlay immediately.
    [[self defaults] synchronize];
}

- (void)resetAll {
    // Only wipe keys we own. Iterating over `dictionaryRepresentation`
    // would also nuke YouTube's own prefs - never do that.
    NSArray *keys = @[
        kB2YEnabledKey, kB2YAutoMatchKey, kB2YManualBVIDKey, kB2YTimeOffsetKey,
        kB2YOpacityKey, kB2YFontSizeKey, kB2YScrollSpeedKey, kB2YTrackSpacingKey,
        kB2YDisplayAreaKey, kB2YWeightThresholdKey, kB2YFilterColorKey,
        kB2YFilterLowWeightKey, kB2YShowDebugLogKey, kB2YCookieSESSDATAKey,
        kB2YMatchThresholdKey, kB2YMaxDanmakuKey
    ];
    for (NSString *key in keys) {
        [[self defaults] removeObjectForKey:key];
    }
    [self synchronize];
    [self registerDefaults];
}

- (NSString *)bilibiliCookieHeader {
    NSString *sessdata = [self stringForKey:kB2YCookieSESSDATAKey];
    if (sessdata.length == 0) return @"";
    return [NSString stringWithFormat:@"SESSDATA=%@", sessdata];
}

@end
