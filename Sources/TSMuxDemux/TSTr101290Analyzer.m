//
//  TSTr101290Analyzer.m
//  
//
//  Created by Magnus Eriksson on 2023-03-01.
//

#import "TSTr101290Analyzer.h"
#import "TSTr101290Statistics.h"
#import "TSConstants.h"
#import "TSProgramAssociationTable.h"
#import "TSProgramMapTable.h"
#import "TSPacket.h"
#import "TSTimeUtil.h"

#pragma mark - TSContinuityCounter

@interface TSContinuityCounter: NSObject
-(NSString* _Nullable)validateContinuityCounter:(TSPacket* _Nonnull)currentPacket;
@end

@implementation TSContinuityCounter
{
    TSPacket *mLastPacket; // FIXME MG <-- Only save CC, not entire packet.
    TSPacket *mSecondLastPacket;
}

-(NSString* _Nullable)validateContinuityCounter:(TSPacket* _Nonnull)currentPacket
{
    NSString *error = [self validateContinuityCounter:currentPacket
                                                         lastPacket:mLastPacket
                                                   secondLastPacket:mSecondLastPacket];
    if (error) {
        //NSLog(@"CC error for pid '%u' ('%@'): got '%u', expected '%u'. %@", self.pid, [TSAccessUnit streamTypeDescription:self.streamType], ccError.receivedCC, ccError.expectedCC, ccError.message);
    }
    
    // Start over on discontinuity
    mSecondLastPacket = currentPacket.adaptationField.discontinuityFlag ? nil : mLastPacket;
    mLastPacket = currentPacket;
    
    return error;
}


-(NSString* _Nullable)validateContinuityCounter:(TSPacket*)currentPacket
                                                   lastPacket:(TSPacket*)lastPacket
                                             secondLastPacket:(TSPacket*)secondLastPacket
{
    if (!lastPacket || currentPacket.adaptationField.discontinuityFlag) {
        // The continuity counter may be discontinuous when the discontinuity_indicator is set to '1' (refer to 2.4.3.4).
        return nil;
    }
    
    // The continuity_counter shall not be incremented when the adaptation_field_control of the packet equals '00' or '10'.
    BOOL isExpectingIncrementedCC =
    currentPacket.header.adaptationMode != TSAdaptationModeReserved &&
    currentPacket.header.adaptationMode != TSAdaptationModeAdaptationOnly;
    BOOL isDuplicate = currentPacket.header.continuityCounter == lastPacket.header.continuityCounter;
    uint8_t nextExpectedCc = [self nextContinuityCounter:lastPacket.header.continuityCounter];
    
    if (isExpectingIncrementedCC && currentPacket.header.continuityCounter != nextExpectedCc) {
        BOOL tooManyDuplicates = secondLastPacket.header.continuityCounter == lastPacket.header.continuityCounter;
        if (!isDuplicate) {
            return [NSString stringWithFormat:@"Got %u but expected incremented (%u) or duplicate CC (%u)",
                    currentPacket.header.continuityCounter,
                    nextExpectedCc,
                    lastPacket.header.continuityCounter
            ];
        } else if (tooManyDuplicates) {
            return [NSString stringWithFormat:@"Too many packets (>= 3) with same CC (%u)", currentPacket.header.continuityCounter];
        }
    } else if (!isExpectingIncrementedCC && !isDuplicate) {
        return [NSString stringWithFormat:@"Got %u but expected duplicate/not-incremented CC (%u)",
                currentPacket.header.continuityCounter,
                lastPacket.header.continuityCounter
        ];
    }
    return nil;
}

-(uint8_t)nextContinuityCounter:(uint8_t)currentContinuityCounter
{
    static const NSUInteger MAX_VALUE = 16;
    return (currentContinuityCounter + 1) % MAX_VALUE;
}

@end


#pragma mark - TSTr101290Analyzer

@implementation TSTr101290Analyzer
{
    uint64_t mNumConsecutiveSyncBytes;
    uint64_t mNumConsecutiveCorruptedSyncBytes;
    
    // Key = pid,
    // Value = timestamp describing when the pid was last encountered
    NSMutableDictionary<NSNumber*, NSNumber*> * _Nonnull mPidLastSeenMsMap;
    
    // Key = pid,
    // Value = timestamp describing when a pid-last-seen-too-long-ago error was last reported
    NSMutableDictionary<NSNumber*, NSNumber*> * _Nonnull mPidLastReportedIntervalErrorMsMap;
    
    // Key = pid
    // Value = cc counter
    NSMutableDictionary<NSNumber*, TSContinuityCounter*> * _Nonnull mPidCcValidatorMap;
}

