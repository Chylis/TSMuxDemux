//
//  TSDemuxer.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSConstants.h"
#import "TSAccessUnit.h"
#import "TSProgramMapTable.h"
#import "TSTr101290Statistics.h"
#import "TSProgramAssociationTable.h"
@class TSDemuxer;


@protocol TSDemuxerDelegate
-(void)demuxer:(TSDemuxer * _Nonnull)demuxer didReceivePat:(TSProgramAssociationTable* _Nonnull)pat previousPat:(TSProgramAssociationTable* _Nullable)previousPat;
-(void)demuxer:(TSDemuxer * _Nonnull)demuxer didReceivePmt:(TSProgramMapTable* _Nonnull)pmt previousPmt:(TSProgramMapTable* _Nullable)previousPmt;
-(void)demuxer:(TSDemuxer * _Nonnull)demuxer didReceiveAccessUnit:(TSAccessUnit* _Nonnull)accessUnit;
@end

@interface TSDemuxer : NSObject

@property(nonatomic, weak, nullable) id<TSDemuxerDelegate> delegate;

@property(nonatomic, readonly, nullable) TSProgramAssociationTable *pat;
@property(nonatomic, readonly, nonnull) NSDictionary<ProgramNumber,TSProgramMapTable*> *pmts;

-(instancetype _Nullable)initWithDelegate:(id<TSDemuxerDelegate> _Nullable)delegate;

-(TSProgramMapTable* _Nullable)pmtForPid:(uint16_t)pid;

/// (Currently) not thread safe - i.e. make sure you call this from the same thread.
/// Use [TSTimeUtils nowHostTimeNanos] to provide data arrival time.
-(void)demux:(NSData* _Nonnull)tsDataChunk dataArrivalHostTimeNanos:(uint64_t)dataArrivalHostTimeNanos;

-(TSTr101290Statistics* _Nonnull)statistics;

@end
