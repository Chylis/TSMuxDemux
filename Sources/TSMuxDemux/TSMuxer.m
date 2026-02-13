//
//  TSMuxer.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-01.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSMuxer.h"
#import "TSElementaryStream.h"
#import "TSAccessUnit.h"
#import "TSPacket.h"
#import "Table/TSProgramAssociationTable.h"
#import "Table/TSProgramMapTable.h"
#import "TSTimeUtil.h"
#import "TSLog.h"

#pragma mark - TSMuxerSettings

#define DEFAULT_PSI_INTERVAL_MS 250
#define DEFAULT_PROGRAM1_PMT 0x1000 // 4096
#define MAX_TARGET_BITRATE_KBPS 60000 // safety net
#define DEFAULT_MAX_QUEUED_ACCESS_UNITS 300
#define STATS_LOG_INTERVAL_MS 10000

@implementation TSMuxerSettings

-(instancetype)init
{
    self = [super init];
    if (self) {
        _pmtPid = DEFAULT_PROGRAM1_PMT;
        _psiIntervalMs = DEFAULT_PSI_INTERVAL_MS;
        _maxNumQueuedAccessUnits = DEFAULT_MAX_QUEUED_ACCESS_UNITS;
    }
    return self;
}

-(instancetype)copyWithZone:(NSZone *)zone
{
    TSMuxerSettings *copy = [[self class] allocWithZone:zone];
    copy.pmtPid = self.pmtPid;
    copy.psiIntervalMs = self.psiIntervalMs;
    copy.targetBitrateKbps = self.targetBitrateKbps;
    copy.maxNumQueuedAccessUnits = self.maxNumQueuedAccessUnits;
    return copy;
}

@end

#pragma mark - TSMuxer

/// The number of the (one and only) program carried in this ts-stream.
/// Will be present in the PAT.
/// Will have an associated PMT (see PID_PROGRAM1_PMT) and PCR (PID_PROGRAM1_PCR).
/// All elementary streams belong to this program.
/// Note: Program number 0 is reserved for the PID of the Network Information Table
#define PROGRAM_NUMBER 1


@interface TSMuxer()

@property(nonatomic, readonly, nonnull) TSProgramAssociationTable *pat;
@property(nonatomic, readonly, nonnull) TSElementaryStream *patTrack;

@property(nonatomic, readonly, nonnull) TSElementaryStream *pmtTrack;
@property(nonatomic, readonly, nonnull) NSMutableArray<TSAccessUnit*> *accessUnits;

@property(nonatomic) uint16_t pcrPid;
@property(nonatomic) uint8_t versionNumber;
@property(nonatomic, readonly, nonnull) NSSet<TSElementaryStream*> *elementaryStreams;

/// Timestamp representing when the program specific information was last sent.
@property(nonatomic) uint64_t psiSendTimeMs;

@property(nonatomic) CMTime lastSentPcr;
@property(nonatomic) CMTime firstSentPcr;

/// CBR state
@property(nonatomic) uint64_t numTsPacketsEmitted;
@property(nonatomic) uint64_t firstOutputTimeNanos;
/// TS packets waiting to be paced out at the CBR rate. Packets are appended per-AU
/// (e.g. [V V V A A A PSI PSI V V ...]) and drained one-by-one to the delegate.
@property(nonatomic, readonly, nonnull) NSMutableArray<NSData*> *pendingTsPackets;

/// PIDs that need their next emitted packet to carry the discontinuity flag.
@property(nonatomic, readonly, nonnull) NSMutableSet<NSNumber*> *discontinuousPids;

/// Stats
@property(nonatomic) uint64_t statsLastLogTimeMs;
@property(nonatomic) uint64_t statsTsPacketCount;
@property(nonatomic) uint64_t statsNullPacketCount;
@property(nonatomic) uint64_t statsAccessUnitCount;
@property(nonatomic) uint64_t statsDroppedAccessUnitCount;

@end

@implementation TSMuxer

@synthesize settings = _settings;

+(void)validateSettings:(TSMuxerSettings *)settings
{
    if ([TSPidUtil isCustomPidInvalid:settings.pmtPid]) {
        [NSException raise:@"TSMuxerInvalidPidException" format:@"PMT Pid is reserved/out of valid range"];
    }
    if (settings.psiIntervalMs == 0) {
        [NSException raise:@"TSMuxerInvalidSettingsException" format:@"PSI interval must be > 0"];
    }
    if (settings.targetBitrateKbps > MAX_TARGET_BITRATE_KBPS) {
        [NSException raise:@"TSMuxerInvalidSettingsException" format:@"Target bitrate must be <= %d kbps", MAX_TARGET_BITRATE_KBPS];
    }
}

