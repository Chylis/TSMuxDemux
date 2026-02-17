//
//  TSAccessUnit.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import "TSStreamType.h"
@class TSDescriptor;

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

/// Set to true if this access unit is a random access point (e.g., IDR frame for H.264/H.265).
/// When true, the random_access_indicator will be set in the adaptation field of the first TS packet.
@property(nonatomic, readonly) BOOL isRandomAccessPoint;

/// Raw stream_type from PMT. Use resolvedStreamType for codec identification.
@property(nonatomic, readonly) uint8_t streamType;
@property(nonatomic, readonly, nullable) NSArray<TSDescriptor*> *descriptors;

@property(nonatomic, readonly, nonnull) NSData *compressedData;

-(instancetype _Nonnull)initWithPid:(uint16_t)pid
                                pts:(CMTime)pts
                                dts:(CMTime)dts
                    isDiscontinuous:(BOOL)isDiscontinuous
                 isRandomAccessPoint:(BOOL)isRandomAccessPoint
                         streamType:(uint8_t)streamType
                         descriptors:(NSArray<TSDescriptor*>* _Nullable)descriptors
                     compressedData:(NSData* _Nonnull)compressedData;

/// Creates a PES-packet from the access unit.
/// PTS/DTS are converted to the MPEG-TS 90 kHz timescale, relative to epoch.
/// When epoch is valid, PTS/DTS are offset by the epoch (subtracted) so that timestamps
/// start from zero — aligning them with a PCR clock that also starts from zero.
/// Pass kCMTimeInvalid to use absolute timestamps (no offset).
-(NSData* _Nonnull)toTsPacketPayloadWithEpoch:(CMTime)epoch;

/// Returns the resolved stream type by examining streamType and descriptors.
-(TSResolvedStreamType)resolvedStreamType;

-(BOOL)isAudio;
-(BOOL)isVideo;

-(NSString* _Nonnull)resolvedStreamTypeDescription;

@end
