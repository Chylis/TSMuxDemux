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
@property(nonatomic, strong) TSPacket *lastPacket;

@end

@implementation TSElementaryStreamBuilder

-(instancetype _Nonnull)initWithDelegate:(id<TSElementaryStreamBuilderDelegate>)delegate
                                     pid:(uint16_t)pid
                              streamType:(TSStreamType)streamType
                             descriptors:(NSArray<TSDescriptor *> * _Nullable)descriptors
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _pid = pid;
        _streamType = streamType;
        _descriptors = descriptors;
        _lastPacket = nil;
    }
    return self;
}



-(void)addTsPacket:(TSPacket* _Nonnull)tsPacket
{
    NSAssert(tsPacket.header.pid == self.pid, @"PID mismatch");
    //NSLog(@"pid: %u, CC '%u', adaptation: %u", self.pid, tsPacket.header.continuityCounter, tsPacket.header.adaptationMode);
    
    BOOL isDuplicateCC = tsPacket.header.continuityCounter == self.lastPacket.header.continuityCounter && !tsPacket.adaptationField.discontinuityFlag;
    
    [self setLastPacket:tsPacket];
    
    if (isDuplicateCC) {
        // FIXME MG: Consider not only duplicate CCs but also gaps
        return;
    }
    
    // FIXME MG: Consider following sequence:
    // first packet received is packet 2/2 (i.e. not PUSI)
    // second packet received is packet 1/X (i.e. PUSI=true)
    // what pts,dts etc will be sent to delegate? 
    if (tsPacket.header.payloadUnitStartIndicator) {
        // First packet of new PES
        if (self.collectedData.length > 0) {
            TSAccessUnit *accessUnit = [[TSAccessUnit alloc] initWithPid:self.pid
                                                                     pts:self.pts
                                                                     dts:self.dts
                                                         isDiscontinuous:self.isDiscontinuous
                                                              streamType:self.streamType
                                                             descriptors:self.descriptors
                                                          compressedData:self.collectedData];
            [self.delegate streamBuilder:self didBuildAccessUnit:accessUnit];
        }
        
        // Parse PES header
        TSAccessUnit *firstAccessUnit = [TSAccessUnit initWithTsPacket:tsPacket
                                                                   pid:self.pid
                                                            streamType:self.streamType
                                                         descriptors:self.descriptors];
        self.pts = firstAccessUnit.pts;
        self.dts = firstAccessUnit.dts;
        self.isDiscontinuous = firstAccessUnit.isDiscontinuous;
        self.collectedData = [NSMutableData dataWithData:firstAccessUnit.compressedData];
    } else {
        if (tsPacket.payload.length > 0) {
            [self.collectedData appendData:tsPacket.payload];
        }
    }
}

@end
