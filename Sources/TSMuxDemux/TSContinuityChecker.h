//
//  TSContinuityChecker.h
//  TSMuxDemux
//
//  Validates TS packet continuity counter per ITU-T H.222.0 §2.4.3.3
//

#import <Foundation/Foundation.h>
@class TSPacket;

/// Result of continuity counter validation
typedef NS_ENUM(NSUInteger, TSContinuityCheckResult) {
    /// Normal packet - continue processing
    TSContinuityCheckResultOK,
    /// Duplicate CC (retransmission) - skip this packet
    TSContinuityCheckResultDuplicate,
    /// CC gap detected (packets were lost) - discard in-progress data
    TSContinuityCheckResultGap,
};

/// Tracks and validates continuity counter for a single PID.
/// Create one instance per PID being tracked.
@interface TSContinuityChecker : NSObject

/// Validates the continuity counter of the given packet.
/// Updates internal state and returns the appropriate action.
-(TSContinuityCheckResult)checkPacket:(TSPacket * _Nonnull)packet;

@end