-(instancetype _Nonnull)initWithSettings:(TSMuxerSettings * _Nonnull)settings
                                delegate:(id<TSMuxerDelegate> _Nullable)delegate
{
    self = [super init];
    if (self) {
        self.settings = settings;
        self.delegate = delegate;
        self.psiSendTimeMs = 0;
        self.lastSentPcr = kCMTimeInvalid;
        self.firstSentPcr = kCMTimeInvalid;
        
        const uint8_t streamTypeNotApplicable = 0;
        _pat = [[TSProgramAssociationTable alloc] initWithTransportStreamId:0
                                                                 programmes:@{ @(PROGRAM_NUMBER): @(_settings.pmtPid)}];
        _patTrack = [[TSElementaryStream alloc] initWithPid:PID_PAT
                                                 streamType:streamTypeNotApplicable
                                                descriptors:nil];
        
        _pmtTrack = [[TSElementaryStream alloc] initWithPid:settings.pmtPid
                                                 streamType:streamTypeNotApplicable
                                                descriptors:nil];
        
        _pcrPid = 0;
        _versionNumber = 0;
        _elementaryStreams = [NSSet set];
        _accessUnits = [NSMutableArray array];
        _pendingTsPackets = [NSMutableArray array];
        _discontinuousPids = [NSMutableSet set];
        _nowNanosProvider = ^{ return [TSTimeUtil nowHostTimeNanos]; };
    }
    
    return self;
}

-(TSMuxerSettings*)settings
{
    return [_settings copy];
}

-(void)setSettings:(TSMuxerSettings * _Nonnull)settings
{
    [TSMuxer validateSettings:settings];
    _settings = [settings copy];
}

-(void)setPcrPid:(uint16_t)pcrPid
{
    if (self.pcrPid != pcrPid) {
        _pcrPid = pcrPid;
        [self setVersionNumber:self.versionNumber + 1];
    }
}

-(void)setVersionNumber:(uint8_t)versionNumber
{
    _versionNumber = versionNumber % 32; // Version number is a 5 bit field. 2^5 = 32.
}

-(void)addElementaryStream:(TSElementaryStream* _Nonnull)es
{
    const BOOL alreadyExists = [self elementaryStreamWithPid:es.pid] != nil;
    if (!alreadyExists) {
        _elementaryStreams = [self.elementaryStreams setByAddingObject:es];
        [self setVersionNumber:self.versionNumber + 1];
    }
}

-(TSElementaryStream* _Nullable)elementaryStreamWithPid:(uint16_t)pid
{
    for (TSElementaryStream *es in self.elementaryStreams) {
        if (es.pid == pid) return es;
    }
    return nil;
}

-(void)mux:(TSAccessUnit *)accessUnit
{
    if ([TSPidUtil isCustomPidInvalid:accessUnit.pid] || accessUnit.pid == _settings.pmtPid) {
        [NSException raise:@"TSMuxerInvalidPidException" format:@"Pid is reserved/occupied/out of valid range"];
    }
    
    BOOL hasSetPcrPid = self.pcrPid != 0;
    if (!hasSetPcrPid && [accessUnit isVideo]) {
        self.pcrPid = accessUnit.pid;
    }
    
    TSElementaryStream *track = [self elementaryStreamWithPid:accessUnit.pid];
    if (!track) {
        track = [[TSElementaryStream alloc] initWithPid:accessUnit.pid
                                             streamType:accessUnit.streamType
                                            descriptors:accessUnit.descriptors];
        [self addElementaryStream:track];
    }
    
    [self.accessUnits addObject:accessUnit];
    self.statsAccessUnitCount++;

    // Drop oldest access units during backpressure
    if (_settings.maxNumQueuedAccessUnits > 0 && self.accessUnits.count > _settings.maxNumQueuedAccessUnits) {
        NSUInteger dropCount = self.accessUnits.count - _settings.maxNumQueuedAccessUnits;
        NSMutableSet<NSNumber*> *droppedPids = [NSMutableSet set];
        for (NSUInteger i = 0; i < dropCount; i++) {
            [droppedPids addObject:@(self.accessUnits[i].pid)];
        }
        [self.accessUnits removeObjectsInRange:NSMakeRange(0, dropCount)];
        [self.discontinuousPids unionSet:droppedPids];
        self.statsDroppedAccessUnitCount += dropCount;
        TSLogWarn(@"Queue overflow: dropped %lu access units (PIDs: %@)", (unsigned long)dropCount, droppedPids);
    }

    if (_settings.targetBitrateKbps > 0) {
        [self doMuxCBR];
    } else {
        [self doMuxVBR];
    }

    [self maybeLogStats];
}

#pragma mark - Stats

