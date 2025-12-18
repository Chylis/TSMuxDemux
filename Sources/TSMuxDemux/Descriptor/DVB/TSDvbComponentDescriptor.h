//
//  TSDvbComponentDescriptor.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2025-12-18.
//  Copyright © 2025 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "../TSDescriptor.h"

/// DVB Component Descriptor (tag 0x50) as defined in ETSI EN 300 468, section 6.2.8.
/// Describes video/audio component characteristics including format details.
/// https://www.etsi.org/deliver/etsi_en/300400_300499/300468/
@interface TSDvbComponentDescriptor: TSDescriptor

/// Stream content extension (4 bits). Reserved, typically 0xF.
@property(nonatomic, readonly) uint8_t streamContentExt;

/// Stream content type (4 bits).
/// Video: 0x01=MPEG-2, 0x05=H.264/AVC, 0x09=HEVC
/// Audio: 0x02=MPEG-1 Layer 2, 0x04=AC-3, 0x06=HE-AAC
@property(nonatomic, readonly) uint8_t streamContent;

/// Component type (8 bits). Interpretation depends on streamContent.
/// For video: encodes aspect ratio, resolution (SD/HD/UHD), frame rate.
@property(nonatomic, readonly) uint8_t componentType;

/// Component tag linking this descriptor to an elementary stream.
@property(nonatomic, readonly) uint8_t componentTag;

/// ISO 639-2 language code (3 characters), or nil if not present.
@property(nonatomic, readonly, nullable) NSString *languageCode;

/// Descriptive text, or nil if not present.
@property(nonatomic, readonly, nullable) NSData *text;

-(instancetype _Nonnull)initWithTag:(uint8_t)tag
                            payload:(NSData* _Nonnull)payload
                             length:(NSUInteger)length;

/// Returns YES if this describes a video component.
-(BOOL)isVideo;

/// Returns YES if this describes an audio component.
-(BOOL)isAudio;

@end
