//
//  TSTr101290Analyzer.h
//  
//
//  Created by Magnus Eriksson on 2023-03-01.
//

#import <Foundation/Foundation.h>
@class TSPacket;
@class TSProgramMapTable;
@class TSProgramAssociationTable;
@class TSTr101290Statistics;

@interface TSTr101290Analyzer : NSObject

@property(nonatomic, strong, readonly) TSTr101290Statistics * _Nonnull stats;

-(void)analyzeTsPacket:(TSPacket* _Nonnull)tsPacket
                   pat:(TSProgramAssociationTable* _Nullable)pat
                   pmt:(TSProgramMapTable* _Nullable)pmt
     dataArrivalTimeMs:(uint64_t)dataArrivalTimeMs;

@end
