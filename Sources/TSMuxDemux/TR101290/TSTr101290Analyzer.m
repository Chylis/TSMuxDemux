//
//  TSTr101290Analyzer.m
//  
//
//  Created by Magnus Eriksson on 2023-03-01.
//

#import "TSTr101290Analyzer.h"
#import "TSTr101290AnalyzeContext.h"
#import "TSTr101290CompletedSection.h"
#import "TSTr101290Statistics.h"
#import "../TSConstants.h"
#import "../Table/TSProgramAssociationTable.h"
#import "../Table/TSProgramMapTable.h"
#import "../Table/TSProgramSpecificInformationTable.h"
#import "../TSPacket.h"
#import "../TSElementaryStream.h"
#import "../Descriptor/TSISO639LanguageDescriptor.h"

#pragma mark - TSContinuityCounter

@interface TSContinuityCounter: NSObject
-(NSString* _Nullable)validateContinuityCounter:(TSPacket* _Nonnull)currentPacket;
@end

@implementation TSContinuityCounter
{
    BOOL mHasLastCC;
    BOOL mHasSecondLastCC;
    uint8_t mLastCC;
    uint8_t mSecondLastCC;
}

-(NSString* _Nullable)validateContinuityCounter:(TSPacket* _Nonnull)currentPacket
{
    NSString *error = [self validateCurrentPacket:currentPacket];

    // Start over on discontinuity
    if (currentPacket.adaptationField.discontinuityFlag) {
        mHasSecondLastCC = NO;
    } else {
        mHasSecondLastCC = mHasLastCC;
        mSecondLastCC = mLastCC;
    }
    mHasLastCC = YES;
    mLastCC = currentPacket.header.continuityCounter;

    return error;
}

