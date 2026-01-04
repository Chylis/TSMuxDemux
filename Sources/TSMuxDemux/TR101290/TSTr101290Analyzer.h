//
//  TSTr101290Analyzer.h
//  
//
//  Created by Magnus Eriksson on 2023-03-01.
//

#import <Foundation/Foundation.h>
@class TSPacket;
@class TSTr101290Statistics;
@class TSTr101290AnalyzeContext;

@interface TSTr101290Analyzer : NSObject

@property(nonatomic, strong, readonly) TSTr101290Statistics * _Nonnull stats;

-(void)analyzeTsPacket:(TSPacket* _Nonnull)tsPacket
               context:(TSTr101290AnalyzeContext* _Nonnull)context;

/// Resets CC and last-seen state for PIDs transitioning from excluded to included.
/// Call when esPidFilter changes to prevent false positives from stale state.
-(void)handleFilterChangeFromOldFilter:(NSSet<NSNumber*>* _Nullable)oldFilter
                           toNewFilter:(NSSet<NSNumber*>* _Nullable)newFilter;

@end