-(void)maybeLogStats
{
    const uint64_t nowMs = self.nowNanosProvider() / 1000000;
    if (self.statsLastLogTimeMs == 0) {
        self.statsLastLogTimeMs = nowMs;
        return;
    }

    const uint64_t elapsedMs = nowMs - self.statsLastLogTimeMs;
    if (elapsedMs < STATS_LOG_INTERVAL_MS) return;

    const double elapsedSeconds = elapsedMs / 1e3;
    const double actualBitrateKbps = (self.statsTsPacketCount * TS_PACKET_SIZE_188 * 8.0) / elapsedSeconds / 1e3;
    const BOOL isCBR = _settings.targetBitrateKbps > 0;

    TSLogDebug(@"mode=%s targetKbps=%lu actualKbps=%.0f | receivedAUs=%llu droppedAUs=%llu pendingAUs=%lu | pendingTsPackets=%lu emittedTsPackets=%llu nullTsPackets=%llu",
               isCBR ? "CBR" : "VBR",
               (unsigned long)_settings.targetBitrateKbps,
               actualBitrateKbps,
               self.statsAccessUnitCount,
               self.statsDroppedAccessUnitCount,
               (unsigned long)self.accessUnits.count,
               (unsigned long)self.pendingTsPackets.count,
               self.statsTsPacketCount,
               self.statsNullPacketCount);

    self.statsLastLogTimeMs = nowMs;
    self.statsTsPacketCount = 0;
    self.statsNullPacketCount = 0;
    self.statsAccessUnitCount = 0;
    self.statsDroppedAccessUnitCount = 0;
}

#pragma mark - Shared Helpers

-(void)packetizePsiTables:(OnTsPacketDataCallback)onTsPacketCb
{
    [TSPacket packetizePayload:[self.pat toTsPacketPayload]
                         track:self.patTrack
                     forcePusi:YES
                       pcrBase:0
                        pcrExt:0
             discontinuityFlag:NO
              randomAccessFlag:NO
                onTsPacketData:onTsPacketCb];

    if (self.elementaryStreams.count > 0) {
        TSProgramMapTable *pmt = [[TSProgramMapTable alloc] initWithProgramNumber:PROGRAM_NUMBER
                                                                    versionNumber:self.versionNumber
                                                                           pcrPid:self.pcrPid
                                                                elementaryStreams:self.elementaryStreams];
        [TSPacket packetizePayload:[pmt toTsPacketPayload]
                             track:self.pmtTrack
                         forcePusi:YES
                           pcrBase:0
                            pcrExt:0
                 discontinuityFlag:NO
                  randomAccessFlag:NO
                    onTsPacketData:onTsPacketCb];
    }
}

-(void)packetizeNextAccessUnit:(OnTsPacketDataCallback)onTsPacketCb
{
    if (self.accessUnits.count == 0) return;

    const TSAccessUnit *accessUnit = self.accessUnits[0];
    [self.accessUnits removeObjectAtIndex:0];

    NSNumber *pidKey = @(accessUnit.pid);
    BOOL discontinuity = [self.discontinuousPids containsObject:pidKey];
    if (discontinuity) {
        [self.discontinuousPids removeObject:pidKey];
    }

    NSData *pesPacket = [accessUnit toTsPacketPayload];
    TSElementaryStream *track = [self elementaryStreamWithPid:accessUnit.pid];

    uint64_t pcr = [self maybeGetPcr:accessUnit];
    [TSPacket packetizePayload:pesPacket
                         track:track
                     forcePusi:NO
                       pcrBase:pcr
                        pcrExt:0
             discontinuityFlag:discontinuity
              randomAccessFlag:accessUnit.isRandomAccessPoint
                onTsPacketData:onTsPacketCb];
}

#pragma mark - VBR
// mux: → accessUnits → packetize → delegate (immediate, no pacing)

-(void)doMuxVBR
{
    OnTsPacketDataCallback emitTsPacket = ^(NSData *tsPacketData) {
        self.statsTsPacketCount++;
        [self.delegate muxer:self didMuxTSPacketData:tsPacketData];
    };

    while (self.accessUnits.count) {
        const uint64_t nowMs = self.nowNanosProvider() / 1000000;

        if ([self isTimeToSendPsiTables:nowMs]) {
            [self packetizePsiTables:emitTsPacket];
            self.psiSendTimeMs = nowMs;
        }

        [self packetizeNextAccessUnit:emitTsPacket];
    }
}

#pragma mark - CBR
// mux: → accessUnits → packetize → pendingTsPackets → paced out one-by-one at targetBitrateKbps.
// PSI is emitted directly, not via pendingTsPackets.

// FIXME MG: PCR is not emitted during null-only stretches (only emitted with video access units)

