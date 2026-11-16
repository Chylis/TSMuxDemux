//
//  TSTimeUtil.m
//  TSMuxDemux
//

#import "TSTimeUtil.h"
#import "TSLog.h"
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
        if (mach_timebase_info(&machTimebaseInfo) != KERN_SUCCESS) {
            TSLogError(@"Failed to fetch mach_timebase_info");
            NSAssert(NO, @"Failed to fetch mach_timebase_info");
        }
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
    return (uint64_t)(seconds * ONE_SECOND_NANOS);
}

+(uint64_t)convertTimeToUIntTime:(CMTime)time withNewTimescale:(uint32_t)newTimescale
{
    // Round to nearest. Callers' timestamps are often exact frame-grid times that went
    // through nanosecond host-clock arithmetic (anchor + n * 1/60 s is rounded to whole ns),
    // so they land a hair either side of a 90 kHz tick. Truncating turned that into
    // 1499/1500/1501-tick gaps for a constant 60 fps; rounding keeps every gap 1500.
    // Rounding moves a stamp by at most half a tick and keeps their order (it is monotonic),
    // so DTS <= PTS still holds.
    CMTime converted = CMTimeConvertScale(time, newTimescale, kCMTimeRoundingMethod_RoundHalfAwayFromZero);
    if (converted.value < 0) {
        TSLogWarn(@"Negative timestamp clamped to 0 (value: %lld, timescale: %u)", converted.value, newTimescale);
        return 0;
    }
    return (uint64_t)converted.value;
}

+(CMTime)convertUIntTimeToCMTime:(uint64_t)timeAsUInt withNewTimescale:(uint32_t)newTimescale
{
    return CMTimeMake(timeAsUInt, newTimescale);
}

@end
