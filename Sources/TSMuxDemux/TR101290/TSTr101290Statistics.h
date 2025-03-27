//
//  TSTr101290Statistics.h
//  
//
//  Created by Magnus Eriksson on 2023-03-01.
//

#import <Foundation/Foundation.h>


#pragma mark - TSTr10129Prio1

@interface TSTr10129Prio1: NSObject

/**
 The most important function for the evaluation of data from the MPEG-2 TS is the sync acquisition.
 The actual synchronization of the TS depends on the number of correct sync bytes necessary for the device to synchronize
 and on the number of distorted sync bytes which the device cannot cope with.
 It is proposed that five consecutive correct sync bytes (ISO/IEC 13818-1 [i.1], clause G.1) should be sufficient for sync acquisition,
 and two or more consecutive corrupted sync bytes should indicate sync loss.
 */
@property(nonatomic) uint64_t tsSyncLoss;

/**
 Ts packet header sync byte not 0x47
 */
@property(nonatomic) uint64_t syncByteError;

/**
- PID 0x0000 does not occur at least every 0,5s: Sections with table_id 0x00 do not occur at least every 0,5 s on PID 0x0000.
- PID 0x0000 does not contain a table_id 0x00 (i.e. a PAT): Section with table_id other than 0x00 found on PID 0x0000.
- Scrambling_control_field is not 00 for PID 0x0000: Scrambling_control_field is not 00 for PID 0x0000 ETSI TS 101 154 [i.30], clause 4.1.7
 */
@property(nonatomic) uint64_t patError;

@property(nonatomic) uint64_t ccError;
@property(nonatomic) uint64_t pmtError;

/**
 - Referred PID does not occur for a user specified period.
 */
@property(nonatomic) uint64_t pidError;

@end


#pragma mark - TSTr101290Statistics

@interface TSTr101290Statistics : NSObject

@property(nonatomic, strong, readonly) TSTr10129Prio1 * _Nullable prio1;

@end
