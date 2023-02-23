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
        _statistics = [TSElementaryStreamStats new];
    }
    return self;
}



-(void)addTsPacket:(TSPacket* _Nonnull)tsPacket
{
    NSAssert(tsPacket.header.pid == self.pid, @"PID mismatch");
    //NSLog(@"pid: %u, CC '%u', adaptation: %u", self.pid, tsPacket.header.continuityCounter, tsPacket.header.adaptationMode);
    
    BOOL isDuplicateCC = tsPacket.header.continuityCounter == self.lastPacket.header.continuityCounter;
    TSContinuityCountError *ccError = [self validateContinuityCounter:tsPacket
                                                           lastPacket:self.lastPacket
                                                     secondLastPacket:self.secondLastPacket];
    if (ccError) {
        [self.statistics.ccErrors addObject:ccError];
        //NSLog(@"CC error for pid '%u' ('%@'): got '%u', expected '%u'. %@", self.pid, [TSAccessUnit streamTypeDescription:self.streamType], ccError.receivedCC, ccError.expectedCC, ccError.message);
    }
    
    // Start over on discontinuity
    [self setSecondLastPacket:tsPacket.adaptationField.discontinuityFlag ? nil : self.lastPacket];
    [self setLastPacket:tsPacket];
    
    if (isDuplicateCC) {
        self.statistics.duplicatePacketCount++;
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
            return [[TSContinuityCountError alloc] initWithReceived:currentPacket.header.continuityCounter
                                                           expected:nextExpectedCc
                                                            message:@"Expected incremented or duplicate CC"];
        } else if (tooManyDuplicates) {
            return [[TSContinuityCountError alloc] initWithReceived:currentPacket.header.continuityCounter
                                                           expected:nextExpectedCc
                                                            message:@"Too many packets (>= 3) with same CC"];
        }
    } else if (!isExpectingIncrementedCC && !isDuplicate) {
        return [[TSContinuityCountError alloc] initWithReceived:currentPacket.header.continuityCounter
                                                       expected:lastPacket.header.continuityCounter
                                                        message:@"Expected duplicate CC"];
    }
    return nil;
}

-(uint8_t)nextContinuityCounter:(uint8_t)currentContinuityCounter
{
    static const NSUInteger MAX_VALUE = 16;
    return (currentContinuityCounter + 1) % MAX_VALUE;
}

@end
