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
@class TSDescriptor;

// Descriptor tags defined in ISO/IEC 13818-1 / ITU-T H.222.0
// https://en.wikipedia.org/wiki/Program-specific_information#Elementary_stream_types
typedef NS_ENUM(uint8_t, TSStreamType) {
    // TSStreamTypePrivateData type of data is determined by descriptor tags (TSDescriptorTag)
    TSStreamTypePrivateData                          = 0x06,
    TSStreamTypeADTSAAC                              = 0x0f,
    TSStreamTypeH264                                 = 0x1b,
    TSStreamTypeH265                                 = 0x24,
};

// Defined in ANSI/SCTE 35 - Digital Program Insertion Cueing Message
// Uses range 0x80 - 0xFF (i.e. of the user defined range)
typedef NS_ENUM(uint8_t, TSScte35StreamType) {
    TSScte35StreamTypeSpliceInfo                     = 0x86
};

/// See "Rec. ITU-T H.222.0 (03/2017)"
/// section "2.4.3.6 PES packet" page 37
@interface TSAccessUnit: NSObject

@property(nonatomic, readonly) uint16_t pid;

/// Set to kCMTimeInvalid to represent "No PTS".
@property(nonatomic, readonly) CMTime pts;

/// Set to kCMTimeInvalid to represent "No DTS".
@property(nonatomic, readonly) CMTime dts;

/// Set to true if the ts packet is flagged as discontinuous. Should be used as a hint to e.g. reset PTS-anchors etc.
@property(nonatomic, readonly) BOOL isDiscontinuous;

@property(nonatomic, readonly) uint8_t streamType;
@property(nonatomic, readonly, nullable) NSArray<TSDescriptor*> *descriptors;

@property(nonatomic, readonly, nonnull) NSData *compressedData;

-(instancetype _Nonnull)initWithPid:(uint16_t)pid
                                pts:(CMTime)pts
                                dts:(CMTime)dts
                    isDiscontinuous:(BOOL)isDiscontinuous
                         streamType:(uint8_t)streamType
                         descriptors:(NSArray<TSDescriptor*>* _Nullable)descriptors
                     compressedData:(NSData* _Nonnull)compressedData;

/// Creates a PES-packet from the received ts packet.
+(instancetype _Nullable)initWithTsPacket:(TSPacket* _Nonnull)packet
                                      pid:(uint16_t)pid
                               streamType:(uint8_t)streamType
                              descriptors:(NSArray<TSDescriptor*>* _Nullable)descriptors;


/// Creates a PES-packet from the access unit.
/// Converts the pts and dts to the MPEG-TS timescale.
-(NSData* _Nonnull)toTsPacketPayload;

-(BOOL)isAudioStreamType;
+(BOOL)isAudioStreamType:(uint8_t)streamType
             descriptors:(NSArray<TSDescriptor*>* _Nullable)descriptors;

-(BOOL)isVideoStreamType;
+(BOOL)isVideoStreamType:(uint8_t)streamType;

-(NSString* _Nonnull)streamTypeDescription;
+(NSString* _Nonnull)streamTypeDescription:(uint8_t)streamType;

@end
