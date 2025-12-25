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
#import "Table/TSProgramMapTable.h"
#import "Table/TSProgramAssociationTable.h"
#import "Table/DVB/TSDvbServiceDescriptionTable.h"
#import "Table/ATSC/TSAtscVirtualChannelTable.h"
#import "TR101290/TSTr101290Statistics.h"

@class TSDemuxer;
@class TSDemuxerDVBState;
@class TSDemuxerATSCState;

/**
 * DVB Mode Support:
 * - SDT (Service Description Table): IMPLEMENTED
 * - NIT (Network Information): PID defined, parsing NOT IMPLEMENTED
 * - EIT (Event Information): PID defined, parsing NOT IMPLEMENTED
 * - TDT/TOT (Time tables): PID defined, parsing NOT IMPLEMENTED
 * - DVB Descriptors: Tags defined, only 0x48 (Service) parsed
 * - DVB String Encoding: IMPLEMENTED (ISO 6937, ISO 8859-x, UTF-8)
 *
 * ATSC Mode Support:
 * - VCT (Virtual Channel Table): STUB (header only)
 * - MGT (Master Guide Table): NOT IMPLEMENTED
 * - STT (System Time Table): NOT IMPLEMENTED
 * - RRT/EIT/ETT: NOT IMPLEMENTED
 * - Stream types 0x81/0x87: IMPLEMENTED (AC-3/E-AC-3)
 */

#pragma mark - Delegate Protocol

@protocol TSDemuxerDelegate <NSObject>

/// Required - standard-agnostic callbacks
-(void)demuxer:(TSDemuxer * _Nonnull)demuxer didReceivePat:(TSProgramAssociationTable* _Nonnull)pat previousPat:(TSProgramAssociationTable* _Nullable)previousPat;
-(void)demuxer:(TSDemuxer * _Nonnull)demuxer didReceivePmt:(TSProgramMapTable* _Nonnull)pmt previousPmt:(TSProgramMapTable* _Nullable)previousPmt;
-(void)demuxer:(TSDemuxer * _Nonnull)demuxer didReceiveAccessUnit:(TSAccessUnit* _Nonnull)accessUnit;

@optional

/// DVB-specific callback (only called in TSDemuxerModeDVB)
-(void)demuxer:(TSDemuxer * _Nonnull)demuxer didReceiveSdt:(TSDvbServiceDescriptionTable* _Nonnull)sdt previousSdt:(TSDvbServiceDescriptionTable* _Nullable)previousSdt;

/// ATSC-specific callback (only called in TSDemuxerModeATSC)
-(void)demuxer:(TSDemuxer * _Nonnull)demuxer didReceiveVct:(TSAtscVirtualChannelTable* _Nonnull)vct previousVct:(TSAtscVirtualChannelTable* _Nullable)previousVct;

@end

#pragma mark - DVB State Wrapper

/// DVB-specific state - accessed via demuxer.dvb
@interface TSDemuxerDVBState : NSObject
@property(nonatomic, readonly, nullable) TSDvbServiceDescriptionTable *sdt;
@end

#pragma mark - ATSC State Wrapper

/// ATSC-specific state - accessed via demuxer.atsc
@interface TSDemuxerATSCState : NSObject
@property(nonatomic, readonly, nullable) TSAtscVirtualChannelTable *vct;
@end

#pragma mark - TSDemuxer

@interface TSDemuxer : NSObject

@property(nonatomic, weak, nullable) id<TSDemuxerDelegate> delegate;
@property(nonatomic, readonly) TSDemuxerMode mode;
/// Auto-detected packet size (188 or 204). Returns 0 until detection completes.
@property(nonatomic, readonly) NSUInteger packetSize;

@property(nonatomic, readonly, nullable) TSProgramAssociationTable *pat;
@property(nonatomic, readonly, nonnull) NSDictionary<ProgramNumber,TSProgramMapTable*> *pmts;

/// DVB-specific state (only populated in TSDemuxerModeDVB)
@property(nonatomic, readonly, nonnull) TSDemuxerDVBState *dvb;

/// ATSC-specific state (only populated in TSDemuxerModeATSC)
@property(nonatomic, readonly, nonnull) TSDemuxerATSCState *atsc;

/// Designated initializer - mode is required.
-(instancetype _Nullable)initWithDelegate:(id<TSDemuxerDelegate> _Nullable)delegate
                                     mode:(TSDemuxerMode)mode;

-(TSProgramMapTable* _Nullable)pmtForPid:(uint16_t)pid;

/// (Currently) not thread safe - i.e. make sure you call this from the same thread.
/// Use [TSTimeUtils nowHostTimeNanos] to provide data arrival time.
-(void)demux:(NSData* _Nonnull)tsDataChunk dataArrivalHostTimeNanos:(uint64_t)dataArrivalHostTimeNanos;

-(TSTr101290Statistics* _Nonnull)statistics;

@end
