//
//  Settings.x
//
//  Settings panel injected into YouTube's own settings view controller.
//  Mirrors the structure used by YTLite so users get a familiar UI.
//
//  We hook YTSettingsViewController's section-building method to
//  append a "B2Y Danmaku" group with toggles, sliders, and a text field
//  for the manual BV id.
//

#import "B2YDanmaku.h"

// ---- YouTube settings class interfaces ----
// Forward-declared here; YouTube's own headers are not available at build
// time, so we declare only the surface we use. These declarations are
// local to this translation unit, so they don't collide with B2YDanmaku.x.

@interface YTSettingsCellData : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *itemSubtitle;
@property (nonatomic, assign) BOOL switchVisible;
@property (nonatomic, assign) BOOL switchOn;
@property (nonatomic, copy) NSString *switchKey;
@property (nonatomic, assign) BOOL hasSwitch;
@property (nonatomic, strong) UIImage *icon;
@property (nonatomic, copy) void (^selectBlock)(YTSettingsCellData *);
@end

@interface YTSettingsViewController : UIViewController
- (void)setSectionItems:(NSArray *)items forCategory:(NSInteger)category title:(NSString *)title titleDescription:(NSString *)desc headerHidden:(BOOL)hidden;
- (void)pushViewController:(UIViewController *)vc;
@end

// ---- Section identifier ----
// A category ID unlikely to collide with YouTube's own. 0xB2D0 is a valid
// hex literal (the previous 0xB2Y0 was not - 'Y' isn't a hex digit).
static const NSInteger kB2YCategoryID = 0xB2D0;

// ---- Helper: build a switch cell ----

static YTSettingsCellData *b2y_switch(NSString *title, NSString *key) {
    YTSettingsCellData *data = [[%c(YTSettingsCellData) alloc] init];
    data.title = title;
    data.hasSwitch = YES;
    data.switchVisible = YES;
    data.switchOn = b2yBool(key);
    data.switchKey = key;

    // Hook the switch toggle via KVO on `switchOn`.
    __weak typeof(data) weakData = data;
    data.selectBlock = ^(YTSettingsCellData *cell) {
        BOOL newVal = !b2yBool(key);
        b2ySetBool(newVal, key);
        weakData.switchOn = newVal;
    };
    return data;
}

// ---- Helper: present a text-input alert ----

