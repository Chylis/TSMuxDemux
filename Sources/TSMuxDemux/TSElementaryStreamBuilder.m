//
//  TSElementaryStreamBuilder.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-08.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSElementaryStreamBuilder.h"
#import "TSPacket.h"
#import <CoreMedia/CoreMedia.h>

@interface TSElementaryStreamBuilder()

@property(nonatomic) CMTime pts;
@property(nonatomic) CMTime dts;
@property(nonatomic) BOOL isDiscontinuous;
@property(nonatomic, strong) NSMutableData *collectedData;

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
        // New PES packet starting - parse its header first to get PTS
        TSAccessUnit *newPesAccessUnit = [TSAccessUnit initWithTsPacket:tsPacket
                                                                    pid:self.pid
                                                             streamType:self.streamType
                                                            descriptors:self.descriptors];

        // Check if this PES packet belongs to the same access unit (same PTS).
        // This handles interlaced video where top and bottom fields are sent in separate
        // PES packets but share the same PTS. It also handles cases where a single frame
        // is split across multiple PES packets (e.g., multiple slices with the same PTS).
        // By aggregating PES packets with matching PTS, we ensure the decoder receives
        // complete frames/field-pairs rather than incomplete data.
        BOOL isSameAccessUnit = NO;
        if (self.collectedData.length > 0 && CMTIME_IS_VALID(self.pts) && CMTIME_IS_VALID(newPesAccessUnit.pts)) {
            isSameAccessUnit = CMTimeCompare(self.pts, newPesAccessUnit.pts) == 0;
        }

        if (isSameAccessUnit) {
            // Same PTS - this is a continuation of the same frame (e.g., another slice)
            // Append the data without delivering the previous access unit
            //NSLog(@"[TSESBuilder] pid=%u: Aggregating PES into same access unit (PTS=%.3f) - collected %lu + %lu bytes",
            //      self.pid,
            //      CMTimeGetSeconds(self.pts),
            //      (unsigned long)self.collectedData.length,
            //      (unsigned long)newPesAccessUnit.compressedData.length);
            [self.collectedData appendData:newPesAccessUnit.compressedData];
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

            // Start collecting the new access unit
            self.pts = newPesAccessUnit.pts;
            self.dts = newPesAccessUnit.dts;
            self.isDiscontinuous = newPesAccessUnit.isDiscontinuous;
            self.collectedData = [NSMutableData dataWithData:newPesAccessUnit.compressedData];
        }
    } else {
        // Continuation of PES packet
        if (!self.collectedData) {
            //NSLog(@"TSESStreamBuilder: Waiting for PUSI=true for pid %u - discarding", self.pid);
            return;
        }
        // Here we assume the entire payload is part of the PES continuation.
        // If there's any risk of extra stuffing, we might need to compute the expected length.
        if (tsPacket.payload.length > 0) {
            [self.collectedData appendData:tsPacket.payload];
        }
    }
}

@end
