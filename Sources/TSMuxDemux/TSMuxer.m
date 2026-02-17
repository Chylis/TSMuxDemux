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
#import "TSLog.h"

#pragma mark - TSMuxerSettings

#define MAX_TARGET_BITRATE_KBPS 60000 // safety net
#define STATS_LOG_INTERVAL_MS 10000

@implementation TSMuxerSettings

-(instancetype)copyWithZone:(NSZone *)zone
{
    TSMuxerSettings *copy = [[self class] allocWithZone:zone];
    copy.pmtPid = self.pmtPid;
    copy.pcrPid = self.pcrPid;
    copy.videoPid = self.videoPid;
    copy.audioPid = self.audioPid;
    copy.psiIntervalMs = self.psiIntervalMs;
    copy.pcrIntervalMs = self.pcrIntervalMs;
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

static const uint64_t kNeverSent = UINT64_MAX;


/// PCR state.
/// Value: transport-time-driven (virtual in CBR, wall-clock in VBR).
///        Per ISO 13818-1 §2.4.2.1, the PCR represents the STC at byte-arrival at the decoder,
///        which in a CBR stream is determined by byte position, not the encoder wall clock.
/// Interval: transport-time-driven per ISO 13818-1.
typedef struct {
    /// PID carrying the PCR for program 1.
    uint16_t pid;
    /// Time when the last PCR was emitted. kNeverSent = not yet emitted.
    uint64_t lastEmissionTimeNanos;
    /// Time when the first AU was processed — the PCR=0 anchor point. 0 = not yet set.
    uint64_t pcrAnchorNanos;
    /// CC of the last emitted packet on this PID. Updated by emitPacket:.
    uint8_t lastEmittedCc;
} TSPcrState;

/// A packetized TS packet with metadata extracted at creation time,
/// so consumers don't need to parse the raw bytes.
@interface TSPacketizedPacket : NSObject
@property(nonatomic, readonly, nonnull) NSData *data;
@property(nonatomic, readonly) uint16_t pid;
@property(nonatomic, readonly) uint8_t cc;
+(instancetype _Nonnull)packetWithData:(NSData * _Nonnull)data pid:(uint16_t)pid cc:(uint8_t)cc;
@end

@implementation TSPacketizedPacket
+(instancetype)packetWithData:(NSData *)data pid:(uint16_t)pid cc:(uint8_t)cc {
    TSPacketizedPacket *p = [[TSPacketizedPacket alloc] init];
    p->_data = data;
    p->_pid = pid;
    p->_cc = cc;
    return p;
}
@end

@interface TSMuxer() {
    TSPcrState _pcr;
    /// DTS/PTS of the first access unit — subtracted from all DTS/PTS so that timestamps
    /// start from zero, aligning them with the PCR clock (which also starts from zero).
    CMTime _ptsAnchor;
}

@property(nonatomic, readonly, nonnull) TSProgramAssociationTable *pat;
@property(nonatomic, readonly, nonnull) TSElementaryStream *patTrack;

@property(nonatomic, readonly, nonnull) TSElementaryStream *pmtTrack;
@property(nonatomic, readonly, nonnull) NSMutableArray<TSAccessUnit*> *accessUnits;

@property(nonatomic) uint8_t versionNumber;
@property(nonatomic, readonly, nonnull) NSSet<TSElementaryStream*> *elementaryStreams;

/// Transport time when the program specific information was last sent.
/// Shared by PAT and PMT since this is a single-program muxer — they're always emitted as a pair.
@property(nonatomic) uint64_t psiSendTimeNanos;

/// CBR state
@property(nonatomic) uint64_t numTsPacketsEmitted;
@property(nonatomic) uint64_t startTimeWallClockNanos;

/// TS packets waiting to be paced out at the CBR rate. Contains packets from at most
/// one AU at a time (single PID) — fully drained before the next AU is packetized.
@property(nonatomic, readonly, nonnull) NSMutableArray<TSPacketizedPacket*> *pendingTsPackets;

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
        [NSException raise:@"TSMuxerInvalidPidException" format:@"PMT PID is reserved/out of valid range"];
    }
    if ([TSPidUtil isCustomPidInvalid:settings.pcrPid]) {
        [NSException raise:@"TSMuxerInvalidPidException" format:@"PCR PID is reserved/out of valid range"];
    }
    if ([TSPidUtil isCustomPidInvalid:settings.videoPid]) {
        [NSException raise:@"TSMuxerInvalidPidException" format:@"Video PID is reserved/out of valid range"];
    }
    if ([TSPidUtil isCustomPidInvalid:settings.audioPid]) {
        [NSException raise:@"TSMuxerInvalidPidException" format:@"Audio PID is reserved/out of valid range"];
    }
    if (settings.pmtPid == settings.pcrPid) {
        [NSException raise:@"TSMuxerInvalidPidException" format:@"PMT PID and PCR PID must not be the same"];
    }
    if (settings.audioPid == settings.videoPid) {
        [NSException raise:@"TSMuxerInvalidPidException" format:@"Audio PID and Video PID must not be the same"];
    }
    if (settings.audioPid == settings.pmtPid || settings.videoPid == settings.pmtPid) {
        [NSException raise:@"TSMuxerInvalidPidException" format:@"Audio/Video PIDs must not be the same as PMT PID"];
    }
    if (settings.psiIntervalMs == 0) {
        [NSException raise:@"TSMuxerInvalidSettingsException" format:@"PSI interval must be > 0"];
    }
    if (settings.pcrIntervalMs == 0) {
        [NSException raise:@"TSMuxerInvalidSettingsException" format:@"PCR interval must be > 0"];
    }
    if (settings.targetBitrateKbps > MAX_TARGET_BITRATE_KBPS) {
        [NSException raise:@"TSMuxerInvalidSettingsException" format:@"Target bitrate must be <= %d kbps", MAX_TARGET_BITRATE_KBPS];
    }
}

