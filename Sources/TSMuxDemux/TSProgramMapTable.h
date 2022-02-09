//
//  TSProgramMapTable.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-07.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSProgramSpecificInformationTable.h"
#import "TSConstants.h"
@class TSPacket;
@class TSElementaryStream;

/// See "Rec. ITU-T H.222.0 (03/2017)"
/// section "2.4.4.8 Program map table"         page 54
@interface TSProgramMapTable : NSObject

@property(nonatomic, readonly) TSProgramSpecificInformationTable * _Nonnull psi;

@property(nonatomic) uint16_t pcrPid;
@property(nonatomic, readonly) uint16_t programNumber;
@property(nonatomic, readonly) uint16_t programInfoLength;
@property(nonatomic, readonly) NSSet<TSElementaryStream*> * _Nonnull elementaryStreams;

-(void)addElementaryStream:(TSElementaryStream* _Nonnull)elementaryStream;
-(TSElementaryStream* _Nullable)elementaryStreamWithPid:(uint16_t)pid;

#pragma mark Muxer

-(instancetype _Nullable)initWithProgramNumber:(uint16_t)programNumber
                                        pcrPid:(uint16_t)pcrPid
                             elementaryStreams:(NSSet<TSElementaryStream*>* _Nonnull)elementaryStreams;

-(NSData* _Nonnull)toTsPacketPayload;

#pragma mark Demuxer

-(instancetype _Nullable)initWithTsPacket:(TSPacket* _Nonnull)packet;

@end
