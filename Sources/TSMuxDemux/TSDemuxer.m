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
#import "TSTr101290Analyzer.h"
#import "TSProgramAssociationTable.h"
#import "TSProgramMapTable.h"
#import "TSAccessUnit.h"
#import "TSElementaryStream.h"
#import "TSElementaryStreamBuilder.h"
#import "TSTimeUtil.h"

typedef NSNumber *ElementaryStreamPid;

@interface TSDemuxer() <TSElementaryStreamBuilderDelegate>

@property(nonatomic, nonnull) TSTr101290Analyzer *tsPacketAnalyzer;
@property(nonatomic, nonnull) NSMutableDictionary<ElementaryStreamPid, TSElementaryStreamBuilder*> *streamBuilders;

@end

@implementation TSDemuxer
{
    NSMutableDictionary<ProgramNumber,TSProgramMapTable*> *_pmts;
}

-(instancetype)initWithDelegate:(id<TSDemuxerDelegate>)delegate
{
    self = [super init];
    if (self) {
        self.delegate = delegate;
        self.streamBuilders = [NSMutableDictionary dictionary];
        self.tsPacketAnalyzer = [TSTr101290Analyzer new];
        
        _pmts = [NSMutableDictionary dictionary];
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
    [self.delegate demuxer:self didReceivePat:pat previousPat:prevPat];
}

-(void)updatePmt:(TSProgramMapTable*)pmt
{
    ProgramNumber programNumber = @(pmt.programNumber);
    TSProgramMapTable *prevPmt = _pmts[programNumber];
    if ([pmt isEqual:prevPmt]) {
        return;
    }
    
    NSMutableSet *pidsToRemove = [NSMutableSet setWithArray:self.streamBuilders.allKeys];
    for (TSElementaryStream *stream in pmt.elementaryStreams) {
        [pidsToRemove removeObject:@(stream.pid)];
        
        // Add builders for new pids
        TSElementaryStreamBuilder *builder = [self.streamBuilders objectForKey:@(stream.pid)];
        if (!builder) {
            builder = [[TSElementaryStreamBuilder alloc] initWithDelegate:self
                                                                      pid:stream.pid
                                                               streamType:stream.streamType];
            [self.streamBuilders setObject:builder forKey:@(stream.pid)];
        }
    }
    
    // Remove builders for no longer existing pids
    [self.streamBuilders removeObjectsForKeys:pidsToRemove.allObjects];
    
    _pmts[programNumber] = pmt;
    [self.delegate demuxer:self didReceivePmt:pmt previousPmt:prevPmt];
}

-(TSTr101290Statistics* _Nonnull)statistics
{
    return self.tsPacketAnalyzer.stats;
}


-(void)demux:(NSData* _Nonnull)chunk dataArrivalHostTimeNanos:(uint64_t)dataArrivalHostTimeNanos
{
    NSArray<TSPacket*> *tsPackets = [TSPacket packetsFromChunkedTsData:chunk];
    for (TSPacket *tsPacket in tsPackets) {
        BOOL isPes = NO;
        TSProgramMapTable *pmt = nil;
        TSProgramAssociationTable *pat = nil;
        
        uint16_t pid = tsPacket.header.pid;
        if (pid == PID_PAT) {
            pat = [[TSProgramAssociationTable alloc] initWithTsPacket:tsPacket];
        } else if (pid == PID_CAT) {
            // TODO Parse...
            NSLog(@"Received CAT");
        } else if (pid == PID_TSDT) {
            // TODO Parse...
            NSLog(@"Received TSDT");
        } else if (pid == PID_IPMP) {
            // TODO Parse...
            NSLog(@"Received IPMP");
        } else if (pid == PID_ASI) {
            // TODO Parse...
            NSLog(@"Received ASI");
        } else if (pid == PID_NULL_PACKET) {
            // TODO Parse...
            //NSLog(@"Received null packet");
        } else {
            ProgramNumber programNumber = [self.pat programNumberFromPid:pid];
            const BOOL isPidInPat = programNumber != nil;
            if (isPidInPat) {
                // PSI
                if ([programNumber isEqualToNumber:@(PROGRAM_NUMBER_NETWORK_INFO)]) {
                    // TODO Parse...
                    NSLog(@"Received Network Info table");
                } else {
                    pmt = [[TSProgramMapTable alloc] initWithTsPacket:tsPacket];
                }
            } else if (![PidUtil isReservedPid:pid]){
                isPes = YES;
            }
        }
        
        // Analyze first
        [self.tsPacketAnalyzer analyzeTsPacket:tsPacket
                                           pat:pat
                                           pmt:pmt
                             dataArrivalTimeMs:dataArrivalHostTimeNanos / 1000000];
        
        // Then process
        if (pat) {
            self.pat = pat;
        } else if (pmt) {
            [self updatePmt:pmt];
        } else if (isPes) {
            TSElementaryStreamBuilder *builder = [self.streamBuilders objectForKey:@(pid)];
            [builder addTsPacket:tsPacket];
        }
    }
}

-(void)streamBuilder:(TSElementaryStreamBuilder *)builder didBuildAccessUnit:(TSAccessUnit *)accessUnit
{
    [self.delegate demuxer:self didReceiveAccessUnit:accessUnit];
}

@end
