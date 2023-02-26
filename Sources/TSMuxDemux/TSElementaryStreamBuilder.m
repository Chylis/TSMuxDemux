//
//  TSElementaryStreamBuilder.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-08.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSElementaryStreamBuilder.h"
#import "TSPacket.h"
#import "TSElementaryStreamStats.h"
#import <CoreMedia/CoreMedia.h>

@interface TSElementaryStreamBuilder()

@property(nonatomic) CMTime pts;
@property(nonatomic) CMTime dts;
@property(nonatomic, strong) NSMutableData *collectedData;

@property(nonatomic, strong) TSPacket *lastPacket;
@property(nonatomic, strong) TSPacket *secondLastPacket;
@property(nonatomic, strong) TSPacket *thirdLastPacket;

@end

@implementation TSElementaryStreamBuilder

-(instancetype _Nonnull)initWithDelegate:(id<TSElementaryStreamBuilderDelegate>)delegate
                                     pid:(uint16_t)pid
                              streamType:(TSStreamType)streamType;
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _pid = pid;
        _streamType = streamType;
        _lastPacket = nil;
        _secondLastPacket = nil;
        _thirdLastPacket = nil;
        _stats = [TSElementaryStreamStats new];
    }
    return self;
}



-(void)addTsPacket:(TSPacket* _Nonnull)tsPacket
{
    NSAssert(tsPacket.header.pid == self.pid, @"PID mismatch");
    
    //NSLog(@"pid: %u, CC '%u'", self.pid, tsPacket.header.continuityCounter);
    
    const BOOL isDuplicatePacket = tsPacket.header.continuityCounter == self.lastPacket.header.continuityCounter;
    TSContinuityCountError *ccError = [self validateContinuityCounter:tsPacket
                                                           lastPacket:self.lastPacket
                                                     secondLastPacket:self.secondLastPacket
                                                      thirdLastPacket:self.thirdLastPacket];
    if (ccError) {
        [_stats.ccErrors addObject:ccError];
        [self.delegate streamBuilder:self didReceiveCCError:ccError];
    }
    
    [self setThirdLastPacket:self.secondLastPacket];
    [self setSecondLastPacket:self.lastPacket];
    [self setLastPacket:tsPacket];
    
    if (isDuplicatePacket) {
        self.stats.discardedPacketCount++;
        return;
    }
    
    if (tsPacket.header.payloadUnitStartIndicator) {
        // First packet of new PES
        if (self.collectedData.length > 0) {
            TSAccessUnit *accessUnit = [[TSAccessUnit alloc] initWithPid:self.pid
                                                                     pts:self.pts
                                                                     dts:self.dts
                                                              streamType:self.streamType
                                                          compressedData:self.collectedData];
            [self.delegate streamBuilder:self didBuildAccessUnit:accessUnit];
        }
        
        // Parse PES header
        TSAccessUnit *firstAccessUnit = [TSAccessUnit initWithTsPacket:tsPacket pid:self.pid streamType:self.streamType];
        self.pts = firstAccessUnit.pts;
        self.dts = firstAccessUnit.dts;
        self.collectedData = [NSMutableData dataWithData:firstAccessUnit.compressedData];
    } else {
        if (tsPacket.payload.length > 0) {
            [self.collectedData appendData:tsPacket.payload];
        }
    }
}


-(TSContinuityCountError* _Nullable)validateContinuityCounter:(TSPacket*)currentPacket
                                    lastPacket:(TSPacket*)lastPacket
                              secondLastPacket:(TSPacket*)secondLastPacket
                               thirdLastPacket:(TSPacket*)thirdLastPacket
{
    TSContinuityCountError *error = nil;
    BOOL isDuplicateCC = currentPacket.header.continuityCounter == lastPacket.header.continuityCounter;
    
    // "The continuity counter may be discontinuous when the discontinuity_indicator is set to '1' (refer to 2.4.3.4)."
    if (lastPacket && !currentPacket.adaptationField.discontinuityFlag) {
        if (isDuplicateCC) {
            /*
            // Duplicate packets may be sent as two, and only two, consecutive Transport Stream packets of the same PID.
            BOOL tooManyDuplicateCCs =
            lastPacket.header.continuityCounter == secondLastPacket.header.continuityCounter
            && lastPacket.header.continuityCounter == thirdLastPacket.header.continuityCounter;
            if (tooManyDuplicateCCs) {
                // e.g. 0-1-2-2-2-2-3-4-5 (error reason: CC 2 must occur 3 times).
                error = [[TSContinuityCountError alloc] initWithReceived:currentPacket.header.continuityCounter
                                                                expected:[self nextContinuityCounter:currentPacket.header.continuityCounter]
                                                                 message:@"Too many packets with same CC (>= 4)"];
            } else if (currentPacket.header.adaptationMode != TSAdaptationModePayloadOnly &&
                       currentPacket.header.adaptationMode != TSAdaptationModeAdaptationAndPayload) {
                // The duplicate packets shall have the same continuity_counter value as the original packet and the adaptation_field_control field shall be equal to '01' or '11'.
                error = [[TSContinuityCountError alloc] initWithReceived:currentPacket.header.continuityCounter
                                                                expected:currentPacket.header.continuityCounter
                                                                 message:@"The adaptation_field_control of the duplicate packet shall be equal to '01' or '11'"];
            } */
            
            // TODO: Implement check for "isEqualExceptPCRIfPresent" (see below comment):
            // In duplicate packets each byte of the original packet shall be duplicated, with the exception that in the program clock reference fields, if present, a valid value shall be encoded.
        } else {
            // The continuity_counter shall not be incremented when the adaptation_field_control of the packet equals '00' or '10'.
            BOOL isNotExpectingIncrementedCC =
            currentPacket.header.adaptationMode == TSAdaptationModeReserved ||
            currentPacket.header.adaptationMode == TSAdaptationModeAdaptationOnly;
            if (isNotExpectingIncrementedCC) {
                // e.g. 0-1-2
                error = [[TSContinuityCountError alloc] initWithReceived:currentPacket.header.continuityCounter
                                                                expected:lastPacket.header.continuityCounter
                                                                 message:@"The continuity_counter shall not be incremented when the adaptation_field_control of the packet equals '00' or '10'"];
            } else {
                /* // Duplicate packets may be sent as two, and only two, consecutive Transport Stream packets of the same PID.
                BOOL tooFewDuplicateCCs =
                lastPacket.header.continuityCounter == secondLastPacket.header.continuityCounter &&
                secondLastPacket.header.continuityCounter != thirdLastPacket.header.continuityCounter;
                if (tooFewDuplicateCCs) {
                    // e.g. 0-1-2-2-3 (error reason: CC 2 must occur 3 times).
                    error = [[TSContinuityCountError alloc] initWithReceived:currentPacket.header.continuityCounter
                                                                    expected:lastPacket.header.continuityCounter
                 message:@"Too few duplicate packets with same CC (< 2)"];
                 } else {*/
                uint8_t expectedCC = [self nextContinuityCounter:lastPacket.header.continuityCounter];
                if (currentPacket.header.continuityCounter != expectedCC) {
                    error = [[TSContinuityCountError alloc] initWithReceived:currentPacket.header.continuityCounter
                                                                    expected:expectedCC
                                                                     message:@"Unexpected CC"];
                }
                //}
            }
        }
    }
    
    return error;
}

-(uint8_t)nextContinuityCounter:(uint8_t)currentContinuityCounter
{
    static const NSUInteger MAX_VALUE = 16;
    return (currentContinuityCounter + 1) % MAX_VALUE;
}

@end
