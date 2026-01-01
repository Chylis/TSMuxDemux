//
//  TSDemuxer.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSDemuxer.h"
#import "TSConstants.h"
#import "TSPacket.h"
#import "TR101290/TSTr101290Analyzer.h"
#import "TR101290/TSTr101290AnalyzeContext.h"
#import "TR101290/TSTr101290CompletedSection.h"
#import "Table/TSProgramAssociationTable.h"
#import "Table/TSProgramMapTable.h"
#import "Table/TSProgramSpecificInformationTable.h"
#import "Table/DVB/TSDvbServiceDescriptionTable.h"
#import "Table/ATSC/TSAtscVirtualChannelTable.h"
#import "TSAccessUnit.h"
#import "TSElementaryStream.h"
#import "TSElementaryStreamBuilder.h"
#import "Table/TSPsiTableBuilder.h"
#import "TSTimeUtil.h"

#pragma mark - DVB State Wrapper

@interface TSDemuxerDVBState()
@property(nonatomic, readwrite, nullable) TSDvbServiceDescriptionTable *sdt;
@end

@implementation TSDemuxerDVBState
@end

#pragma mark - ATSC State Wrapper

@interface TSDemuxerATSCState()
@property(nonatomic, readwrite, nullable) TSAtscVirtualChannelTable *vct;
@end

@implementation TSDemuxerATSCState
@end

#pragma mark - TSDemuxer

@interface TSDemuxer() <TSPsiTableBuilderDelegate, TSElementaryStreamBuilderDelegate>

@property(nonatomic, nonnull) TSTr101290Analyzer *tsPacketAnalyzer;
@property(nonatomic, nonnull) NSMutableDictionary<Pid, TSPsiTableBuilder*> *tableBuilders;
@property(nonatomic, nonnull) NSMutableDictionary<Pid, TSElementaryStreamBuilder*> *streamBuilders;

// Temporary storage for completed sections (set in callback, cleared after analysis)
// Multiple sections can complete from a single packet
@property(nonatomic, nonnull) NSMutableArray<TSTr101290CompletedSection*> *pendingCompletedSections;

@end

@implementation TSDemuxer
{
    NSMutableDictionary<ProgramNumber,TSProgramMapTable*> *_pmts;
    NSDictionary<NSNumber*, TSProgramMapTable*> *_cachedPmtsByPid;

    // Packet format auto-detection (0 = not yet detected)
    NSUInteger _packetSize;
}

-(instancetype)initWithDelegate:(id<TSDemuxerDelegate>)delegate mode:(TSDemuxerMode)mode
{
    self = [super init];
    if (self) {
        _mode = mode;
        self.delegate = delegate;
        self.streamBuilders = [NSMutableDictionary dictionary];
        self.tsPacketAnalyzer = [TSTr101290Analyzer new];
        self.pendingCompletedSections = [NSMutableArray array];

        _pmts = [NSMutableDictionary dictionary];
        _dvb = [TSDemuxerDVBState new];
        _atsc = [TSDemuxerATSCState new];

        self.tableBuilders = [NSMutableDictionary dictionary];
    }
    return self;
}

-(void)setPat:(TSProgramAssociationTable*)pat
{
    TSProgramAssociationTable *prevPat = self.pat;
    if ([pat isEqual:prevPat]) {
        return;
    }
    _pat = pat;
    _cachedPmtsByPid = nil;
    [self.delegate demuxer:self didReceivePat:pat previousPat:prevPat];
}

-(void)setSdt:(TSDvbServiceDescriptionTable*)sdt
{
    TSDvbServiceDescriptionTable *prevSdt = self.dvb.sdt;
    if ([sdt isEqual:prevSdt]) {
        return;
    }
    self.dvb.sdt = sdt;
    if ([self.delegate respondsToSelector:@selector(demuxer:didReceiveSdt:previousSdt:)]) {
        [self.delegate demuxer:self didReceiveSdt:sdt previousSdt:prevSdt];
    }
}

-(void)setVct:(TSAtscVirtualChannelTable*)vct
{
    TSAtscVirtualChannelTable *prevVct = self.atsc.vct;
    if ([vct isEqual:prevVct]) {
        return;
    }
    self.atsc.vct = vct;
    if ([self.delegate respondsToSelector:@selector(demuxer:didReceiveVct:previousVct:)]) {
        [self.delegate demuxer:self didReceiveVct:vct previousVct:prevVct];
    }
}

