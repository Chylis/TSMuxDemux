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

/// Reports a packet whose sync byte was invalid and which was therefore
/// dropped before parsing: its remaining header bits cannot be trusted.
/// Counts a Sync_byte_error while sync is held and feeds the same
/// TR 101 290 sync-loss tracking as analyzeTsPacket.
-(void)reportInvalidSyncByte;

/// Reports a packet whose sync byte was valid but which was dropped before
/// analysis (filtered-out PID, null packet, malformed packet). Keeps the
/// TR 101 290 sync tracking aligned with the byte stream: the packet counts
/// towards sync acquisition and interrupts a run of corrupted sync bytes.
-(void)reportValidSyncByte;

-(void)analyzeTsPacket:(TSPacket* _Nonnull)tsPacket
               context:(TSTr101290AnalyzeContext* _Nonnull)context;

/// Resets CC and last-seen state for PIDs transitioning from excluded to included.
/// Call when esPidWhitelist changes to prevent false positives from stale state.
-(void)handleFilterChangeFromOldFilter:(NSSet<NSNumber*>* _Nullable)oldFilter
                           toNewFilter:(NSSet<NSNumber*>* _Nullable)newFilter;

@end
