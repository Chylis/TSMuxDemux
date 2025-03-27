//
//  TSISO639LanguageDescriptor.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2025-03-23.
//  Copyright © 2025 Magnus Makes Software. All rights reserved.
//

#import "TSISO639LanguageDescriptor.h"
#import "../TSFourCharCodeUtil.h"

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
            NSUInteger offset = 0;
            NSUInteger remainingLength = length;
            
            if (remainingLength > 0) {
                NSMutableArray *entries = [NSMutableArray arrayWithCapacity:remainingLength / 4];
                
                while (remainingLength > 0) {
                    NSData *langCode = [payload subdataWithRange:NSMakeRange(offset, 3)];
                    offset+=3;
                    remainingLength-=3;
                    
                    uint8_t audioType = 0;
                    [payload getBytes:&audioType range:NSMakeRange(offset, 1)];
                    offset++;
                    remainingLength--;
                    
                    TSISO639LanguageDescriptorEntry *e = [[TSISO639LanguageDescriptorEntry alloc]
                                                          initWithLanguageCode:langCode
                                                          audioType:audioType];
                    [entries addObject:e];
                }
                _entries = entries;
            }
        } else {
            NSLog(@"Received ISO639LanguageDescriptor with no payload");
        }
    }
    
    return self;
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
