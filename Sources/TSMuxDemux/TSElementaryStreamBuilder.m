//
//  TSElementaryStreamBuilder.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-08.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSElementaryStreamBuilder.h"
#import "TSPacket.h"
#import "TSPesHeader.h"
#import "TSStreamType.h"
#import "TSContinuityChecker.h"
#import "TSLog.h"
#import <CoreMedia/CoreMedia.h>

@interface TSElementaryStreamBuilder()

@property(nonatomic) CMTime pts;
@property(nonatomic) CMTime dts;
@property(nonatomic) BOOL isDiscontinuous;
@property(nonatomic) BOOL isRandomAccessPoint;
@property(nonatomic, strong) NSMutableData *collectedData;
@property(nonatomic) TSResolvedStreamType resolvedStreamType;
@property(nonatomic) BOOL isVideo;
@property(nonatomic, strong) TSContinuityChecker *ccChecker;

@end

/// YES if the PES payload starts (after a 3- or 4-byte start code) with an H.264 (type 9)
/// or HEVC (type 35) access unit delimiter NAL unit.
static BOOL PayloadStartsWithAccessUnitDelimiter(const uint8_t *payload, NSUInteger length, TSResolvedStreamType type)
{
    NSUInteger nal = 0;
    if (length >= 4 && payload[0] == 0x00 && payload[1] == 0x00 && payload[2] == 0x00 && payload[3] == 0x01) {
        nal = 4;
    } else if (length >= 3 && payload[0] == 0x00 && payload[1] == 0x00 && payload[2] == 0x01) {
        nal = 3;
    } else {
        return NO;
    }
    if (type == TSResolvedStreamTypeH264) {
        return length > nal && (payload[nal] & 0x1F) == 9;
    }
    if (type == TSResolvedStreamTypeH265) {
        return length > nal + 1 && ((payload[nal] >> 1) & 0x3F) == 35;
    }
    return NO;
}

@implementation TSElementaryStreamBuilder

-(instancetype _Nonnull)initWithDelegate:(id<TSElementaryStreamBuilderDelegate>)delegate
                                     pid:(uint16_t)pid
                              streamType:(uint8_t)streamType
                             descriptors:(NSArray<TSDescriptor *> * _Nullable)descriptors
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _pid = pid;
        _streamType = streamType;
        _descriptors = descriptors;
        _collectedData = nil;
        _ccChecker = [[TSContinuityChecker alloc] init];
        _resolvedStreamType = [TSStreamType resolveStreamType:streamType descriptors:descriptors];
        _isVideo = [TSStreamType isVideo:_resolvedStreamType];
    }
    return self;
}



