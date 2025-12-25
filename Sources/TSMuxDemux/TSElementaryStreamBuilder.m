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
#import <CoreMedia/CoreMedia.h>

@interface TSElementaryStreamBuilder()

@property(nonatomic) CMTime pts;
@property(nonatomic) CMTime dts;
@property(nonatomic) BOOL isDiscontinuous;
@property(nonatomic, strong) NSMutableData *collectedData;
@property(nonatomic) TSResolvedStreamType resolvedStreamType;
@property(nonatomic) BOOL isVideo;

@end

@implementation TSElementaryStreamBuilder
{
    BOOL _hasLastCC;
    uint8_t _lastContinuityCounter;
}

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
        _hasLastCC = NO;
        _lastContinuityCounter = 0;
        _resolvedStreamType = [TSStreamType resolveStreamType:streamType descriptors:descriptors];
        _isVideo = [TSStreamType isVideo:_resolvedStreamType];
    }
    return self;
}



-(void)addTsPacket:(TSPacket* _Nonnull)tsPacket
{
    NSAssert(tsPacket.header.pid == self.pid, @"PID mismatch");
    //NSLog(@"pid: %u, CC '%u', adaptation: %u", self.pid, tsPacket.header.continuityCounter, tsPacket.header.adaptationMode);

    BOOL isDuplicateCC = _hasLastCC &&
        tsPacket.header.continuityCounter == _lastContinuityCounter &&
        !tsPacket.adaptationField.discontinuityFlag;

    _hasLastCC = YES;
    _lastContinuityCounter = tsPacket.header.continuityCounter;

    if (isDuplicateCC) {
        // FIXME MG: Consider not only duplicate CCs but also gaps
        return;
    }

    if (tsPacket.header.payloadUnitStartIndicator) {
        // New PES packet starting - parse header only (no data copy)
        TSPesHeader *pesHeader = [TSPesHeader parseFromPacket:tsPacket];
        if (!pesHeader) {
            return;
        }

        const NSUInteger payloadLength = tsPacket.payload.length - pesHeader.payloadOffset;

        // Check if this PES packet belongs to the same access unit (same PTS).
        // This handles interlaced video where top and bottom fields are sent in separate
        // PES packets but share the same PTS. It also handles cases where a single frame
        // is split across multiple PES packets (e.g., multiple slices with the same PTS).
        // By aggregating PES packets with matching PTS, we ensure the decoder receives
        // complete frames/field-pairs rather than incomplete data.
        BOOL isSameAccessUnit = NO;
        if (self.collectedData.length > 0 && CMTIME_IS_VALID(self.pts) && CMTIME_IS_VALID(pesHeader.pts)) {
            isSameAccessUnit = CMTimeCompare(self.pts, pesHeader.pts) == 0;
        }

        if (isSameAccessUnit) {
            // Same PTS - this is a continuation of the same frame (e.g., another slice)
            // Append directly to accumulator - single copy
            [self.collectedData appendBytes:tsPacket.payload.bytes + pesHeader.payloadOffset
                                     length:payloadLength];
            // Preserve the original DTS and discontinuity flag from the first PES
        } else {
            // Different PTS - deliver the previous access unit if we have one
            if (self.collectedData.length > 0) {
                TSAccessUnit *accessUnit = [[TSAccessUnit alloc] initWithPid:self.pid
                                                                         pts:self.pts
                                                                         dts:self.dts
                                                             isDiscontinuous:self.isDiscontinuous
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

            // Estimate capacity to minimize reallocations during accumulation
            NSUInteger capacity;
            if (pesHeader.pesPacketLength != 0) {
                // pesPacketLength (num bytes remaining after the pesPacketLength field) is known - use it
                // (including optional PES header field - slight over-allocation is fine).
                capacity = pesHeader.pesPacketLength;
            } else if (self.isVideo) {
                // Unbounded PES (length=0) is common for video.
                // HEVC uses larger CTUs (up to 64x64) vs H.264's 16x16 macroblocks,
                // and more complex prediction modes, resulting in larger frame sizes.
                capacity = (self.resolvedStreamType == TSResolvedStreamTypeH265)
                ? 128 * 1024
                : 64 * 1024;
            } else {
                // Audio frames are typically small (AAC ~1KB, AC-3 ~2KB per frame).
                // Use 8KB to account for multiple audio frames per PES.
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
