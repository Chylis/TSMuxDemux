//
//  TSTimeUtil.m
//  TSMuxDemux
//

#import "TSTimeUtil.h"
#include <mach/mach_time.h>

static const uint64_t ONE_SECOND_NANOS = 1000000000;

@implementation TSTimeUtil
{
    // machTimebaseInfo is used to convert mach ticks to/from nanoseconds.
    // https://developer.apple.com/library/archive/qa/qa1643/_index.html
    // E.g. if the numerator is 1,000,000,000 and the denominator is 6,000,000, the frequency is 6,000,000:ths of a second.
    // Ticks to nanos: (numTicks * numer) / denom = (1 * 6_000_000) / 1_000_000_000) = 0.006 nanos per tick
    // Nanos to ticks: (nanos * denom) / numer    = (1 * 1_000_000_000) / 6_000_000  = 166.67 tics per nano
    mach_timebase_info_data_t machTimebaseInfo;
}

+(instancetype)sharedInstance
{
    static dispatch_once_t once;
    static id sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

-(instancetype)init
{
    self = [super init];
    if (self) {
        mach_timebase_info(&machTimebaseInfo);
    }
    return self;
}

+(uint64_t)nowHostTimeMachTicks
{
    return mach_absolute_time();
}

+(uint64_t)nowHostTimeNanos
{
    uint64_t numberOfTicksRightNow = [self nowHostTimeMachTicks];
    return [self convertMachTicksToNanos:numberOfTicksRightNow];
}

+(uint64_t)convertMachTicksToNanos:(uint64_t)numberOfTicks
{
    mach_timebase_info_data_t machTimebaseInfo = [TSTimeUtil sharedInstance]->machTimebaseInfo;
    return (numberOfTicks * ((uint64_t)machTimebaseInfo.numer)) / ((uint64_t)machTimebaseInfo.denom);
}

+(uint64_t)convertNanosToMachTicks:(uint64_t)nanos
{
    mach_timebase_info_data_t machTimebaseInfo = [TSTimeUtil sharedInstance]->machTimebaseInfo;
    return (nanos * ((uint64_t)machTimebaseInfo.denom)) / ((uint64_t)machTimebaseInfo.numer);
}

+(uint64_t)secondsToNanos:(double)seconds
{
    return (uint64_t)seconds * ONE_SECOND_NANOS;
}

+(uint64_t)convertTimeToUIntTime:(CMTime)time withNewTimescale:(uint32_t)newTimescale
{
    return (uint64_t)(((double)time.value / (double)time.timescale) * newTimescale);
}

+(CMTime)convertUIntTimeToCMTime:(uint64_t)timeAsUInt withNewTimescale:(uint32_t)newTimescale
{
    return CMTimeMake(timeAsUInt, newTimescale);
}

@end