-(void)updatePmt:(TSProgramMapTable*)pmt
{
    ProgramNumber programNumber = @(pmt.programNumber);
    TSProgramMapTable *prevPmt = _pmts[programNumber];
    if ([pmt isEqual:prevPmt]) {
        return;
    }

    // Mark all pids in prev PMT for removal
    NSMutableSet *pidsToRemove = [NSMutableSet set];
    [prevPmt.elementaryStreams enumerateObjectsUsingBlock:^(TSElementaryStream *es, BOOL *stop) {
        [pidsToRemove addObject:@(es.pid)];
    }];
    
    for (TSElementaryStream *stream in pmt.elementaryStreams) {
        // Keep pid if still present in new PMT
        [pidsToRemove removeObject:@(stream.pid)];
        
        TSElementaryStreamBuilder *builder = [self.streamBuilders objectForKey:@(stream.pid)];
        if (!builder) {
            // Add builders for new pids
            builder = [[TSElementaryStreamBuilder alloc] initWithDelegate:self
                                                                      pid:stream.pid
                                                               streamType:stream.streamType
                                                              descriptors:stream.descriptors];
            [self.streamBuilders setObject:builder forKey:@(stream.pid)];
        }
    }
    
    // Remove builders for no longer existing pids
    if (pidsToRemove.count > 0) {
        [self.streamBuilders removeObjectsForKeys:pidsToRemove.allObjects];
    }

    _pmts[programNumber] = pmt;
    _cachedPmtsByPid = nil;
    [self.delegate demuxer:self didReceivePmt:pmt previousPmt:prevPmt];
}

-(TSTr101290Statistics* _Nonnull)statistics
{
    return self.tsPacketAnalyzer.stats;
}

// TODO: Performance improvement - maintain direct PID to PMT index
-(TSProgramMapTable* _Nullable)pmtForPid:(uint16_t)pid
{
    for (TSProgramMapTable *pmt in [_pmts allValues]) {
        if ([pmt elementaryStreamWithPid:pid]) {
            return pmt;
        }
    }
    return nil;
}

/// Returns PMTs keyed by their PID (for TR101290 analysis).
/// Result is cached and invalidated when PAT or PMT changes.
-(NSDictionary<NSNumber*, TSProgramMapTable*>*)pmtsByPid
{
    if (_cachedPmtsByPid) {
        return _cachedPmtsByPid;
    }
    if (!self.pat) {
        return @{};
    }
    NSMutableDictionary<NSNumber*, TSProgramMapTable*> *result = [NSMutableDictionary dictionary];
    [self.pat.programmes enumerateKeysAndObjectsUsingBlock:^(NSNumber *programNumber, NSNumber *pmtPid, BOOL *stop) {
        TSProgramMapTable *pmt = _pmts[programNumber];
        if (pmt) {
            result[pmtPid] = pmt;
        }
    }];
    _cachedPmtsByPid = result;
    return _cachedPmtsByPid;
}

#pragma mark - Packet Routing Helpers

/// Adds a TS packet to the appropriate PSI table builder, creating one if needed.
-(void)addPacketToPsiTableBuilder:(TSPacket *)tsPacket forPid:(uint16_t)pid
{
    TSPsiTableBuilder *builder = [self.tableBuilders objectForKey:@(pid)];
    if (!builder) {
        builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:pid];
        [self.tableBuilders setObject:builder forKey:@(pid)];
    }
    [builder addTsPacket:tsPacket];
}


/// Routes a single TS packet to appropriate handler. Returns YES if packet is PES data.
-(BOOL)routeTsPacket:(TSPacket *)tsPacket
{
    uint16_t pid = tsPacket.header.pid;

    // Standard PIDs (mode-agnostic)
    if (pid == PID_PAT) {
        [self addPacketToPsiTableBuilder:tsPacket forPid:pid];
        return NO;
    }
    if (pid == PID_CAT)        { return NO; }  // TODO: Parse CAT
    if (pid == PID_TSDT)       { NSLog(@"Received TSDT"); return NO; }  // TODO: Parse
    if (pid == PID_IPMP)       { NSLog(@"Received IPMP"); return NO; }  // TODO: Parse
    if (pid == PID_ASI)        { NSLog(@"Received ASI"); return NO; }   // TODO: Parse
    if (pid == PID_NULL_PACKET) { return NO; }

    // DVB mode
    if (self.mode == TSDemuxerModeDVB) {
        if (pid == PID_DVB_SDT_BAT_ST) {
            [self addPacketToPsiTableBuilder:tsPacket forPid:pid];
            return NO;
        }
        if (pid >= PID_DVB_NIT_ST && pid <= PID_DVB_SIT) {
            return NO;  // Other DVB reserved PIDs - not yet implemented
        }
        if ([TSPidUtil isAtscReservedPid:pid]) {
            NSLog(@"[TSDemuxer] WARN: Received ATSC PID 0x%04X in DVB mode - possible mode mismatch", pid);
            return NO;
        }
    }

    // ATSC mode
    if (self.mode == TSDemuxerModeATSC) {
        if (pid == PID_ATSC_PSIP) {
            [self addPacketToPsiTableBuilder:tsPacket forPid:pid];
            return NO;
        }
        if ([TSPidUtil isDvbReservedPid:pid]) {
            NSLog(@"[TSDemuxer] WARN: Received DVB PID 0x%04X in ATSC mode - possible mode mismatch", pid);
            return NO;
        }
    }

    // PMT and elementary streams (from PAT)
    ProgramNumber programNumber = [self.pat programNumberFromPid:pid];
    if (programNumber != nil) {
        if ([programNumber isEqualToNumber:@(PROGRAM_NUMBER_NETWORK_INFO)]) {
            return NO;  // TODO: Parse Network Info table
        }
        [self addPacketToPsiTableBuilder:tsPacket forPid:pid];  // PMT
        return NO;
    }

    // Not a reserved PID and not in PAT - treat as PES
    return ![TSPidUtil isReservedPid:pid];
}

