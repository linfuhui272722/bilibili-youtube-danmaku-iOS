//
//  B2YDanmaku.h
//  B2YDanmaku
//
//  Central header imported by every Logos (.x) and Obj-C (.m) file.
//  Imports all B2Y modules so cross-file references resolve without a
//  separate PCH.
//
//  YouTube private class declarations live in B2YDanmaku.x and Settings.x
//  (next to the hooks that use them) to avoid duplicate-declaration errors.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

#import "B2YSettings.h"
#import "B2YMD5.h"
#import "B2YVideoMatcher.h"
#import "B2YWBIKeys.h"
#import "B2YDanmakuAPI.h"
#import "B2YProtobufParser.h"
#import "B2YDanmakuModel.h"
#import "B2YDanmakuEngine.h"
#import "B2YDanmakuOverlayView.h"

// Tweak version injected from the Makefile (-DTWEAK_VERSION=...)
#ifndef TWEAK_VERSION
#define TWEAK_VERSION "1.0.0"
#endif

// Stringify the version macro so it can be used in NSString literals.
#define B2Y_VERSION @TWEAK_VERSION

// Convenience macros for reading/writing tweak preferences.
#define b2yBool(key)   [[B2YSettings shared] boolForKey:(key)]
#define b2yInt(key)    [[B2YSettings shared] integerForKey:(key)]
#define b2yFloat(key)  [[B2YSettings shared] floatForKey:(key)]
#define b2yString(key) [[B2YSettings shared] stringForKey:(key)]

#define b2ySetBool(v, k)   [[B2YSettings shared] setBool:(v) forKey:(k)]
#define b2ySetInt(v, k)    [[B2YSettings shared] setInteger:(v) forKey:(k)]
#define b2ySetFloat(v, k)  [[B2YSettings shared] setFloat:(v) forKey:(k)]
#define b2ySetString(v, k) [[B2YSettings shared] setString:(v) forKey:(k)]
