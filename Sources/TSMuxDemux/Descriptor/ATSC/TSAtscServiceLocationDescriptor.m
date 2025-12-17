//
//  TSAtscServiceLocationDescriptor.m
//  TSMuxDemux
//
//  ATSC A/65 Service Location Descriptor (tag 0xA1)
//

#import "TSAtscServiceLocationDescriptor.h"

#pragma mark - TSAtscServiceLocationElement

@implementation TSAtscServiceLocationElement

-(instancetype)initWithStreamType:(uint8_t)streamType
                    elementaryPid:(uint16_t)elementaryPid
                     languageCode:(NSString *)languageCode
{
    self = [super init];
    if (self) {
        _streamType = streamType;
        _elementaryPid = elementaryPid;
        _languageCode = languageCode ?: @"";
    }
    return self;
}

-(BOOL)isEqual:(id)object
{
    if (self == object) return YES;
    if (![object isKindOfClass:[TSAtscServiceLocationElement class]]) return NO;
    TSAtscServiceLocationElement *other = (TSAtscServiceLocationElement *)object;
    return self.streamType == other.streamType
        && self.elementaryPid == other.elementaryPid
        && [self.languageCode isEqualToString:other.languageCode];
}

-(NSUInteger)hash
{
    return self.elementaryPid ^ (self.streamType << 16);
}

-(NSString *)description
{
    return [NSString stringWithFormat:@"{ pid: %u, type: 0x%02X, lang: %@ }",
            self.elementaryPid, self.streamType, self.languageCode];
}

@end

#pragma mark - TSAtscServiceLocationDescriptor

@implementation TSAtscServiceLocationDescriptor

-(instancetype _Nonnull)initWithTag:(uint8_t)tag
                            payload:(NSData *)payload
                             length:(NSUInteger)length
{
    self = [super initWithTag:tag length:length];
    if (self) {
        if (!payload || payload.length < 3) {
            _pcrPid = 0x1FFF; // Invalid/null PID
            _elements = @[];
            return self;
        }

        const uint8_t *bytes = payload.bytes;
        NSUInteger payloadLength = payload.length;
        NSUInteger offset = 0;

        // PCR_PID: 3 bits reserved + 13 bits PID
        _pcrPid = (((uint16_t)bytes[offset] & 0x1F) << 8) | bytes[offset + 1];
        offset += 2;

        // number_elements: 8 bits
        uint8_t numElements = bytes[offset];
        offset += 1;

        NSMutableArray<TSAtscServiceLocationElement*> *elements = [NSMutableArray arrayWithCapacity:numElements];

        for (uint8_t i = 0; i < numElements; i++) {
            // Each element is 6 bytes: stream_type(1) + PID(2) + language(3)
            if (offset + 6 > payloadLength) {
                break;
            }

            uint8_t streamType = bytes[offset];
            offset += 1;

            uint16_t elementaryPid = (((uint16_t)bytes[offset] & 0x1F) << 8) | bytes[offset + 1];
            offset += 2;

            // ISO 639 language code (3 ASCII bytes)
            NSString *langCode = [[NSString alloc] initWithBytes:&bytes[offset]
                                                          length:3
                                                        encoding:NSASCIIStringEncoding] ?: @"";
            // Trim null bytes (language may be 0x00 0x00 0x00 if not specified)
            langCode = [langCode stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\0"]];
            offset += 3;

            TSAtscServiceLocationElement *element = [[TSAtscServiceLocationElement alloc]
                                                     initWithStreamType:streamType
                                                     elementaryPid:elementaryPid
                                                     languageCode:langCode];
            [elements addObject:element];
        }

        _elements = [elements copy];
    }
    return self;
}

-(BOOL)isEqual:(id)object
{
    if (self == object) return YES;
    if (![object isKindOfClass:[TSAtscServiceLocationDescriptor class]]) return NO;
    TSAtscServiceLocationDescriptor *other = (TSAtscServiceLocationDescriptor *)object;
    return self.descriptorTag == other.descriptorTag
        && self.pcrPid == other.pcrPid
        && [self.elements isEqualToArray:other.elements];
}

-(NSUInteger)hash
{
    return self.descriptorTag ^ (self.pcrPid << 8) ^ self.elements.count;
}

-(NSString *)description
{
    return [NSString stringWithFormat:@"ServiceLocation { pcrPid: %u, elements: %@ }",
            self.pcrPid, self.elements];
}

@end
