//
//  TSDvbComponentDescriptor.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2025-12-18.
//  Copyright © 2025 Magnus Makes Software. All rights reserved.
//
//  DVB Component Descriptor as defined in ETSI EN 300 468, section 6.2.8.
//  https://www.etsi.org/deliver/etsi_en/300400_300499/300468/

#import "TSDvbComponentDescriptor.h"

@implementation TSDvbComponentDescriptor

-(instancetype _Nonnull)initWithTag:(uint8_t)tag
                            payload:(NSData* _Nonnull)payload
                             length:(NSUInteger)length
{
    self = [super initWithTag:tag length:length];
    if (self) {
        if (!payload || payload.length < 6 || length < 6) {
            NSLog(@"DVB component descriptor too short: %lu bytes", (unsigned long)length);
            return self;
        }

        if (length != payload.length) {
            NSLog(@"DVB component descriptor length mismatch: declared %lu, payload %lu bytes",
                  (unsigned long)length, (unsigned long)payload.length);
        }

        const uint8_t *bytes = payload.bytes;
        NSUInteger offset = 0;

        // Byte 0: stream_content_ext (4 bits) + stream_content (4 bits)
        uint8_t byte0 = bytes[offset++];
        _streamContentExt = (byte0 >> 4) & 0x0F;
        _streamContent = byte0 & 0x0F;

        // Byte 1: component_type (8 bits)
        _componentType = bytes[offset++];

        // Byte 2: component_tag (8 bits)
        _componentTag = bytes[offset++];

        // Bytes 3-5: ISO_639_language_code (3 bytes)
        NSString *langCode = [[NSString alloc] initWithBytes:&bytes[offset]
                                                      length:3
                                                    encoding:NSASCIIStringEncoding];
        if (langCode) {
            langCode = [langCode stringByTrimmingCharactersInSet:
                        [NSCharacterSet characterSetWithCharactersInString:@"\0"]];
            // Set to nil if empty after trimming null characters
            _languageCode = langCode.length > 0 ? langCode : nil;
        }
        offset += 3;

        // Remaining bytes: text (variable length)
        NSUInteger textLength = length - offset;
        if (textLength > 0 && offset + textLength <= payload.length) {
            _text = [payload subdataWithRange:NSMakeRange(offset, textLength)];
        }
    }

    return self;
}

-(BOOL)isVideo
{
    // stream_content values for video per ETSI EN 300 468
    return _streamContent == 0x01  // MPEG-2 video
        || _streamContent == 0x05  // H.264/AVC video
        || _streamContent == 0x09; // HEVC video
}

-(BOOL)isAudio
{
    // stream_content values for audio per ETSI EN 300 468
    return _streamContent == 0x02  // MPEG-1 Layer 2 audio
        || _streamContent == 0x04  // AC-3 audio
        || _streamContent == 0x06; // HE-AAC audio
}

-(BOOL)isEqual:(id)object
{
    if (self == object) return YES;
    if (![object isKindOfClass:[TSDvbComponentDescriptor class]]) return NO;
    if (![super isEqual:object]) return NO;

    TSDvbComponentDescriptor *other = (TSDvbComponentDescriptor *)object;

    return self.streamContentExt == other.streamContentExt
        && self.streamContent == other.streamContent
        && self.componentType == other.componentType
        && self.componentTag == other.componentTag
        && (self.languageCode == other.languageCode || [self.languageCode isEqualToString:other.languageCode])
        && (self.text == other.text || [self.text isEqualToData:other.text]);
}

-(NSUInteger)hash
{
    return [super hash]
        ^ self.streamContent
        ^ self.componentType
        ^ self.componentTag;
}

-(NSString *)description
{
    return [self tagDescription];
}

-(NSString *)tagDescription
{
    NSString *contentDesc = [self streamContentDescription] ?: [NSString stringWithFormat:@"0x%02X", _streamContent];
    NSMutableString *desc = [NSMutableString stringWithFormat:@"Component: %@", contentDesc];

    NSString *typeDesc = [self componentTypeDescription];
    if (typeDesc) {
        [desc appendFormat:@" (%@)", typeDesc];
    } else {
        [desc appendFormat:@" type=0x%02X", _componentType];
    }

    [desc appendFormat:@" tag=%u", _componentTag];

    if (_streamContentExt != 0x0F) {
        [desc appendFormat:@" ext=0x%X", _streamContentExt];
    }
    if (_languageCode) {
        [desc appendFormat:@" lang=%@", _languageCode];
    }
    return desc;
}

