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
@property(nonatomic, strong) NSMutableData *collectedData;

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
    }
    return self;
}

-(void)addTsPacket:(TSPacket* _Nonnull)tsPacket
{
    NSAssert(tsPacket.header.pid == self.pid, @"PID mismatch");
    
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
        [self.collectedData appendData:tsPacket.payload];
    }
}

@end
