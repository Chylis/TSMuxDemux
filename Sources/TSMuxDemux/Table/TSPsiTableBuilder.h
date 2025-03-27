//
//  TSPsiTableBuilder.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-08.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "../TSAccessUnit.h"
@class TSPacket;
@class TSPsiTableBuilder;
@class TSProgramSpecificInformationTable;

@protocol TSPsiTableBuilderDelegate
-(void)tableBuilder:(TSPsiTableBuilder* _Nonnull)builder
      didBuildTable:(TSProgramSpecificInformationTable* _Nonnull)table;
@end

/// A class that constructs an elementary stream by collecting access units that belong together.
/// Usage: Feed it ts-packets containing PES-packets with the same pid.
@interface TSPsiTableBuilder : NSObject

@property(nonatomic, weak, nullable) id<TSPsiTableBuilderDelegate> delegate;

@property(nonatomic, readonly) uint16_t pid;
@property(nonatomic, readonly) TSStreamType streamType;
@property(nonatomic, readonly, nullable) NSArray<TSDescriptor*>* descriptors;

-(instancetype _Nonnull)initWithDelegate:(id<TSPsiTableBuilderDelegate> _Nullable)delegate
                                     pid:(uint16_t)pid;

-(void)addTsPacket:(TSPacket* _Nonnull)tsPacket;

@end
