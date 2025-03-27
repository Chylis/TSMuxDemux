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

#pragma mark - TSMuxerSettings

#define DEFAULT_PSI_INTERVAL_MS 250
#define DEFAULT_PROGRAM1_PMT 0x1000 // 4096

@implementation TSMuxerSettings

-(instancetype)init
{
    self = [super init];
    if (self) {
        // Initalize defaults
        _pmtPid = DEFAULT_PROGRAM1_PMT;
        _psiIntervalMs = DEFAULT_PSI_INTERVAL_MS;
    }
    return self;
}

-(instancetype)copyWithZone:(NSZone *)zone
{
    TSMuxerSettings *copy = [[self class] allocWithZone:zone];
    copy.pmtPid = self.pmtPid;
    copy.psiIntervalMs = self.psiIntervalMs;
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

@end

@implementation TSMuxer

@synthesize settings = _settings;

-(instancetype _Nonnull)initWithSettings:(TSMuxerSettings * _Nonnull)settings
                                delegate:(id<TSMuxerDelegate> _Nullable)delegate
{
    // Validate input settings
    if ([PidUtil isCustomPidInvalid:settings.pmtPid]) {
        [NSException raise:@"TSMuxerInvalidPidException" format:@"PMT Pid is reserved/out of valid range"];
    }
    
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
    }
    
    return self;
}

-(TSMuxerSettings*)settings
{
    return [_settings copy];
}

-(void)setSettings:(TSMuxerSettings * _Nonnull)settings
{
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
    if ([PidUtil isCustomPidInvalid:accessUnit.pid] || accessUnit.pid == _settings.pmtPid) {
        [NSException raise:@"TSMuxerInvalidPidException" format:@"Pid is reserved/occupied/out of valid range"];
    }
    
    BOOL hasSetPcrPid = self.pcrPid != 0;
    if (!hasSetPcrPid && [accessUnit isVideoStreamType]) {
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
    
    [self doMux];
}

-(void)doMux
{
    OnTsPacketDataCallback onTsPacketCb = ^(NSData *tsPacketData) {
        [self.delegate muxer:self didMuxTSPacketData:tsPacketData];
    };
    
    while (self.accessUnits.count) {
        const uint64_t nowMs = [TSTimeUtil nowHostTimeNanos] / 1000000;
        
        if ([self isTimeToSendPsiTables:nowMs]) {
            [TSPacket packetizePayload:[self.pat toTsPacketPayload]
                                 track:self.patTrack
                             forcePusi:YES
                               pcrBase:0
                                pcrExt:0
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
                            onTsPacketData:onTsPacketCb];
            }
            
            //NSLog(@"Sent PSI");
            self.psiSendTimeMs = nowMs;
        }
        
        
        const TSAccessUnit *accessUnit = self.accessUnits[0];
        [self.accessUnits removeObjectAtIndex:0];
        
        
        NSData *pesPacket = [accessUnit toTsPacketPayload];
        TSElementaryStream *track = [self elementaryStreamWithPid:accessUnit.pid];
        
        uint64_t pcr = [self maybeGetPcr:accessUnit];
        [TSPacket packetizePayload:pesPacket track:track forcePusi:NO pcrBase:pcr pcrExt:0 onTsPacketData:onTsPacketCb];
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
    static const NSUInteger pcrIntervalSeconds = 0.04;
    
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
