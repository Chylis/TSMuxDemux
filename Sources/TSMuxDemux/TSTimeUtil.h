//
//  TSTimeUtil.h
//  TSMuxDemux
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

@interface TSTimeUtil : NSObject

+(uint64_t)nowHostTimeMachTicks;

+(uint64_t)nowHostTimeNanos;

/// Converts the received number of mach ticks units to nanos
+(uint64_t)convertMachTicksToNanos:(uint64_t)numberOfTicks;

/// Converts the received number of nanos to host time/mach ticks units
+(uint64_t)convertNanosToMachTicks:(uint64_t)nanos;

+(uint64_t)secondsToNanos:(double)seconds;

+(uint64_t)convertTimeToUIntTime:(CMTime)time withNewTimescale:(uint32_t)newTimescale;
+(CMTime)convertUIntTimeToCMTime:(uint64_t)timeAsUInt withNewTimescale:(uint32_t)newTimescale;

@end