static void b2y_present_text_input(UIViewController *presenter,
                                   NSString *title,
                                   NSString *message,
                                   NSString *placeholder,
                                   NSString *currentValue,
                                   void (^completion)(NSString *input)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = placeholder;
        tf.text = currentValue;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *input = alert.textFields.firstObject.text;
        completion(input);
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

// ===========================================================================
//  Hook YTSettingsViewController to add our section
// ===========================================================================

%hook YTSettingsViewController

- (void)setSectionItems:(NSArray *)items
            forCategory:(NSInteger)category
                  title:(NSString *)title
        titleDescription:(NSString *)desc
            headerHidden:(BOOL)hidden {
    // We only inject into the root settings category (category 0).
    if (category != 0) {
        %orig;
        return;
    }

    NSMutableArray *newItems = [items mutableCopy];

    // ---- Build our section ----
    NSMutableArray *b2yItems = [NSMutableArray array];

    // Header cell (non-interactive).
    YTSettingsCellData *header = [[%c(YTSettingsCellData) alloc] init];
    header.title = @"B2Y Danmaku";
    header.itemSubtitle = [NSString stringWithFormat:@"Sync Bilibili danmaku onto YouTube. v%@", B2Y_VERSION];
    header.hasSwitch = NO;
    [b2yItems addObject:header];

    // Master enable toggle.
    [b2yItems addObject:b2y_switch(@"Enable Danmaku", kB2YEnabledKey)];

    // Auto-match toggle.
    [b2yItems addObject:b2y_switch(@"Auto-match by Title", kB2YAutoMatchKey)];

    // Manual BV id (text input).
    YTSettingsCellData *bvidCell = [[%c(YTSettingsCellData) alloc] init];
    bvidCell.title = @"Manual BV ID";
    NSString *currentBVID = b2yString(kB2YManualBVIDKey);
    bvidCell.itemSubtitle = currentBVID.length > 0 ? currentBVID : @"(not set)";
    bvidCell.hasSwitch = NO;
    __weak typeof(self) weakSelf = self;
    bvidCell.selectBlock = ^(YTSettingsCellData *cell) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        b2y_present_text_input(strongSelf,
                              @"Bilibili BV ID",
                              @"Enter the BV id (e.g. BV1xx411c7mD)",
                              @"BV1xxxxxxxxx",
                              b2yString(kB2YManualBVIDKey),
                              ^(NSString *input) {
            b2ySetString(input ?: @"", kB2YManualBVIDKey);
            cell.itemSubtitle = input.length > 0 ? input : @"(not set)";
        });
    };
    [b2yItems addObject:bvidCell];

    // SESSDATA cookie (for logged-in search).
    YTSettingsCellData *sessCell = [[%c(YTSettingsCellData) alloc] init];
    sessCell.title = @"Bilibili SESSDATA";
    NSString *currentSess = b2yString(kB2YCookieSESSDATAKey);
    sessCell.itemSubtitle = currentSess.length > 0 ? @"(set)" : @"(not set - anonymous)";
    sessCell.hasSwitch = NO;
    sessCell.selectBlock = ^(YTSettingsCellData *cell) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        b2y_present_text_input(strongSelf,
                              @"Bilibili SESSDATA Cookie",
                              @"Paste your SESSDATA cookie value for logged-in search (optional)",
                              @"xxxxxxxxxxxxxxxx",
                              b2yString(kB2YCookieSESSDATAKey),
                              ^(NSString *input) {
            b2ySetString(input ?: @"", kB2YCookieSESSDATAKey);
            cell.itemSubtitle = input.length > 0 ? @"(set)" : @"(not set - anonymous)";
        });
    };
    [b2yItems addObject:sessCell];

    // Match threshold (slider via picker).
    YTSettingsCellData *threshCell = [[%c(YTSettingsCellData) alloc] init];
    threshCell.title = @"Match Threshold";
    NSInteger thresh = b2yInt(kB2YMatchThresholdKey);
    if (thresh <= 0) thresh = 60;
    threshCell.itemSubtitle = [NSString stringWithFormat:@"%ld%% (title similarity)", (long)thresh];
    threshCell.hasSwitch = NO;
    threshCell.selectBlock = ^(YTSettingsCellData *cell) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Match Threshold"
                                                                       message:@"Minimum title similarity to accept a Bilibili match"
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSInteger v = 40; v <= 95; v += 5) {
            NSString *label = [NSString stringWithFormat:@"%ld%%", (long)v];
            UIAlertAction *a = [UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                b2ySetInt(v, kB2YMatchThresholdKey);
                cell.itemSubtitle = [NSString stringWithFormat:@"%ld%%", (long)v];
            }];
            [picker addAction:a];
        }
        [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [strongSelf presentViewController:picker animated:YES completion:nil];
    };
    [b2yItems addObject:threshCell];

    // Display area.
    YTSettingsCellData *areaCell = [[%c(YTSettingsCellData) alloc] init];
    areaCell.title = @"Display Area";
    NSInteger area = (NSInteger)b2yFloat(kB2YDisplayAreaKey);
    if (area <= 0) area = 75;
    areaCell.itemSubtitle = [NSString stringWithFormat:@"%ld%% of screen height", (long)area];
    areaCell.hasSwitch = NO;
    areaCell.selectBlock = ^(YTSettingsCellData *cell) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Display Area"
                                                                       message:@"Vertical portion of the player covered by danmaku"
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSInteger v = 25; v <= 100; v += 25) {
            NSString *label = [NSString stringWithFormat:@"%ld%%", (long)v];
            UIAlertAction *a = [UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                b2ySetFloat((float)v, kB2YDisplayAreaKey);
                cell.itemSubtitle = [NSString stringWithFormat:@"%ld%% of screen height", (long)v];
            }];
            [picker addAction:a];
        }
        [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [strongSelf presentViewController:picker animated:YES completion:nil];
    };
    [b2yItems addObject:areaCell];

    // Font size.
    YTSettingsCellData *fontCell = [[%c(YTSettingsCellData) alloc] init];
    fontCell.title = @"Font Size";
    NSInteger fontSize = (NSInteger)b2yFloat(kB2YFontSizeKey);
    if (fontSize <= 0) fontSize = 18;
    fontCell.itemSubtitle = [NSString stringWithFormat:@"%ldpt", (long)fontSize];
    fontCell.hasSwitch = NO;
    fontCell.selectBlock = ^(YTSettingsCellData *cell) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Font Size"
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSInteger v = 12; v <= 32; v += 2) {
            NSString *label = [NSString stringWithFormat:@"%ldpt", (long)v];
            UIAlertAction *a = [UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                b2ySetFloat((float)v, kB2YFontSizeKey);
                cell.itemSubtitle = [NSString stringWithFormat:@"%ldpt", (long)v];
            }];
            [picker addAction:a];
        }
        [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [strongSelf presentViewController:picker animated:YES completion:nil];
    };
    [b2yItems addObject:fontCell];

    // Opacity (stored as 0-100 in settings).
    YTSettingsCellData *opacityCell = [[%c(YTSettingsCellData) alloc] init];
    opacityCell.title = @"Opacity";
    NSInteger opacity = (NSInteger)b2yFloat(kB2YOpacityKey);
    if (opacity <= 0) opacity = 100;
    opacityCell.itemSubtitle = [NSString stringWithFormat:@"%ld%%", (long)opacity];
    opacityCell.hasSwitch = NO;
    opacityCell.selectBlock = ^(YTSettingsCellData *cell) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Opacity"
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSInteger v = 20; v <= 100; v += 10) {
            NSString *label = [NSString stringWithFormat:@"%ld%%", (long)v];
            UIAlertAction *a = [UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                b2ySetFloat((float)v, kB2YOpacityKey);
                cell.itemSubtitle = [NSString stringWithFormat:@"%ld%%", (long)v];
            }];
            [picker addAction:a];
        }
        [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [strongSelf presentViewController:picker animated:YES completion:nil];
    };
    [b2yItems addObject:opacityCell];

    // Scroll speed (multiplier: 1.0 = normal).
    YTSettingsCellData *speedCell = [[%c(YTSettingsCellData) alloc] init];
    speedCell.title = @"Scroll Speed";
    CGFloat speedMult = b2yFloat(kB2YScrollSpeedKey);
    if (speedMult <= 0) speedMult = 1.0;
    speedCell.itemSubtitle = [NSString stringWithFormat:@"%.1fx", speedMult];
    speedCell.hasSwitch = NO;
    speedCell.selectBlock = ^(YTSettingsCellData *cell) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Scroll Speed"
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray<NSNumber *> *multipliers = @[@0.5, @0.75, @1.0, @1.25, @1.5, @2.0];
        for (NSNumber *mult in multipliers) {
            NSString *label = [NSString stringWithFormat:@"%.2fx", mult.doubleValue];
            UIAlertAction *a = [UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                b2ySetFloat((float)mult.doubleValue, kB2YScrollSpeedKey);
                cell.itemSubtitle = [NSString stringWithFormat:@"%.2fx", mult.doubleValue];
            }];
            [picker addAction:a];
        }
        [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [strongSelf presentViewController:picker animated:YES completion:nil];
    };
    [b2yItems addObject:speedCell];

    // Filter low-weight danmaku.
    [b2yItems addObject:b2y_switch(@"Filter Low-Weight Danmaku", kB2YFilterLowWeightKey)];

    // Reset.
    YTSettingsCellData *resetCell = [[%c(YTSettingsCellData) alloc] init];
    resetCell.title = @"Reset All Settings";
    resetCell.hasSwitch = NO;
    resetCell.selectBlock = ^(YTSettingsCellData *cell) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Reset"
                                                                         message:@"Reset all B2Y Danmaku settings to defaults?"
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
            [[B2YSettings shared] resetAll];
        }]];
        [strongSelf presentViewController:confirm animated:YES completion:nil];
    };
    [b2yItems addObject:resetCell];

    // Append our items to the root list.
    [newItems addObjectsFromArray:b2yItems];

    // Re-call with the augmented list. We pass a sentinel category so we
    // don't recurse infinitely.
    %orig(newItems, category, title, desc, hidden);
}

%end
