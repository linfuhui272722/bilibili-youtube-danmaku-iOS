//
//  B2YProtobufParser.m
//
//  Hand-rolled protobuf reader. We deliberately avoid pulling in a
//  full protobuf runtime - the danmaku schema is tiny and stable, and
//  a 200-line parser keeps the tweak binary small.
//

#import "B2YProtobufParser.h"
#import "B2YDanmakuModel.h"

// Wire types.
static const uint32_t kWireTypeVarint  = 0;
static const uint32_t kWireTypeFixed64 = 1;
static const uint32_t kWireTypeLength  = 2;
static const uint32_t kWireTypeFixed32 = 5;

// A cursor over the raw bytes.
typedef struct {
    const uint8_t *bytes;
    NSUInteger length;
    NSUInteger offset;
} B2YCursor;

static BOOL cursorHasMore(B2YCursor *c) {
    return c->offset < c->length;
}

// Read a base-128 varint. Returns 0 on overflow (matches JS behaviour).
static uint64_t readVarint(B2YCursor *c) {
    uint64_t value = 0;
    int shift = 0;
    while (cursorHasMore(c)) {
        uint8_t b = c->bytes[c->offset++];
        value |= ((uint64_t)(b & 0x7F)) << shift;
        if ((b & 0x80) == 0) return value;
        shift += 7;
        if (shift >= 64) return 0; // overflow guard
    }
    return value;
}

// Read a length-delimited field body as an NSData slice (no copy).
static NSData *readLengthDelimited(B2YCursor *c) {
    uint64_t len = readVarint(c);
    if (len == 0 || c->offset + len > c->length) return nil;
    NSData *slice = [NSData dataWithBytesNoCopy:(void *)(c->bytes + c->offset)
                                         length:len
                                   freeWhenDone:NO];
    c->offset += len;
    return slice;
}

// Skip a field whose wire type we don't care about.
static void skipField(B2YCursor *c, uint32_t wireType) {
    switch (wireType) {
        case kWireTypeVarint:
            readVarint(c);
            break;
        case kWireTypeFixed64:
            c->offset += 8;
            break;
        case kWireTypeLength: {
            uint64_t len = readVarint(c);
            c->offset += len;
            break;
        }
        case kWireTypeFixed32:
            c->offset += 4;
            break;
        default:
            // Unknown wire type - we can't safely skip, bail out.
            c->offset = c->length;
            break;
    }
}

// Parse a single DanmakuElem from its length-delimited body.
static B2YDanmaku *parseDanmakuElem(NSData *body) {
    B2YDanmaku *d = [[B2YDanmaku alloc] init];
    B2YCursor c = {body.bytes, body.length, 0};

    while (cursorHasMore(&c)) {
        uint64_t tag = readVarint(&c);
        uint32_t fieldNumber = (uint32_t)(tag >> 3);
        uint32_t wireType = (uint32_t)(tag & 0x7);

        switch (fieldNumber) {
            case 2: { // progress (int32, varint) - milliseconds
                if (wireType != kWireTypeVarint) { skipField(&c, wireType); break; }
                uint64_t v = readVarint(&c);
                d.time = (NSTimeInterval)v / 1000.0;
                break;
            }
            case 3: { // mode (int32, varint)
                if (wireType != kWireTypeVarint) { skipField(&c, wireType); break; }
                d.mode = (B2YDanmakuMode)readVarint(&c);
                break;
            }
            case 4: { // fontsize (int32, varint)
                if (wireType != kWireTypeVarint) { skipField(&c, wireType); break; }
                d.fontsize = (NSInteger)readVarint(&c);
                break;
            }
            case 5: { // color (uint32, varint)
                if (wireType != kWireTypeVarint) { skipField(&c, wireType); break; }
                d.color = (uint32_t)readVarint(&c);
                break;
            }
            case 7: { // content (string, length-delimited)
                if (wireType != kWireTypeLength) { skipField(&c, wireType); break; }
                NSData *strBody = readLengthDelimited(&c);
                if (strBody) {
                    d.text = [[NSString alloc] initWithData:strBody
                                                encoding:NSUTF8StringEncoding];
                }
                break;
            }
            case 9: { // weight (int32, varint)
                if (wireType != kWireTypeVarint) { skipField(&c, wireType); break; }
                d.weight = (NSInteger)readVarint(&c);
                break;
            }
            default:
                skipField(&c, wireType);
                break;
        }
    }

    // Default color is white if absent.
    if (d.color == 0) d.color = 0xFFFFFF;
    // Default mode is scroll if absent.
    if (d.mode == 0) d.mode = B2YDanmakuModeScroll;

    return d;
}

@implementation B2YProtobufParser

- (NSArray<B2YDanmaku *> *)parseDanmakuSegment:(NSData *)data {
    if (!data.length) return @[];

    NSMutableArray<B2YDanmaku *> *result = [NSMutableArray array];
    B2YCursor c = {data.bytes, data.length, 0};

    while (cursorHasMore(&c)) {
        @try {
            uint64_t tag = readVarint(&c);
            uint32_t fieldNumber = (uint32_t)(tag >> 3);
            uint32_t wireType = (uint32_t)(tag & 0x7);

            if (fieldNumber == 1 && wireType == kWireTypeLength) {
                // elems field - parse the nested DanmakuElem.
                NSData *elemBody = readLengthDelimited(&c);
                if (!elemBody) break;
                B2YDanmaku *d = parseDanmakuElem(elemBody);

                // Validity check: must have non-empty content and a sane time.
                if (d.text.length > 0 && d.time >= 0) {
                    [result addObject:d];
                }
            } else {
                skipField(&c, wireType);
            }
        } @catch (NSException *e) {
            // Bail out on any parse error - return what we have so far.
            break;
        }
    }

    return result;
}

@end