-(NSUInteger)packetSize
{
    return _packetSize;
}

/// Detects packet size using buffer length modulo arithmetic.
/// Assumes input is packet-aligned (starts at packet boundary).
/// BTS (204-byte) is detected only when unambiguous: divisible by 204 but not by 188.
/// When ambiguous (divisible by both), defaults to standard 188-byte TS packets.
-(NSUInteger)detectPacketSizeFromLength:(NSUInteger)length
{
    BOOL isBts = (length % TS_PACKET_SIZE_204 == 0) && (length % TS_PACKET_SIZE_188 != 0);
    return isBts ? TS_PACKET_SIZE_204 : TS_PACKET_SIZE_188;
}

-(void)demux:(NSData* _Nonnull)chunk dataArrivalHostTimeNanos:(uint64_t)dataArrivalHostTimeNanos
{
    // Auto-detect packet size on first call
    if (_packetSize == 0) {
        _packetSize = [self detectPacketSizeFromLength:chunk.length];
        NSLog(@"TSDemuxer: Detected %lu-byte TS packets", (unsigned long)_packetSize);
    }

    NSArray<TSPacket*> *tsPackets = [TSPacket packetsFromChunkedTsData:chunk packetSize:_packetSize];
    for (TSPacket *tsPacket in tsPackets) {
        BOOL isPes = [self routeTsPacket:tsPacket];

        TSTr101290AnalyzeContext *context = [[TSTr101290AnalyzeContext alloc]
                                             initWithPat:self.pat
                                             pmts:self.pmtsByPid
                                             nowMs:dataArrivalHostTimeNanos / 1000000
                                             completedSections:self.pendingCompletedSections];
        [self.tsPacketAnalyzer analyzeTsPacket:tsPacket context:context];

        // Clear pending sections after analysis
        [self.pendingCompletedSections removeAllObjects];

        if (isPes) {
            uint16_t pid = tsPacket.header.pid;
            TSElementaryStreamBuilder *esBuilder = [self.streamBuilders objectForKey:@(pid)];
            [esBuilder addTsPacket:tsPacket];
        }
    }
}

-(void)tableBuilder:(TSPsiTableBuilder *)builder didBuildTable:(TSProgramSpecificInformationTable *)table
{
    // Store completed section for TR101290 analysis (multiple sections can complete per packet)
    TSTr101290CompletedSection *completed = [[TSTr101290CompletedSection alloc] initWithSection:table pid:builder.pid];
    [self.pendingCompletedSections addObject:completed];

    // Standard-agnostic tables
    if (table.tableId == TABLE_ID_PAT) {
        self.pat = [[TSProgramAssociationTable alloc] initWithPSI:table];
    } else if (table.tableId == TABLE_ID_PMT) {
        [self updatePmt:[[TSProgramMapTable alloc] initWithPSI:table]];
    }
    // DVB tables (only in DVB mode)
    else if (self.mode == TSDemuxerModeDVB && table.tableId == TABLE_ID_DVB_SDT_ACTUAL_TS) {
        [self setSdt:[[TSDvbServiceDescriptionTable alloc] initWithPSI:table]];
    }
    // ATSC tables (only in ATSC mode)
    else if (self.mode == TSDemuxerModeATSC &&
             (table.tableId == TABLE_ID_ATSC_TVCT || table.tableId == TABLE_ID_ATSC_CVCT)) {
        [self setVct:[[TSAtscVirtualChannelTable alloc] initWithPSI:table]];
    }
    // ATSC tables we acknowledge but don't parse (MGT, STT, RRT, EIT, ETT)
    else if (self.mode == TSDemuxerModeATSC &&
             (table.tableId == TABLE_ID_ATSC_MGT ||
              table.tableId == TABLE_ID_ATSC_STT ||
              table.tableId == TABLE_ID_ATSC_RRT ||
              table.tableId == TABLE_ID_ATSC_EIT ||
              table.tableId == TABLE_ID_ATSC_ETT)) {
        // TODO Parse...
    }
    else {
        NSLog(@"Received unhandled PSI table pid: %u, tableId: 0x%02X", builder.pid, table.tableId);
    }
}

-(void)streamBuilder:(TSElementaryStreamBuilder *)builder didBuildAccessUnit:(TSAccessUnit *)accessUnit
{
    [self.delegate demuxer:self didReceiveAccessUnit:accessUnit];
}

@end
