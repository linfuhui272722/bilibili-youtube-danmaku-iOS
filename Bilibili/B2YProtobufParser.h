//
//  B2YProtobufParser.h
//  B2YDanmaku
//
//  Minimal protobuf wire-format parser for Bilibili's danmaku segment
//  response (DmSegMobileReply).
//
//  The segment endpoint returns a raw protobuf body (NOT JSON), whose
//  schema is:
//
//  message DmSegMobileReply {
//      repeated DanmakuElem elems = 1;
//  }
//  message DanmakuElem {
//      int64  id        = 1;
//      int32  progress  = 2;   // milliseconds from video start
//      int32  mode      = 3;   // 1=scroll, 4=bottom, 5=top, 7=advanced, ...
//      int32  fontsize  = 4;
//      uint32 color     = 5;   // 0xRRGGBB
//      string midHash   = 6;
//      string content   = 7;
//      int64  ctime      = 8;
//      int32  weight    = 9;
//      string idStr      = 10;
//      int32  attr       = 11;
//      string action    = 12;
//  }
//
//  We only need: progress, mode, fontsize, color, content, weight.
//  Everything else is ignored to keep the parser small.
//

#import <Foundation/Foundation.h>

@class B2YDanmaku;

NS_ASSUME_NONNULL_BEGIN

@interface B2YProtobufParser : NSObject

// Parse a DmSegMobileReply protobuf body into an array of B2YDanmaku.
// Returns an empty array on malformed input (best-effort, like the JS
// version which swallows per-field errors).
- (NSArray<B2YDanmaku *> *)parseDanmakuSegment:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