/// Returns human-readable description of componentType based on streamContent.
/// Per ETSI EN 300 468 Table 26.
-(NSString *)componentTypeDescription
{
    switch (_streamContent) {
        case 0x01: // MPEG-2 video
            return [self mpeg2VideoComponentTypeDescription];
        case 0x05: // H.264/AVC video
            return [self avcVideoComponentTypeDescription];
        case 0x09: // HEVC video
            return [self hevcVideoComponentTypeDescription];
        default:
            return nil;
    }
}

-(NSString *)mpeg2VideoComponentTypeDescription
{
    switch (_componentType) {
        case 0x01: return @"4:3 SD 25Hz";
        case 0x02: return @"16:9 letterbox SD 25Hz";
        case 0x03: return @"16:9 SD 25Hz";
        case 0x04: return @">16:9 SD 25Hz";
        case 0x05: return @"4:3 SD 30Hz";
        case 0x06: return @"16:9 letterbox SD 30Hz";
        case 0x07: return @"16:9 SD 30Hz";
        case 0x08: return @">16:9 SD 30Hz";
        case 0x09: return @"4:3 HD 25Hz";
        case 0x0A: return @"16:9 letterbox HD 25Hz";
        case 0x0B: return @"16:9 HD 25Hz";
        case 0x0C: return @">16:9 HD 25Hz";
        case 0x0D: return @"4:3 HD 30Hz";
        case 0x0E: return @"16:9 letterbox HD 30Hz";
        case 0x0F: return @"16:9 HD 30Hz";
        case 0x10: return @">16:9 HD 30Hz";
        default: return nil;
    }
}

-(NSString *)avcVideoComponentTypeDescription
{
    switch (_componentType) {
        case 0x01: return @"4:3 SD 25Hz";
        case 0x03: return @"16:9 SD 25Hz";
        case 0x04: return @">16:9 SD 25Hz";
        case 0x05: return @"4:3 SD 30Hz";
        case 0x07: return @"16:9 SD 30Hz";
        case 0x08: return @">16:9 SD 30Hz";
        case 0x0B: return @"16:9 HD 25Hz";
        case 0x0C: return @">16:9 HD 25Hz";
        case 0x0F: return @"16:9 HD 30Hz";
        case 0x10: return @">16:9 HD 30Hz";
        case 0x80: return @"16:9 HD 25Hz 3D";
        case 0x81: return @"16:9 HD 30Hz 3D";
        case 0x82: return @">16:9 HD 25Hz 3D";
        case 0x83: return @">16:9 HD 30Hz 3D";
        case 0x84: return @"16:9 UHD 25Hz 2160p";
        case 0x85: return @"16:9 UHD 30Hz 2160p";
        default: return nil;
    }
}

-(NSString *)hevcVideoComponentTypeDescription
{
    switch (_componentType) {
        case 0x00: return @"HD 8-bit 60Hz";
        case 0x01: return @"HD 10-bit 60Hz";
        case 0x02: return @"UHD 8-bit 30Hz";
        case 0x03: return @"UHD 10-bit 60Hz";
        case 0x04: return @"UHD 10-bit 4:2:2 60Hz";
        case 0x05: return @"HD 10-bit HFR 120Hz";
        case 0x06: return @"UHD 10-bit HFR 120Hz";
        default: return nil;
    }
}

-(NSString *)streamContentDescription
{
    switch (_streamContent) {
        case 0x01: return @"MPEG-2 video";
        case 0x02: return @"MPEG-1 Layer 2 audio";
        case 0x03: return @"EBU teletext/subtitles";
        case 0x04: return @"AC-3 audio";
        case 0x05: return @"H.264/AVC video";
        case 0x06: return @"HE-AAC audio";
        case 0x07: return @"DTS audio";
        case 0x08: return @"DVB SRM data";
        case 0x09: return @"HEVC video";
        default: return nil;
    }
}

@end