-(NSString* _Nullable)validateCurrentPacket:(TSPacket*)currentPacket
{
    if (!mHasLastCC || currentPacket.adaptationField.discontinuityFlag) {
        // The continuity counter may be discontinuous when the discontinuity_indicator is set to '1' (refer to 2.4.3.4).
        return nil;
    }

    // The continuity_counter shall not be incremented when the adaptation_field_control of the packet equals '00' or '10'.
    BOOL isExpectingIncrementedCC =
        currentPacket.header.adaptationMode != TSAdaptationModeReserved &&
        currentPacket.header.adaptationMode != TSAdaptationModeAdaptationOnly;
    BOOL isDuplicate = currentPacket.header.continuityCounter == mLastCC;
    uint8_t nextExpectedCc = [self nextContinuityCounter:mLastCC];

    if (isExpectingIncrementedCC && currentPacket.header.continuityCounter != nextExpectedCc) {
        BOOL tooManyDuplicates = mHasSecondLastCC && mSecondLastCC == mLastCC;
        if (!isDuplicate) {
            return [NSString stringWithFormat:@"Got %u but expected incremented (%u) or duplicate CC (%u)",
                    currentPacket.header.continuityCounter,
                    nextExpectedCc,
                    mLastCC
            ];
        } else if (tooManyDuplicates) {
            return [NSString stringWithFormat:@"Too many packets (>= 3) with same CC (%u)", currentPacket.header.continuityCounter];
        }
    } else if (!isExpectingIncrementedCC && !isDuplicate) {
        return [NSString stringWithFormat:@"Got %u but expected duplicate/not-incremented CC (%u)",
                currentPacket.header.continuityCounter,
                mLastCC
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

    // Key = pid, Value = timestamp when a valid section was last completed on this PID
    // For PAT: tracks when tableId 0x00 was last seen on PID 0x0000
    // For PMT: tracks when tableId 0x02 was last seen on each PMT PID
    NSMutableDictionary<NSNumber*, NSNumber*> * _Nonnull mSectionLastSeenMsMap;

    // Key = pid, Value = timestamp when interval error was last reported (to avoid flooding)
    NSMutableDictionary<NSNumber*, NSNumber*> * _Nonnull mIntervalErrorLastReportedMsMap;

    // Key = pid, Value = timestamp when this PID was last seen (for PID error check)
    NSMutableDictionary<NSNumber*, NSNumber*> * _Nonnull mPidLastSeenMsMap;

    // Key = pid, Value = cc validator
    NSMutableDictionary<NSNumber*, TSContinuityCounter*> * _Nonnull mPidCcValidatorMap;

    // Timestamp of last interval check (throttle to every 200ms for efficiency)
    uint64_t mLastIntervalCheckMs;
}

-(instancetype)init
{
    self = [super init];
    if (self) {
        _stats = [TSTr101290Statistics new];
        mNumConsecutiveSyncBytes = 0;
        mNumConsecutiveCorruptedSyncBytes = 0;
        mSectionLastSeenMsMap = [NSMutableDictionary dictionary];
        mIntervalErrorLastReportedMsMap = [NSMutableDictionary dictionary];
        mPidLastSeenMsMap = [NSMutableDictionary dictionary];
        mPidCcValidatorMap = [NSMutableDictionary dictionary];
    }
    return self;
}

-(void)analyzeTsPacket:(TSPacket* _Nonnull)tsPacket
               context:(TSTr101290AnalyzeContext* _Nonnull)context
{
    [self performPrio1Analysis:tsPacket context:context];
}

-(void)performPrio1Analysis:(TSPacket* _Nonnull)tsPacket
                    context:(TSTr101290AnalyzeContext* _Nonnull)context
{
    [self checkTsSyncLoss:tsPacket];

    if (tsPacket.header.pid == PID_NULL_PACKET) {
        // Don't analyze null packets
        return;
    }
    if ([self isSyncAcquired]) {
        // After synchronization has been achieved the evaluation of the other parameters can be carried out.
        BOOL checkIntervalError = [self shouldRunIntervalCheck:context.nowMs];
        if (checkIntervalError) {
            mLastIntervalCheckMs = context.nowMs;
        }

        [self checkSyncByteError:tsPacket];
        [self checkPatError:tsPacket context:context checkIntervalError:checkIntervalError];
        [self checkPmtError:tsPacket context:context checkIntervalError:checkIntervalError];
        [self checkCcError:tsPacket];
        [self checkPidError:tsPacket context:context checkIntervalError:checkIntervalError];

        mPidLastSeenMsMap[@(tsPacket.header.pid)] = @(context.nowMs);
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
             context:(TSTr101290AnalyzeContext* _Nonnull)context
   checkIntervalError:(BOOL)checkIntervalError
{
    NSNumber *patPid = @(PID_PAT);

    // Check if any section was completed on PID 0x0000
    for (TSTr101290CompletedSection *completed in context.completedSections) {
        if (completed.pid == PID_PAT) {
            if (completed.section.tableId == TABLE_ID_PAT) {
                // Valid PAT section - update last seen time
                mSectionLastSeenMsMap[patPid] = @(context.nowMs);
            } else {
                // PAT error #2: Section with table_id other than 0x00 found on PID 0x0000
                _stats.prio1.patError++;
            }
        }
    }

    // PAT error #1: Sections with table_id 0x00 do not occur at least every 0,5 s on PID 0x0000
    if (checkIntervalError) {
        uint64_t thresholdMs = TR101290_PAT_PMT_INTERVAL_MS;
        if ([self wasSectionSeenTooLongAgo:patPid nowMs:context.nowMs thresholdMs:thresholdMs] &&
            [self wasIntervalErrorReportedTooLongAgo:patPid nowMs:context.nowMs thresholdMs:thresholdMs]) {
            _stats.prio1.patError++;
            mIntervalErrorLastReportedMsMap[patPid] = @(context.nowMs);
        }
    }

    // PAT error #3: Scrambling_control_field is not 00 for PID 0x0000
    if (tsPacket.header.pid == PID_PAT && tsPacket.header.isScrambled) {
        _stats.prio1.patError++;
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
    
    if ([validator validateContinuityCounter:tsPacket]) {
        _stats.prio1.ccError++;
    }
}

-(void)checkPmtError:(TSPacket* _Nonnull)tsPacket
             context:(TSTr101290AnalyzeContext* _Nonnull)context
   checkIntervalError:(BOOL)checkIntervalError
{
    if (!context.pat) {
        return;
    }

    // Per TR 101 290 1.5.a: only check program_map_PIDs, exclude network_PID
    NSMutableArray<NSNumber*> *pmtPids = [NSMutableArray array];
    [context.pat.programmes enumerateKeysAndObjectsUsingBlock:^(NSNumber *programNumber, NSNumber *pmtPid, BOOL *stop) {
        if (programNumber.unsignedShortValue != PROGRAM_NUMBER_NETWORK_INFO) {
            [pmtPids addObject:pmtPid];
        }
    }];

    // Check completed sections on PMT PIDs
    for (TSTr101290CompletedSection *completed in context.completedSections) {
        NSNumber *completedPid = @(completed.pid);
        if ([pmtPids containsObject:completedPid]) {
            if (completed.section.tableId == TABLE_ID_PMT) {
                // Valid PMT section - update last seen time for this PMT PID
                mSectionLastSeenMsMap[completedPid] = @(context.nowMs);
            }
        }
    }

    // PMT error #1: Sections with table_id 0x02 do not occur at least every 0,5 s on each PMT PID
    if (checkIntervalError) {
        uint64_t thresholdMs = TR101290_PAT_PMT_INTERVAL_MS;
        for (NSNumber *pmtPid in pmtPids) {
            if ([self wasSectionSeenTooLongAgo:pmtPid nowMs:context.nowMs thresholdMs:thresholdMs] &&
                [self wasIntervalErrorReportedTooLongAgo:pmtPid nowMs:context.nowMs thresholdMs:thresholdMs]) {
                _stats.prio1.pmtError++;
                mIntervalErrorLastReportedMsMap[pmtPid] = @(context.nowMs);
            }
        }
    }

    // PMT error #2 (TR 101 290 1.5.a): Scrambling_control_field is not 00 for all packets
    // containing information of sections with table_id 0x02 on each program_map_PID
    if (tsPacket.header.isScrambled && [pmtPids containsObject:@(tsPacket.header.pid)]) {
        _stats.prio1.pmtError++;
    }
}

-(void)checkPidError:(TSPacket * _Nonnull)tsPacket
             context:(TSTr101290AnalyzeContext* _Nonnull)context
   checkIntervalError:(BOOL)checkIntervalError
{
    /*
     TR 101 290: PID_error
     It is checked whether there exists a data stream for each PID that occurs.
     The user specified period should not exceed 5s for video or audio PIDs.
     Data services and audio services with ISO 639 [i.17] language descriptor
     with type greater than '0' should be excluded from this 5 s limit.
     */

    if (!checkIntervalError) {
        return;
    }

    // Check all known PMTs for elementary streams that should be monitored
    for (NSNumber *pmtPid in context.pmts) {
        TSProgramMapTable *pmt = context.pmts[pmtPid];

        for (TSElementaryStream *es in pmt.elementaryStreams) {
            // Only check video/audio PIDs
            if (![es isVideo] && ![es isAudio]) {
                continue;
            }

            // Skip PIDs excluded by ES filter (avoids false positive PID errors)
            if (context.esPidFilter.count > 0 && ![context.esPidFilter containsObject:@(es.pid)]) {
                continue;
            }

            // Exclude audio with ISO 639 audio_type > 0
            if ([self hasISO639AudioTypeGreaterThanZero:es]) {
                continue;
            }

            // Check 5-second threshold for this PID
            [self checkPidInterval:es.pid nowMs:context.nowMs];
        }
    }
}

-(BOOL)hasISO639AudioTypeGreaterThanZero:(TSElementaryStream*)es
{
    for (TSDescriptor *desc in es.descriptors) {
        if ([desc isKindOfClass:[TSISO639LanguageDescriptor class]]) {
            TSISO639LanguageDescriptor *langDesc = (TSISO639LanguageDescriptor*)desc;
            for (TSISO639LanguageDescriptorEntry *entry in langDesc.entries) {
                if (entry.audioType > TSISO639LanguageDescriptorAudioTypeUndefined) {
                    return YES;
                }
            }
        }
    }
    return NO;
}

-(void)checkPidInterval:(uint16_t)pid nowMs:(uint64_t)nowMs
{
    NSNumber *pidKey = @(pid);
    NSNumber *lastSeen = mPidLastSeenMsMap[pidKey];

    if (!lastSeen) {
        // First time seeing this PID - start tracking
        mPidLastSeenMsMap[pidKey] = @(nowMs);
        return;
    }

    uint64_t lastSeenMs = lastSeen.unsignedLongLongValue;
    uint64_t elapsedMs = nowMs - lastSeenMs;

    if (elapsedMs > TR101290_PID_INTERVAL_MS) {
        _stats.prio1.pidError++;
        // Reset to avoid repeated errors
        mPidLastSeenMsMap[pidKey] = @(nowMs);
    }
}

-(BOOL)wasSectionSeenTooLongAgo:(NSNumber* _Nonnull)pid nowMs:(uint64_t)nowMs thresholdMs:(uint64_t)thresholdMs
{
    NSNumber *lastSeen = mSectionLastSeenMsMap[pid];
    if (!lastSeen) {
        // No section seen yet - insert current time to start the timer
        mSectionLastSeenMsMap[pid] = @(nowMs);
        return NO;
    }

    uint64_t lastSeenMs = lastSeen.unsignedLongLongValue;
    uint64_t elapsedMs = (nowMs - lastSeenMs);
    return elapsedMs > thresholdMs;
}

-(BOOL)wasIntervalErrorReportedTooLongAgo:(NSNumber* _Nonnull)pid nowMs:(uint64_t)nowMs thresholdMs:(uint64_t)thresholdMs
{
    NSNumber *lastReported = mIntervalErrorLastReportedMsMap[pid];
    if (!lastReported) {
        // Never reported - ok to report
        return YES;
    }
    return (nowMs - lastReported.unsignedLongLongValue) > thresholdMs;
}

/// Throttle interval checks to avoid running on every packet
-(BOOL)shouldRunIntervalCheck:(uint64_t)nowMs
{
    const uint64_t intervalCheckThrottleMs = 200; // Check every 200ms for efficiency
    return (nowMs - mLastIntervalCheckMs >= intervalCheckThrottleMs);
}

#pragma mark - Filter Change Handling

-(void)handleFilterChangeFromOldFilter:(NSSet<NSNumber*>* _Nullable)oldFilter
                           toNewFilter:(NSSet<NSNumber*>* _Nullable)newFilter
{
    // Reset state for PIDs that were excluded but will now be included,
    // preventing false positives from stale CC and last-seen state. e.g.
    // 1) Filter = nil, PID 256 gets CC=0,1,2
    // 2) Filter = {257} (exclude 256), packets on 256 skipped
    // 3) Filter = {256} (re-include), next packet has CC=7
    // Without reset, CC jump from 2->7 would be flagged as error

    NSMutableArray<NSNumber*> *pidsToReset = [NSMutableArray array];

    // Reset CC validators for newly included PIDs
    for (NSNumber *pid in mPidCcValidatorMap) {
        if ([self wasPid:pid excludedByFilter:oldFilter] &&
            [self willPid:pid beIncludedByFilter:newFilter]) {
            [pidsToReset addObject:pid];
        }
    }
    [mPidCcValidatorMap removeObjectsForKeys:pidsToReset];

    // Reset last-seen timestamps for newly included PIDs
    [pidsToReset removeAllObjects];
    for (NSNumber *pid in mPidLastSeenMsMap) {
        if ([self wasPid:pid excludedByFilter:oldFilter] &&
            [self willPid:pid beIncludedByFilter:newFilter]) {
            [pidsToReset addObject:pid];
        }
    }
    [mPidLastSeenMsMap removeObjectsForKeys:pidsToReset];
}

-(BOOL)wasPid:(NSNumber*)pid excludedByFilter:(NSSet<NSNumber*>*)filter
{
    // Empty/nil filter means all PIDs were included, so none were excluded
    if (filter.count == 0) return NO;
    return ![filter containsObject:pid];
}

-(BOOL)willPid:(NSNumber*)pid beIncludedByFilter:(NSSet<NSNumber*>*)filter
{
    // Empty/nil filter means all PIDs will be included
    if (filter.count == 0) return YES;
    return [filter containsObject:pid];
}

@end