-(instancetype _Nonnull)initWithSettings:(TSMuxerSettings * _Nonnull)settings
                          wallClockNanos:(uint64_t (^ _Nonnull)(void))wallClockNanos
                                delegate:(id<TSMuxerDelegate> _Nullable)delegate
{
    self = [super init];
    if (self) {
        self.settings = settings;
        self.delegate = delegate;
        self.psiSendTimeNanos = kNeverSent;
        
        const uint8_t streamTypeNotApplicable = 0;
        _pat = [[TSProgramAssociationTable alloc] initWithTransportStreamId:0
                                                                 programmes:@{ @(PROGRAM_NUMBER): @(_settings.pmtPid)}];
        _patTrack = [[TSElementaryStream alloc] initWithPid:PID_PAT
                                                 streamType:streamTypeNotApplicable
                                                descriptors:nil];
        
        _pmtTrack = [[TSElementaryStream alloc] initWithPid:settings.pmtPid
                                                 streamType:streamTypeNotApplicable
                                                descriptors:nil];
        
        _pcr = (TSPcrState){ .pid = _settings.pcrPid, .lastEmissionTimeNanos = kNeverSent };
        _ptsAnchor = kCMTimeInvalid;
        _versionNumber = 0;
        _elementaryStreams = [NSSet set];
        _accessUnits = [NSMutableArray array];
        _pendingTsPackets = [NSMutableArray array];
        _discontinuousPids = [NSMutableSet set];
        _wallClockNanos = [wallClockNanos copy];
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

-(void)enqueueAccessUnit:(TSAccessUnit *)accessUnit
{
    if ([TSPidUtil isCustomPidInvalid:accessUnit.pid] || accessUnit.pid == _settings.pmtPid) {
        [NSException raise:@"TSMuxerInvalidPidException" format:@"Pid is reserved/occupied/out of valid range"];
    }
    
    TSElementaryStream *track = [self elementaryStreamWithPid:accessUnit.pid];
    if (!track) {
        track = [[TSElementaryStream alloc] initWithPid:accessUnit.pid
                                             streamType:accessUnit.streamType
                                            descriptors:accessUnit.descriptors];
        [self addElementaryStream:track];
    }
    
    // Drop oldest access unit during backpressure to make room
    if (_settings.maxNumQueuedAccessUnits > 0 && self.accessUnits.count >= _settings.maxNumQueuedAccessUnits) {
        TSAccessUnit *dropped = self.accessUnits[0];
        [self.accessUnits removeObjectAtIndex:0];
        [self.discontinuousPids addObject:@(dropped.pid)];
        self.statsDroppedAccessUnitCount++;
        TSLogWarn(@"Queue overflow: dropped oldest access unit (PID: %u)", dropped.pid);
    }
    
    // Insert in DTS order (PTS fallback) for correct cross-stream interleaving.
    // Scan from the end since AUs typically arrive in near-order.
    CMTime auTime = CMTIME_IS_VALID(accessUnit.dts) ? accessUnit.dts : accessUnit.pts;
    NSUInteger insertIndex = self.accessUnits.count;
    if (CMTIME_IS_VALID(auTime)) {
        while (insertIndex > 0) {
            TSAccessUnit *existing = self.accessUnits[insertIndex - 1];
            CMTime existingTime = CMTIME_IS_VALID(existing.dts) ? existing.dts : existing.pts;
            if (!CMTIME_IS_VALID(existingTime) || CMTimeCompare(existingTime, auTime) <= 0) {
                break;
            }
            insertIndex--;
        }
    }
    [self.accessUnits insertObject:accessUnit atIndex:insertIndex];
    self.statsAccessUnitCount++;
}

-(void)tick
{
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
    const uint64_t nowMs = self.wallClockNanos() / 1000000;
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


static inline BOOL isIntervalElapsed(uint64_t lastTimeNanos, uint64_t intervalNanos, uint64_t nowNanos)
{
    return lastTimeNanos == kNeverSent || (nowNanos - lastTimeNanos) >= intervalNanos;
}

-(void)packetizePsiTables:(OnTsPacketDataCallback)onTsPacketCb
{
    [TSPacket packetizePayload:[self.pat toTsPacketPayload]
                         track:self.patTrack
                       pcrBase:kNoPcr
                        pcrExt:0
             discontinuityFlag:NO
              randomAccessFlag:NO
                onTsPacketData:onTsPacketCb];

    TSProgramMapTable *pmt = [[TSProgramMapTable alloc] initWithProgramNumber:PROGRAM_NUMBER
                                                                versionNumber:self.versionNumber
                                                                       pcrPid:_pcr.pid
                                                            elementaryStreams:self.elementaryStreams];
    [TSPacket packetizePayload:[pmt toTsPacketPayload]
                         track:self.pmtTrack
                       pcrBase:kNoPcr
                        pcrExt:0
             discontinuityFlag:NO
              randomAccessFlag:NO
                onTsPacketData:onTsPacketCb];
}

-(NSMutableArray<TSPacketizedPacket*>*)packetizeAccessUnit:(TSAccessUnit *)accessUnit
                                                  nowNanos:(uint64_t)nowNanos
{
    if (CMTIME_IS_INVALID(_ptsAnchor)) {
        const CMTime candidate = CMTIME_IS_VALID(accessUnit.dts) ? accessUnit.dts : accessUnit.pts;
        if (CMTIME_IS_VALID(candidate)) {
            _ptsAnchor = candidate;
            _pcr.pcrAnchorNanos = nowNanos;
        }
    }

    NSNumber *pidKey = @(accessUnit.pid);
    BOOL discontinuity = [self.discontinuousPids containsObject:pidKey];
    if (discontinuity) {
        [self.discontinuousPids removeObject:pidKey];
    }

    NSData *pesPacket = [accessUnit toTsPacketPayloadWithEpoch:_ptsAnchor];
    TSElementaryStream *track = [self elementaryStreamWithPid:accessUnit.pid];

    uint64_t pcrBase = kNoPcr;
    uint16_t pcrExt = 0;
    if (accessUnit.pid == _pcr.pid && [self isTimeToSendPcr:nowNanos]) {
        [self calculatePcr:nowNanos base:&pcrBase ext:&pcrExt];
        _pcr.lastEmissionTimeNanos = nowNanos;
    }

    NSMutableArray<TSPacketizedPacket*> *packets = [NSMutableArray array];
    [TSPacket packetizePayload:pesPacket
                         track:track
                       pcrBase:pcrBase
                        pcrExt:pcrExt
             discontinuityFlag:discontinuity
              randomAccessFlag:accessUnit.isRandomAccessPoint
                onTsPacketData:^(NSData *tsPacketData, uint16_t pid, uint8_t cc) {
        [packets addObject:[TSPacketizedPacket packetWithData:tsPacketData pid:pid cc:cc]];
    }];
    return packets;
}


-(BOOL)isTimeToSendPsiTables:(uint64_t)nowNanos
{
    return isIntervalElapsed(self.psiSendTimeNanos, _settings.psiIntervalMs * 1000000ULL, nowNanos);
}

-(void)emitPacket:(TSPacketizedPacket *)packet
{
    self.numTsPacketsEmitted++;
    self.statsTsPacketCount++;
    if (packet.pid == _pcr.pid) {
        _pcr.lastEmittedCc = packet.cc;
    }
    [self.delegate muxer:self didMuxTSPacketData:packet.data];
}

#pragma mark - VBR
// enqueueAccessUnit: → accessUnits; tick → packetize → delegate (immediate, no pacing)

-(void)doMuxVBR
{
    do {
        const uint64_t nowNanos = self.wallClockNanos();
        
        if ([self isTimeToSendPsiTables:nowNanos]) {
            [self packetizePsiTables:^(NSData *tsPacketData, uint16_t pid, uint8_t cc) {
                [self emitPacket:[TSPacketizedPacket packetWithData:tsPacketData pid:pid cc:cc]];
            }];
            self.psiSendTimeNanos = nowNanos;
        }

        if (self.accessUnits.count) {
            TSAccessUnit *au = self.accessUnits[0];
            [self.accessUnits removeObjectAtIndex:0];
            for (TSPacketizedPacket *packet in [self packetizeAccessUnit:au nowNanos:nowNanos]) {
                [self emitPacket:packet];
            }
        }

        if ([self shouldSendStandalonePcr:nowNanos]) {
            const uint8_t cc = _pcr.lastEmittedCc;
            [self emitPacket:[TSPacketizedPacket packetWithData:[self packetizeStandalonePcr:nowNanos cc:cc]
                                                           pid:_pcr.pid
                                                            cc:cc]];
            _pcr.lastEmissionTimeNanos = nowNanos;
        }

    } while (self.accessUnits.count);
}


#pragma mark - CBR
// enqueueAccessUnit: → accessUnits; tick → packetize → pendingTsPackets → paced out one-by-one at targetBitrateKbps.
// PSI and PCR-only packets are emitted directly, not via pendingTsPackets.

/// Returns the number of TS packets that should have been emitted by `nowNanos`
/// to maintain the target CBR. On the very first call (elapsed ≈ 0) this returns 0,
/// so no packets are emitted until wall-clock time has actually passed.
-(uint64_t)expectedPacketCount:(uint64_t)nowNanos
{
    NSAssert(_settings.targetBitrateKbps > 0, @"expectedPacketCount requires CBR mode");
    const double elapsedSeconds = (double)(nowNanos - self.startTimeWallClockNanos) / 1e9;
    const double targetBytesPerSecond = (double)_settings.targetBitrateKbps * 1e3 / 8.0;
    const double targetPacketsPerSecond = targetBytesPerSecond / (double)TS_PACKET_SIZE_188;
    return (uint64_t)(targetPacketsPerSecond * elapsedSeconds);
}

/// Virtual stream time in nanoseconds, derived from packet count and target bitrate (in CBR, the byte counter is the clock.)
/// Represents the time a receiver would perceive when reading at the target CBR.
-(uint64_t)cbrNanosElapsed
{
    NSAssert(_settings.targetBitrateKbps > 0, @"cbrNanosElapsed requires CBR mode");
    const double totalBitsEmitted = self.numTsPacketsEmitted * TS_PACKET_SIZE_188 * 8.0;
    const double targetBitsPerSecond = (double)_settings.targetBitrateKbps * 1000.0;
    const double seconds = totalBitsEmitted / targetBitsPerSecond;
    return (uint64_t)(seconds * 1e9);
}

-(void)doMuxCBR
{
    const uint64_t wallClockTimeNs = self.wallClockNanos();
    if (self.startTimeWallClockNanos == 0) {
        self.startTimeWallClockNanos = wallClockTimeNs;
    }
    const uint64_t expectedNumTsPacketsEmitted = [self expectedPacketCount:wallClockTimeNs];
    
    // Paced output loop.
    // Each iteration emits one packet, except:
    // - PSI: emits 2 packets (PAT + PMT)
    // - packetizeAccessUnit: emits zero packets (enqueues into pendingTsPackets for subsequent iterations).
    while (self.numTsPacketsEmitted < expectedNumTsPacketsEmitted) {
        const uint64_t nowNanos = [self cbrNanosElapsed];
        
        if ([self isTimeToSendPsiTables:nowNanos]) {
            [self packetizePsiTables:^(NSData *tsPacketData, uint16_t pid, uint8_t cc) {
                [self emitPacket:[TSPacketizedPacket packetWithData:tsPacketData pid:pid cc:cc]];
            }];
            self.psiSendTimeNanos = nowNanos;
            continue;
        }

        if ([self shouldSendStandalonePcr:nowNanos]) {
            const uint8_t cc = _pcr.lastEmittedCc;
            [self emitPacket:[TSPacketizedPacket packetWithData:[self packetizeStandalonePcr:nowNanos cc:cc]
                                                           pid:_pcr.pid
                                                            cc:cc]];
            _pcr.lastEmissionTimeNanos = nowNanos;
            continue;
        }

        if (self.pendingTsPackets.count > 0) {
            TSPacketizedPacket *packet = self.pendingTsPackets[0];
            [self.pendingTsPackets removeObjectAtIndex:0];
            [self emitPacket:packet];
        } else if (self.accessUnits.count > 0) {
            // Packetize the next AU into pending TS packets (on demand, to limit memory) for subsequent iterations.
            TSAccessUnit *au = self.accessUnits[0];
            [self.accessUnits removeObjectAtIndex:0];
            _pendingTsPackets = [self packetizeAccessUnit:au nowNanos:nowNanos];
        } else {
            // No content available — null stuff to maintain CBR
            self.statsNullPacketCount++;
            [self emitPacket:[TSPacketizedPacket packetWithData:[TSPacket nullPacketData] pid:PID_NULL_PACKET cc:0]];
        }
    }
}

#pragma mark - PCR

/// Whether a standalone PCR should be emitted now.
/// Checks both timing (PCR interval elapsed) and readiness (payload must have been emitted on shared PIDs).
/// CC is always _pcr.lastEmittedCc (zero-initialized for dedicated PIDs, updated by emitPacket: for shared PIDs).
-(BOOL)shouldSendStandalonePcr:(uint64_t)nowNanos
{
    if (![self isTimeToSendPcr:nowNanos]) {
        return NO;
    }
    const BOOL isSharedPid = (_pcr.pid == _settings.videoPid || _pcr.pid == _settings.audioPid);
    if (isSharedPid && _pcr.lastEmissionTimeNanos == kNeverSent) {
        // PCR PID is shared with a payload stream but no AU has arrived on it yet.
        // Defer — the first AU on this PID will piggyback inline PCR.
        return NO;
    }
    return YES;
}

/// Whether the PCR interval has elapsed and a PCR should be emitted.
/// Deferred until the PCR  anchor (pcr time when first AU was processed) is established,
/// so that PCR=0 aligns with PTS=0 in the output stream.
-(BOOL)isTimeToSendPcr:(uint64_t)nowNanos
{
    if (_pcr.pcrAnchorNanos == 0) return NO;
    return isIntervalElapsed(_pcr.lastEmissionTimeNanos, _settings.pcrIntervalMs * 1000000ULL, nowNanos);
}

-(NSData * _Nonnull)packetizeStandalonePcr:(uint64_t)nowNanos cc:(uint8_t)cc
{
    uint64_t pcrBase;
    uint16_t pcrExt;
    [self calculatePcr:nowNanos base:&pcrBase ext:&pcrExt];

    return [TSPacket pcrPacketDataWithPid:_pcr.pid
                       continuityCounter:cc
                                 pcrBase:pcrBase
                                  pcrExt:pcrExt];
}

/// Computes PCR base (90 kHz, 33-bit) and extension (27 MHz remainder, 0-299)
/// from the transport time elapsed since the PCR epoch.
/// Transport time is virtual (byte-position-derived) in CBR, wall-clock in VBR.
-(void)calculatePcr:(uint64_t)nowNanos
               base:(uint64_t *)outBase
                ext:(uint16_t *)outExt
{
    const uint64_t elapsedNanos = nowNanos - _pcr.pcrAnchorNanos;
    // Convert nanoseconds to 27 MHz ticks: nanos * 27,000,000 / 1,000,000,000 = nanos * 27 / 1000.
    // Overflow safe for streams up to ~21 years.
    const uint64_t pcr27MHz = elapsedNanos * 27 / 1000;
    *outBase = (pcr27MHz / 300) & 0x1FFFFFFFFULL; // which 90 kHz tick (33-bits)
    *outExt  = pcr27MHz % 300;                     // where (0-299) within that tick
}

@end