-(instancetype)init
{
    self = [super init];
    if (self) {
        _stats = [TSTr101290Statistics new];
        mNumConsecutiveSyncBytes = 0;
        mNumConsecutiveCorruptedSyncBytes = 0;
        mPidLastSeenMsMap = [NSMutableDictionary dictionary];
        mPidLastReportedIntervalErrorMsMap = [NSMutableDictionary dictionary];
        mPidCcValidatorMap = [NSMutableDictionary dictionary];
    }
    return self;
}

-(void)analyzeTsPacket:(TSPacket* _Nonnull)tsPacket
                   pat:(TSProgramAssociationTable* _Nullable)pat
                   pmt:(TSProgramMapTable* _Nullable)pmt
     dataArrivalTimeMs:(uint64_t)dataArrivalTimeMs
{
    [self performPrio1Analysis:tsPacket pat:pat pmt:pmt dataArrivalTimeMs:dataArrivalTimeMs];
}

-(void)performPrio1Analysis:(TSPacket* _Nonnull)tsPacket
                        pat:(TSProgramAssociationTable* _Nullable)pat
                        pmt:(TSProgramMapTable* _Nullable)pmt
          dataArrivalTimeMs:(uint64_t)dataArrivalTimeMs
{
    [self checkTsSyncLoss:tsPacket];
    
    if (tsPacket.header.pid == PID_NULL_PACKET) {
        // Don't analyze null packets
        return;
    }
    if ([self isSyncAcquired]) {
        // After synchronization has been achieved the evaluation of the other parameters can be carried out.
        [self checkSyncByteError:tsPacket];
        [self checkPatError:tsPacket pat:pat nowMs:dataArrivalTimeMs];
        [self checkPmtError:tsPacket pat:pat pmt:pmt nowMs:dataArrivalTimeMs];
        [self checkCcError:tsPacket];
        [self checkPidError:tsPacket nowMs:dataArrivalTimeMs];
        
        mPidLastSeenMsMap[@(tsPacket.header.pid)] = @(dataArrivalTimeMs);
    }
}

-(void)checkTsSyncLoss:(TSPacket* _Nonnull)tsPacket
{
    BOOL isValidSyncByte = tsPacket.header.syncByte == TS_PACKET_HEADER_SYNC_BYTE;
    if (isValidSyncByte) {
        mNumConsecutiveSyncBytes++;
        mNumConsecutiveCorruptedSyncBytes = 0;
    } else {
        mNumConsecutiveSyncBytes = 0;
        mNumConsecutiveCorruptedSyncBytes++;
        if (mNumConsecutiveCorruptedSyncBytes >= 2) {
            _stats.prio1.tsSyncLoss++;
        }
    }
}

-(BOOL)isSyncAcquired
{
    return mNumConsecutiveSyncBytes >= 5;
}

-(void)checkSyncByteError:(TSPacket * _Nonnull)tsPacket
{
    BOOL isValidSyncByte = tsPacket.header.syncByte == TS_PACKET_HEADER_SYNC_BYTE;
    if (!isValidSyncByte) {
        _stats.prio1.syncByteError++;
    }
}

-(void)checkPatError:(TSPacket * _Nonnull)tsPacket
                 pat:(TSProgramAssociationTable * _Nullable) pat
               nowMs:(uint64_t)nowMs
{
    NSNumber *patPid = @(PID_PAT);
    uint64_t thresholdMs = 500;
    if ([self wasPidSeenTooLongAgo:patPid nowMs:nowMs thresholdMs:thresholdMs] &&
        [self wasPidIntervalErrorReportedTooLongAgo:patPid nowMs:nowMs thresholdMs:thresholdMs]) { // Only report once per 'thresholdMs'
        _stats.prio1.patError++;
        mPidLastReportedIntervalErrorMsMap[patPid] = @(nowMs);
        //NSLog(@"PID 0x0000 does not occur at least every 0,5 s");
    }
    if (pat) {
        if (pat.psi.tableId != TABLE_ID_PAT) {
            _stats.prio1.patError++;
            //NSLog(@"a PID 0x0000 does not contain a table_id 0x00 (i.e. a PAT)");
        } else if (tsPacket.header.isScrambled) {
            _stats.prio1.patError++;
            //NSLog(@"Scrambling_control_field is not 00 for PID 0x0000");
        }
    }
}

