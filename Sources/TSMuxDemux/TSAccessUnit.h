//
//  TSAccessUnit.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
@class TSPacket;

/// https://en.wikipedia.org/wiki/Program-specific_information#Elementary_stream_types
typedef NS_ENUM(uint8_t, TSStreamType) {
    // TSStreamTypePrivateData type of data is determined by descriptor tags (TSDescriptorTag)
    TSStreamTypePrivateData = 0x06,
    TSStreamTypeADTSAAC = 0x0f,
    TSStreamTypeH264 = 0x1b,
    TSStreamTypeH265 = 0x24,
};


typedef NS_ENUM(uint8_t, TSDescriptorTag) {
    TSDescriptorTagUnknown = 0x00,
    TSDescriptorTagVideoStream = 0x02,
    TSDescriptorTagAudioStream = 0x03,
    TSDescriptorTagRegistration = 0x05,
    TSDescriptorTagISO639Language = 0x0A,
    TSDescriptorTagMaximumBitrate = 0x0E,
    TSDescriptorTagStreamIdentifier = 0x52,
    TSDescriptorTagTeletext = 0x56,
    TSDescriptorTagAc3 = 0x6A,
    TSDescriptorTagEnhancedAc3 = 0x7A,
    TSDescriptorTagAac = 0x7C,
    // FIXME MG: 0x7F indicates an extension_descriptor, i.e I need to check the next byte (descriptor_tag_extension), e.g. AC4 audio.
    TSDescriptorTagExtension = 0x7F,
};

typedef NS_ENUM(uint8_t, TSExtensionDescriptorTag) {
    TSExtensionDescriptorTagAc4 = 0x15,
};


/// See "Rec. ITU-T H.222.0 (03/2017)"
/// section "2.4.3.6 PES packet" page 37
@interface TSAccessUnit: NSObject

@property(nonatomic, readonly) uint16_t pid;

/// Set to kCMTimeInvalid to represent "No PTS".
@property(nonatomic, readonly) CMTime pts;

/// Set to kCMTimeInvalid to represent "No DTS".
@property(nonatomic, readonly) CMTime dts;

@property(nonatomic, readonly) TSStreamType streamType;
@property(nonatomic, readonly) TSDescriptorTag descriptorTag;

@property(nonatomic, readonly, nonnull) NSData *compressedData;

-(instancetype _Nonnull)initWithPid:(uint16_t)pid
                                pts:(CMTime)pts
                                dts:(CMTime)dts
                         streamType:(TSStreamType)streamType
                         descriptorTag:(TSDescriptorTag)descriptorTag
                     compressedData:(NSData* _Nonnull)compressedData;

/// Creates a PES-packet from the received ts packet.
+(instancetype _Nullable)initWithTsPacket:(TSPacket* _Nonnull)packet
                                      pid:(uint16_t)pid
                               streamType:(TSStreamType)streamType
                            descriptorTag:(TSDescriptorTag)descriptorTag;


/// Creates a PES-packet from the access unit.
/// Converts the pts and dts to the MPEG-TS timescale.
-(NSData* _Nonnull)toTsPacketPayload;

-(BOOL)isAudioStreamType;
+(BOOL)isAudioStreamType:(TSStreamType)streamType descriptorTag:(TSDescriptorTag)descriptorTag;

-(BOOL)isVideoStreamType;
+(BOOL)isVideoStreamType:(TSStreamType)streamType;

-(NSString* _Nonnull)streamTypeDescription;
+(NSString* _Nonnull)streamTypeDescription:(TSStreamType)streamType descriptorTag:(TSDescriptorTag)descriptorTag;

@end
