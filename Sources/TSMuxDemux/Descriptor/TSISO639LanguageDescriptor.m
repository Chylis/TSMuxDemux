//
//  TSISO639LanguageDescriptor.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2025-03-23.
//  Copyright © 2025 Magnus Makes Software. All rights reserved.
//

#import "TSISO639LanguageDescriptor.h"
#import "../TSBitReader.h"
#import "../TSFourCharCodeUtil.h"
#import "../TSLog.h"

@interface TSISO639LanguageDescriptorEntry()
-(instancetype)initWithLanguageCode:(NSData* _Nonnull)languageCode
                          audioType:(uint8_t)audioType;
@end

@implementation TSISO639LanguageDescriptorEntry
-(instancetype)initWithLanguageCode:(NSData* _Nonnull)languageCode
                          audioType:(uint8_t)audioType
{
    self = [super init];
    if (self) {
        _audioType = audioType;
        _languageCode = [TSISO639LanguageDescriptorEntry languageCodeStringFromData:languageCode];
        
    }
    return self;
}

-(BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[TSISO639LanguageDescriptorEntry class]]) {
        return NO;
    }
    TSISO639LanguageDescriptorEntry *other = (TSISO639LanguageDescriptorEntry*)object;
    if (self.audioType != other.audioType) {
        return NO;
    }
    if (self.languageCode != other.languageCode &&
        ![self.languageCode isEqualToString:other.languageCode]) {
        return NO;
    }
    return YES;
}

-(NSUInteger)hash
{
    return self.audioType ^ self.languageCode.hash;
}

-(NSString*)description
{
    return [NSString stringWithFormat:@"%@ (%@)",
            self.languageCode,
            [TSISO639LanguageDescriptorEntry audioTypeDescription:self.audioType]
    ];
}

+(NSString*)languageCodeStringFromData:(NSData *)languageCode
{
    if (languageCode.length != 3) {
        return @"???";
    }
    return [[NSString alloc] initWithData:languageCode
                                 encoding:NSISOLatin1StringEncoding];
}

+(NSString*)audioTypeDescription:(uint8_t)at
{
    switch ((TSISO639LanguageDescriptorAudioType)at) {
        case TSISO639LanguageDescriptorAudioTypeUndefined:
            return @"Undefined";
        case TSISO639LanguageDescriptorAudioTypeCleanEffects:
            return @"Clean effects";
        case TSISO639LanguageDescriptorAudioTypeHearingImpaired:
            return @"Hearing imparied";
        case TSISO639LanguageDescriptorAudioTypeVisualImpairedCommentary:
            return @"Visual imparied commentary";
        case TSISO639LanguageDescriptorAudioTypePrimary:
            return @"Primary";
        case TSISO639LanguageDescriptorAudioTypeNative:
            return @"Native";
        case TSISO639LanguageDescriptorAudioTypeEmergency:
            return @"Emergency";
        case TSISO639LanguageDescriptorAudioTypePrimaryCommentary:
            return @"Primary commentary";
        case TSISO639LanguageDescriptorAudioTypeAlternateCommentary:
            return @"Alternate commentary";
    }
    if (at >= 4 && at <= 127) {
        return [NSString stringWithFormat:@"User private (%u)", at];
    }
    // 133 - 255:
    return [NSString stringWithFormat:@"Reserved (%u)", at];
}

@end

@implementation TSISO639LanguageDescriptor

-(instancetype _Nonnull)initWithTag:(uint8_t)tag
                            payload:(NSData* _Nonnull)payload
                             length:(NSUInteger)length
{
    self = [super initWithTag:tag length:length];
    if (self) {
        if (payload.length && length > 0) {
            // Use the smaller of declared length and actual payload length
            NSUInteger effectiveLength = MIN(length, payload.length);

            if (effectiveLength >= 4) {
                TSBitReader reader = TSBitReaderMakeWithBytes(payload.bytes, effectiveLength);
                NSMutableArray *entries = [NSMutableArray arrayWithCapacity:effectiveLength / 4];

                // Each entry requires 4 bytes (language code: 3 + audio type: 1)
                while (TSBitReaderRemainingBytes(&reader) >= 4) {
                    NSData *langCode = TSBitReaderReadData(&reader, 3);
                    uint8_t audioType = TSBitReaderReadUInt8(&reader);

                    if (reader.error) {
                        TSLogWarn(@"ISO639LanguageDescriptor read error while parsing entry");
                        break;
                    }

                    TSISO639LanguageDescriptorEntry *e = [[TSISO639LanguageDescriptorEntry alloc]
                                                          initWithLanguageCode:langCode
                                                          audioType:audioType];
                    [entries addObject:e];
                }
                NSUInteger remaining = TSBitReaderRemainingBytes(&reader);
                if (remaining > 0 && remaining < 4) {
                    TSLogWarn(@"ISO639LanguageDescriptor has %lu trailing bytes (incomplete entry)",
                              (unsigned long)remaining);
                }
                _entries = entries;
            } else {
                TSLogWarn(@"ISO639LanguageDescriptor too short: %lu bytes (need at least 4)",
                          (unsigned long)effectiveLength);
                _entries = @[];
            }
        } else {
            TSLogWarn(@"Received ISO639LanguageDescriptor with no payload");
            _entries = @[];
        }
    }

    return self;
}

-(BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    if ([self class] != [object class]) {
        return NO;
    }
    if (![super isEqual:object]) {
        return NO;
    }
    TSISO639LanguageDescriptor *other = (TSISO639LanguageDescriptor*)object;
    if (self.entries.count != other.entries.count) {
        return NO;
    }
    for (NSUInteger i = 0; i < self.entries.count; ++i) {
        if (![self.entries[i] isEqual:other.entries[i]]) {
            return NO;
        }
    }
    return YES;
}

-(NSUInteger)hash
{
    NSUInteger entriesHash = 0;
    for (TSISO639LanguageDescriptorEntry *e in self.entries) {
        entriesHash ^= e.hash;
    }
    return [super hash] ^ entriesHash;
}

-(NSString*)description
{
    return [self tagDescription];
}
-(NSString*)tagDescription
{
    NSMutableString *formattedEntries = [NSMutableString
                                         stringWithFormat:@"%@",
                                         self.entries.count > 0 ? @"" : @"[]"];

    BOOL first = YES;
    for (TSISO639LanguageDescriptorEntry *e in self.entries) {
        if (!first) {
            [formattedEntries appendString:@", "];
        }
        [formattedEntries appendString:[e description]];
        first = NO;
    }

    return [NSString stringWithFormat:@"ISO-639 language: %@", formattedEntries];
}

@end
