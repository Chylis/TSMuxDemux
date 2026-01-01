//
//  TSProgramAssociationTable.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-07.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSProgramSpecificInformationTable.h"
#import "../TSConstants.h"
typedef Pid PmtPid;

#pragma mark - TSProgramAssociationTable

/// See "Rec. ITU-T H.222.0 (03/2017)"
/// section "2.4.4.3 Program association table" page 51
@interface TSProgramAssociationTable : NSObject

@property(nonatomic, readonly) TSProgramSpecificInformationTable * _Nonnull psi;

-(uint16_t)transportStreamId;
/// Reverse lookup - get a program number from a pid
-(ProgramNumber _Nullable)programNumberFromPid:(uint16_t)pid;
-(NSDictionary<ProgramNumber, PmtPid>* _Nonnull)programmes;

#pragma mark Muxer

-(instancetype _Nullable)initWithTransportStreamId:(uint16_t)transportStreamId
                                        programmes:(NSDictionary<ProgramNumber, PmtPid> * _Nonnull)programmes;

-(NSData* _Nonnull)toTsPacketPayload;

#pragma mark Demuxer

-(instancetype _Nullable)initWithPSI:(TSProgramSpecificInformationTable* _Nonnull)psi;

@end
