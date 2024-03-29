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
    TSStreamTypeADTSAAC = 0x0f,
    TSStreamTypeH264 = 0x1b,
    TSStreamTypeH265 = 0x24,
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

@property(nonatomic, readonly, nonnull) NSData *compressedData;

-(instancetype _Nonnull)initWithPid:(uint16_t)pid
                                pts:(CMTime)pts
                                dts:(CMTime)dts
                         streamType:(TSStreamType)streamType
                     compressedData:(NSData* _Nonnull)compressedData;

/// Creates a PES-packet from the received ts packet.
+(instancetype _Nullable)initWithTsPacket:(TSPacket* _Nonnull)packet
                                      pid:(uint16_t)pid
                               streamType:(TSStreamType)streamType;

/// Creates a PES-packet from the access unit.
/// Converts the pts and dts to the MPEG-TS timescale.
-(NSData* _Nonnull)toTsPacketPayload;

-(BOOL)isVideoStreamType;
+(BOOL)isVideoStreamType:(TSStreamType)streamType;
+(NSString* _Nonnull)streamTypeDescription:(TSStreamType)streamType;

@end
