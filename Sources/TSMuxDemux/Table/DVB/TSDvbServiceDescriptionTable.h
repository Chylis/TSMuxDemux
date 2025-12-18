//
//  TSDvbServiceDescriptionTable.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2025-03-23.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "../TSProgramSpecificInformationTable.h"
#import "../../TSConstants.h"
@class TSDescriptor;
@class TSDvbServiceDescriptor;

@interface TSDvbServiceDescriptionEntry : NSObject
@property(nonatomic, readonly) uint16_t serviceId;
@property(nonatomic, readonly) BOOL eitScheduleFlag;
@property(nonatomic, readonly) BOOL eitPresentFollowingFlag;
@property(nonatomic, readonly) uint8_t runningStatus;
@property(nonatomic, readonly) BOOL freeCaMode;
@property(nonatomic, readonly) NSArray<TSDescriptor*> * _Nullable descriptors;

#pragma mark - Util - Implemented/Parsed Descriptor Accessors

/// Returns all service descriptors (tag 0x48) from this entry's descriptor loop.
-(NSArray<TSDvbServiceDescriptor*>* _Nonnull)serviceDescriptors;

@end

@interface TSDvbServiceDescriptionTable : NSObject

@property(nonatomic, readonly) TSProgramSpecificInformationTable * _Nonnull psi;
-(uint16_t)transportStreamId;

-(uint16_t)originalNetworkId;
-(NSArray<TSDvbServiceDescriptionEntry*> * _Nullable)entries;

#pragma mark Demuxer

-(instancetype _Nullable)initWithPSI:(TSProgramSpecificInformationTable* _Nonnull)psi;

@end
