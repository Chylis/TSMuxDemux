//
//  TSElementaryStreamBuilder.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-08.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSAccessUnit.h"
@class TSPacket;
@class TSElementaryStreamBuilder;
@class TSElementaryStreamStats;
@class TSContinuityCountError;

@protocol TSElementaryStreamBuilderDelegate
-(void)streamBuilder:(TSElementaryStreamBuilder* _Nonnull)builder didBuildAccessUnit:(TSAccessUnit* _Nonnull)accessUnit;
@end

/// A class that constructs an elementary stream by collecting access units that belong together.
/// Usage: Feed it ts-packets containing PES-packets with the same pid.
@interface TSElementaryStreamBuilder : NSObject

@property(nonatomic, weak, nullable) id<TSElementaryStreamBuilderDelegate> delegate;

@property(nonatomic, readonly) uint16_t pid;
@property(nonatomic, readonly) TSStreamType streamType;
@property(nonatomic, readonly) TSElementaryStreamStats * _Nonnull statistics;

-(instancetype _Nonnull)initWithDelegate:(id<TSElementaryStreamBuilderDelegate> _Nullable)delegate
                                     pid:(uint16_t)pid
                              streamType:(TSStreamType)streamType;

-(void)addTsPacket:(TSPacket* _Nonnull)tsPacket;

@end