-(void)addTsPacket:(TSPacket* _Nonnull)tsPacket
{
    if (tsPacket.header.pid != self.pid) {
        TSLogWarn(@"PID mismatch (got %u, expected %u)", tsPacket.header.pid, self.pid);
        return;
    }

    TSContinuityCheckResult ccResult = [self.ccChecker checkPacket:tsPacket];

    if (ccResult == TSContinuityCheckResultGap) {
        // Packets were lost - discard in-progress data to avoid delivering corrupted access unit
        if (self.collectedData.length > 0) {
            TSLogWarn(@"CC gap on PID %u (packets lost), discarding %lu bytes",
                  self.pid, (unsigned long)self.collectedData.length);
        }
        self.collectedData = nil;
        self.pts = kCMTimeInvalid;
        self.dts = kCMTimeInvalid;
        return;
    }

    if (ccResult == TSContinuityCheckResultDuplicate) {
        return;
    }

    if (tsPacket.header.payloadUnitStartIndicator) {
        // New PES packet starting - parse header only (no data copy)
        TSPesHeader *pesHeader = [TSPesHeader parseFromPacket:tsPacket];
        if (!pesHeader) {
            return;
        }

        const NSUInteger payloadLength = tsPacket.payload.length - pesHeader.payloadOffset;

        // Does this PES packet continue the access unit being collected, or start a new one?
        // An access unit may span several PES packets (H.222.0 2.4.3.7): only the PES in which it
        // begins carries the PTS. Rules, for video, in order:
        // - A PES whose payload starts with an H.264/HEVC access unit delimiter starts a new unit.
        // - Otherwise, a PES without a PTS continues the unit (a split picture).
        // - Otherwise, a PES with the unit's PTS continues it (slices an encoder stamps alike);
        //   any other PTS starts a new unit - also when the unit has no PTS of its own (a fragment
        //   left by packet loss, or a parameter-set-only unit from a non-conformant mux).
        // Audio keeps the plain PTS-equality rule: PTS-less audio PES do not occur in practice.
        const BOOL hasPts = CMTIME_IS_VALID(pesHeader.pts);
        const BOOL collecting = self.collectedData.length > 0;
        const BOOL samePts = collecting && hasPts && CMTIME_IS_VALID(self.pts) && CMTimeCompare(self.pts, pesHeader.pts) == 0;
        BOOL continuesAccessUnit = NO;
        if (collecting && self.isVideo) {
            const uint8_t *payload = tsPacket.payload.bytes + pesHeader.payloadOffset;
            const BOOL startsWithDelimiter = PayloadStartsWithAccessUnitDelimiter(payload, payloadLength, self.resolvedStreamType);
            continuesAccessUnit = !startsWithDelimiter && (!hasPts || samePts);
        } else if (collecting) {
            continuesAccessUnit = samePts;
        }

        if (continuesAccessUnit) {
            // Append directly to accumulator - single copy. The first PES of the unit owns the
            // PTS, DTS and discontinuity flag.
            [self.collectedData appendBytes:tsPacket.payload.bytes + pesHeader.payloadOffset
                                     length:payloadLength];
        } else {
            // Different PTS - deliver the previous access unit if we have one
            if (self.collectedData.length > 0) {
                TSAccessUnit *accessUnit = [[TSAccessUnit alloc] initWithPid:self.pid
                                                                         pts:self.pts
                                                                         dts:self.dts
                                                             isDiscontinuous:self.isDiscontinuous
                                                          isRandomAccessPoint:self.isRandomAccessPoint
                                                                  streamType:self.streamType
                                                                 descriptors:self.descriptors
                                                              compressedData:self.collectedData];
                [self.delegate streamBuilder:self didBuildAccessUnit:accessUnit];
                self.collectedData = nil;
            }

            // Start collecting the new access unit - single copy directly to accumulator
            self.pts = pesHeader.pts;
            self.dts = pesHeader.dts;
            self.isDiscontinuous = pesHeader.isDiscontinuous;
            self.isRandomAccessPoint = tsPacket.adaptationField.randomAccessFlag;

            // Estimate capacity to minimize reallocations during accumulation.
            NSUInteger capacity;
            if (pesHeader.pesPacketLength != 0) {
                // pesPacketLength (num bytes remaining after the pesPacketLength field) is known - use it
                // (including optional PES header field - slight over-allocation is fine).
                capacity = pesHeader.pesPacketLength;
            } else if (self.isVideo) {
                // Unbounded PES (length=0) is common for video.
                // HEVC uses larger CTUs (up to 64x64) vs H.264's 16x16 macroblocks,
                // and more complex prediction modes, resulting in larger frame sizes.
                
                // Tested with 4K HEVC ~55 Mbps CBR stream:
                //   - H.265 video: ~110 KB per frame, 128 KB capacity = no reallocations
                capacity = (self.resolvedStreamType == TSResolvedStreamTypeH265)
                ? 128 * 1024
                : 64 * 1024;
            } else {
                // Audio frames are typically small (AAC ~1KB, AC-3 ~2KB per frame).
                // Use 8KB to account for multiple audio frames per PES.

                // Tested with 4K HEVC ~55 Mbps CBR stream:
                //   - E-AC-3 audio : 7.7 KB per frame, pesPacketLength used = no reallocations
                //   - AC-3 audio: 5.4 KB per frame, pesPacketLength used = no reallocations
                capacity = 8 * 1024;
            }

            self.collectedData = [NSMutableData dataWithCapacity:capacity];
            [self.collectedData appendBytes:tsPacket.payload.bytes + pesHeader.payloadOffset
                                     length:payloadLength];
        }
    } else {
        // Continuation of PES packet
        if (!self.collectedData) {
            //NSLog(@"TSESStreamBuilder: Waiting for PUSI=true for pid %u - discarding", self.pid);
            return;
        }
        // Entire payload is PES continuation data - append directly
        if (tsPacket.payload.length > 0) {
            [self.collectedData appendBytes:tsPacket.payload.bytes
                                     length:tsPacket.payload.length];
        }
    }
}

@end
