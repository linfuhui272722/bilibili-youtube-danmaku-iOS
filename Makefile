# B2YDanmaku - Theos Makefile
# Builds a MobileSubstrate tweak for the YouTube iOS app.
#
# Build targets:
#   make package            -> builds .deb
#   make package ROOTLESS=1 -> rootless .deb (Sileo on Dopamine/palera1n)
#   make package ROOTHIDE=1 -> roothide .deb (RootHide jailbreaks)

ifeq ($(ROOTLESS),1)
THEOS_PACKAGE_SCHEME = rootless
else ifeq ($(ROOTHIDE),1)
THEOS_PACKAGE_SCHEME = roothide
endif

DEBUG = 0
FINALPACKAGE = 1
ARCHS = arm64 arm64e

# Tweak version - bump on each release
PACKAGE_VERSION = 1.0.0

# Target: iPhoneOS SDK, deployment target 14.0 (arm64e requires >= 14.0).
# SDK version can be overridden via B2Y_SDK_VER (set by codemagic.yaml).
B2Y_SDK_VER ?= 16.5
TARGET := iphone:clang:$(B2Y_SDK_VER):14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = B2YDanmaku

$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation Security CoreGraphics
$(TWEAK_NAME)_WEAK_FRAMEWORKS = WebKit
# -fobjc-arc: enable ARC
# -I.: add project root to header search path
# -IUtils -IBilibili -IEngine: add subdirectories so #import "B2YFoo.h"
#   resolves regardless of which subfolder the .h lives in.
$(TWEAK_NAME)_CFLAGS = -fobjc-arc \
    -DTWEAK_VERSION=\"$(PACKAGE_VERSION)\" \
    -I. -IUtils -IBilibili -IEngine \
    -Wno-deprecated-declarations \
    -Wno-unused-variable \
    -Wno-unused-function \
    -Wno-incompatible-pointer-types-discards-qualifiers
$(TWEAK_NAME)_LDFLAGS = -framework UIKit -framework Foundation

# Source files: Logos (.x) files + Objective-C (.m) files
$(TWEAK_NAME)_FILES = \
    B2YDanmaku.x \
    Settings.x \
    Bilibili/B2YWBIKeys.m \
    Bilibili/B2YDanmakuAPI.m \
    Bilibili/B2YProtobufParser.m \
    Bilibili/B2YDanmakuModel.m \
    Engine/B2YDanmakuEngine.m \
    Engine/B2YDanmakuOverlayView.m \
    Utils/B2YSettings.m \
    Utils/B2YMD5.m \
    Utils/B2YVideoMatcher.m

include $(THEOS_MAKE_PATH)/tweak.mk