/// Returns the number of TS packets that should have been emitted by `nowNanos`
/// to maintain the target CBR. On the very first call (elapsed ≈ 0) this returns 0,
/// so no packets are emitted until wall-clock time has actually passed.
-(uint64_t)expectedPacketCount:(uint64_t)nowNanos
{
    NSAssert(_settings.targetBitrateKbps > 0, @"expectedPacketCount requires CBR mode");
    const double elapsedSeconds = (double)(nowNanos - self.firstOutputTimeNanos) / 1e9;
    const double targetBytesPerSecond = (double)_settings.targetBitrateKbps * 1e3 / 8.0;
    const double targetPacketsPerSecond = targetBytesPerSecond / (double)TS_PACKET_SIZE_188;
    return (uint64_t)(targetPacketsPerSecond * elapsedSeconds);
}

/// Virtual stream time derived from packet count and target bitrate.
/// Represents the time a receiver would perceive when reading at the target CBR.
-(uint64_t)virtualNowMs
{
    NSAssert(_settings.targetBitrateKbps > 0, @"virtualNowMs requires CBR mode");
    const double totalBitsEmitted = self.numTsPacketsEmitted * TS_PACKET_SIZE_188 * 8.0;
    const double targetBitsPerMs = (double)_settings.targetBitrateKbps;
    return (uint64_t)(totalBitsEmitted / targetBitsPerMs);
}

-(void)emitTsPacket:(NSData *)tsPacketData
{
    self.numTsPacketsEmitted++;
    self.statsTsPacketCount++;
    [self.delegate muxer:self didMuxTSPacketData:tsPacketData];
}

-(void)doMuxCBR
{
    const uint64_t nowNanos = self.nowNanosProvider();

    if (self.firstOutputTimeNanos == 0) {
        self.firstOutputTimeNanos = nowNanos;
    }

    const uint64_t expectedNumTsPacketsEmitted = [self expectedPacketCount:nowNanos];
    
    while (self.numTsPacketsEmitted < expectedNumTsPacketsEmitted) {
        const uint64_t virtualNowMs = [self virtualNowMs];
        if ([self isTimeToSendPsiTables:virtualNowMs]) {
            // Emit PSI directly (not enqueued) so psiSendTimeMs reflects actual send time
            [self packetizePsiTables:^(NSData *tsPacketData) {
                [self emitTsPacket:tsPacketData];
            }];
            self.psiSendTimeMs = virtualNowMs;
            continue;
        }

        if (self.pendingTsPackets.count > 0) {
            // Drain one paced TS packet from the pending queue
            NSData *packet = self.pendingTsPackets[0];
            [self.pendingTsPackets removeObjectAtIndex:0];
            [self emitTsPacket:packet];
        } else if (self.accessUnits.count > 0) {
            // No pending TS packets.
            // Let's convert the next AU into a pending TS packet (on demand, to limit memory) for next iteration.
            [self packetizeNextAccessUnit:^(NSData *tsPacketData) {
                [self.pendingTsPackets addObject:tsPacketData];
            }];
        } else {
            // No content available — stuff with null packet to maintain CBR
            self.statsNullPacketCount++;
            [self emitTsPacket:[TSPacket nullPacketData]];
        }
    }
}

-(BOOL)isTimeToSendPsiTables:(uint64_t)nowMs
{
    const uint64_t msElapsedSinceLastPSI = nowMs - self.psiSendTimeMs;
    const BOOL isTimeToSendPSI = self.psiSendTimeMs == 0 || msElapsedSinceLastPSI >= _settings.psiIntervalMs;
    return isTimeToSendPSI;
}

-(uint64_t)maybeGetPcr:(const TSAccessUnit *)accessUnit
{
    if (self.pcrPid != accessUnit.pid) {
        return 0;
    }
    static const double pcrIntervalSeconds = 0.04;
    
    const BOOL hasSentPcr = CMTIME_IS_VALID(self.firstSentPcr);
    const Float64 secondsElapsedSinceLastPcr = CMTimeGetSeconds(accessUnit.pts) - CMTimeGetSeconds(self.lastSentPcr);
    const BOOL isTimeToSendPcr = !hasSentPcr || secondsElapsedSinceLastPcr >= pcrIntervalSeconds;
    if (!isTimeToSendPcr) {
        return 0;
    }
    if (!hasSentPcr) {
        self.firstSentPcr = accessUnit.pts;
    }
    const Float64 secondsElapsedSinceFirstPcr = CMTimeGetSeconds(accessUnit.pts) - CMTimeGetSeconds(self.firstSentPcr);
    const uint64_t pcr = secondsElapsedSinceFirstPcr * TS_TIMESTAMP_TIMESCALE;
    
    self.lastSentPcr = accessUnit.pts;
    return pcr;
}

@end
