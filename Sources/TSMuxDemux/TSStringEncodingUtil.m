//
//  TSStringEncodingUtil.m
//  TSMuxDemux
//

#import "TSStringEncodingUtil.h"
#import <CoreFoundation/CoreFoundation.h>

@implementation TSStringEncodingUtil

+(NSString*)dvbStringFromCharData:(NSData*)data
{
    NSUInteger payloadOffset = 0;
    NSNumber *encodingWrapper = [self dvbStringEncoding:data ioOffset:&payloadOffset];
    NSStringEncoding encoding = encodingWrapper ? [encodingWrapper unsignedIntegerValue] : NSUTF8StringEncoding;
    if (!encodingWrapper) payloadOffset = 0;
    return [[NSString alloc] initWithData:[NSData dataWithBytes:data.bytes + payloadOffset
                                                         length:data.length - payloadOffset]
                                 encoding:encoding];
}


+(NSNumber* _Nullable)dvbStringEncoding:(NSData * _Nullable)data
                               ioOffset:(NSUInteger*)ioOffset
{
    if (!data || data.length == 0) {
        return nil;
    }
    
    *ioOffset += 1;

    const unsigned char *bytes = [data bytes];
    uint8_t firstByte = bytes[0];
    switch (firstByte) {
        case 0x01:// ISO/IEC 8859-5
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatinCyrillic));
        case 0x02:// ISO/IEC 8859-6
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatinArabic));
        case 0x03:// ISO/IEC 8859-7
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatinGreek));
        case 0x04:// ISO/IEC 8859-8
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatinHebrew));
        case 0x05:// ISO/IEC 8859-9
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin5));
        case 0x06:// ISO/IEC 8859-10
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin6));
        case 0x07:// ISO/IEC 8859-11
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatinThai));
        case 0x08: // Reserved for future use
            return nil;
        case 0x09:// ISO/IEC 8859-13
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin7));
        case 0x0A:// ISO/IEC 8859-14
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin8));
        case 0x0B:// ISO/IEC 8859-15
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin9));
        // 0x0C - 0x0F - reserved for future use
        case 0x10:
            return [self dynamicallySelectedPartISOIEC8859:data ioOffset:ioOffset];
        case 0x11: // ISO/IEC 10646
            return @(NSUTF16StringEncoding);
        case 0x12: // KS X 1001-2014
            // kCFStringEncodingEUC_KR represents the EUC-KR encoding based on KS X 1001.
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingEUC_KR));
        case 0x13: // GB-2312-1980
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_2312_80));
        case 0x14: // Big5 subset of ISO/IEC 10646
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingBig5));
        case 0x15: // UTF-8 encoding of ISO/IEC 10646
            return @(NSUTF8StringEncoding);
        
        default:
            return nil;
    }
    
}

// Table A.4: Character Coding Tables for first byte 0x10
+ (NSNumber * _Nullable)dynamicallySelectedPartISOIEC8859:(NSData * _Nullable)data
                                                 ioOffset:(NSUInteger*)ioOffset
{
    if (!data || data.length < 3) {
        return nil;
    }
    
    uint16_t bytes2And3 = 0x0;
    [data getBytes:&bytes2And3 range:NSMakeRange(1, 2)];
    uint16_t encodingID = CFSwapInt16BigToHost(bytes2And3);
    
    *ioOffset += 2;
    
    switch (encodingID) {
        // 0x0000, 0x0001, 0x0002 --> ISO/IEC 8859-2 (East European)
        case 0x0000: // Reserved
            return nil;
        case 0x0001: // ISO/IEC 8859-1
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin1));
        case 0x0002: // ISO/IEC 8859-2
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin2));
        case 0x0003: // ISO/IEC 8859-3
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin3));
        case 0x0004: // ISO/IEC 8859-4
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin4));
        case 0x0005: // ISO/IEC 8859-5
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatinCyrillic));
        case 0x0006: // ISO/IEC 8859-6
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatinArabic));
        case 0x0007: // ISO/IEC 8859-7
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatinGreek));
        case 0x0008: // ISO/IEC 8859-8
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatinHebrew));
        case 0x0009: // ISO/IEC 8859-9
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin5));
        case 0x000A: // ISO/IEC 8859-10
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin6));
        case 0x000B: // ISO/IEC 8859-11
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatinThai));
        case 0x000C: // reserved
            return nil;
        case 0x000D: // ISO/IEC 8859-13
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin7));
        case 0x000E: // ISO/IEC 8859-14
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin8));
        case 0x000F: // ISO/IEC 8859-15
            return @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin9));
        default:
            // Other values (including reserved ones) are not supported
            return nil;
    }
}

@end
