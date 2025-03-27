//
//  TSISO639LanguageDescriptor.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2025-03-23.
//  Copyright © 2025 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSDescriptor.h"

typedef NS_ENUM(uint8_t, TSISO639LanguageDescriptorAudioType) {
    TSISO639LanguageDescriptorAudioTypeUndefined                = 0x00,
    TSISO639LanguageDescriptorAudioTypeCleanEffects             = 0x01,
    TSISO639LanguageDescriptorAudioTypeHearingImpaired           = 0x02,
    TSISO639LanguageDescriptorAudioTypeVisualImpairedCommentary = 0x03,
    // 0x04-0x7F (4-127) User private
    TSISO639LanguageDescriptorAudioTypePrimary                  = 0x80,
    TSISO639LanguageDescriptorAudioTypeNative                   = 0x81,
    TSISO639LanguageDescriptorAudioTypeEmergency                = 0x82,
    TSISO639LanguageDescriptorAudioTypePrimaryCommentary        = 0x83,
    TSISO639LanguageDescriptorAudioTypeAlternateCommentary      = 0x84,
    // 0x85-0xFF (133-255) Reserved
};

@interface TSISO639LanguageDescriptorEntry: NSObject
@property(nonatomic, readonly) uint8_t audioType;
@property(nonatomic, readonly, nonnull) NSString *languageCode;
@end

@interface TSISO639LanguageDescriptor: TSDescriptor
@property(nonatomic, readonly, nullable) NSArray<TSISO639LanguageDescriptorEntry*> *entries;
-(instancetype _Nonnull)initWithTag:(uint8_t)tag
                            payload:(NSData* _Nonnull)payload
                             length:(NSUInteger)length;
@end
