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

@end