-(void)checkCcError:(TSPacket * _Nonnull)tsPacket
{
    NSNumber *key = @(tsPacket.header.pid);
    TSContinuityCounter *validator = mPidCcValidatorMap[key];
    if (!validator) {
        validator = [TSContinuityCounter new];
        mPidCcValidatorMap[key] = validator;
    }
    
    NSString *error = [validator validateContinuityCounter:tsPacket];
    if (error) {
        _stats.prio1.ccError++;
        //NSLog(@"%@", error);
    }
}

-(void)checkPmtError:(TSPacket* _Nonnull)tsPacket
                 pat:(TSProgramAssociationTable* _Nullable)pat
                 pmt:(TSProgramMapTable* _Nullable)pmt
               nowMs:(uint64_t)nowMs
{
    if (pat) {
        uint64_t thresholdMs = 500;
        for (NSNumber *pmtPid in pat.programmes.allValues) {
            // for each PMT in PAT: ensure it has been seen within last 500ms
            if ([self wasPidSeenTooLongAgo:pmtPid nowMs:nowMs thresholdMs:thresholdMs] &&
                [self wasPidIntervalErrorReportedTooLongAgo:pmtPid nowMs:nowMs thresholdMs:thresholdMs]) { // Only report once every 'thresholdMs'
                _stats.prio1.pmtError++;
                mPidLastReportedIntervalErrorMsMap[pmtPid] = @(nowMs);
                //NSLog(@"Sections with table_id 0x02, do not occur at least every 0,5 s on the PID which is referred to in the PAT");
            }
        }
    }
    if (pmt) {
        if (tsPacket.header.isScrambled) {
            _stats.prio1.pmtError++;
            //NSLog(@"Scrambling_control_field is not 00 for all PIDs containing sections with table_id 0x02"@"Scrambling_control_field is not 00 for all PIDs containing sections with table_id 0x02");
        }
    }
}

-(void)checkPidError:(TSPacket * _Nonnull)tsPacket nowMs:(uint64_t)nowMs
{
    /*
     It is checked whether there exists a data stream for each PID that occurs.
     The user specified period should not exceed 5s for video or audio PIDs (see note).
     Data services and audio services with ISO 639 [i.17] language descriptor with type greater than '0' should be excluded from this 5 s limit.
     
     FIXME: For PIDs carrying other information such as sub-titles, data services or audio services with ISO 639 [i.17] language descriptor with type greater than '0', the time between two consecutive packets of the same PID may be significantly longer. In principle, a different user specified period could be defined for each PID.
     */
    NSNumber *lastSeen = mPidLastSeenMsMap[@(tsPacket.header.pid)];
    if (lastSeen != nil) {
        uint64_t lastSeenMs = lastSeen.unsignedLongLongValue;
        uint64_t elapsedMs = nowMs - lastSeenMs;
        BOOL hasElapsed5SecondsSincePidLastSeen = elapsedMs > 5000;
        if (hasElapsed5SecondsSincePidLastSeen) {
            _stats.prio1.pidError++;
            //NSLog(@"PID %u was seen %llu ms ago (which is over 5s).", tsPacket.header.pid, elapsedMs);
        }
    }
}

-(BOOL)wasPidSeenTooLongAgo:(NSNumber* _Nonnull)pid nowMs:(uint64_t)nowMs thresholdMs:(uint64_t)thresholdMs
{
    NSNumber *lastSeen = mPidLastSeenMsMap[pid];
    BOOL isFirstTime = !lastSeen;
    if (isFirstTime) {
        return NO;
    }
    
    uint64_t lastSeenMs = lastSeen.unsignedLongLongValue;
    uint64_t elapsedMs = (nowMs - lastSeenMs);
    BOOL hasElapsedTooLongSinceLastSeen = elapsedMs > thresholdMs;
    return hasElapsedTooLongSinceLastSeen;
}

-(BOOL)wasPidIntervalErrorReportedTooLongAgo:(NSNumber* _Nonnull)pid nowMs:(uint64_t)nowMs thresholdMs:(uint64_t)thresholdMs
{
    NSNumber *lastReported = mPidLastReportedIntervalErrorMsMap[pid];
    BOOL neverReported = !lastReported;
    if (neverReported) {
        return YES;
    }
    BOOL hasElapsedTooLongSinceLastReportedError = (nowMs - lastReported.unsignedLongLongValue) > thresholdMs;
    return hasElapsedTooLongSinceLastReportedError;
}
@end

