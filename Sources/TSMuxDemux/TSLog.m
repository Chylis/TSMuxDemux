//
//  TSLog.m
//  TSMuxDemux
//
//  Centralized logging system with log level filtering.
//

#import "TSLog.h"
#import <stdatomic.h>
#import <os/lock.h>

// Thread-safe storage for log level using atomic operations
static _Atomic TSLogLevel sCurrentLogLevel = TSLogLevelInfo;

// Thread-safe storage for log sink block
static TSLogSinkBlock sLogSinkBlock = nil;
static os_unfair_lock sLogSinkLock = OS_UNFAIR_LOCK_INIT;

// Key for thread-local date formatter cache
static NSString* const kTSLogDateFormatKey = @"TSLogDateFormatter";

@implementation TSLog

#pragma mark - Public Class Methods

+(void)setLevel:(TSLogLevel)level
{
    TSLogLevel oldLevel = atomic_load(&sCurrentLogLevel);
    atomic_store(&sCurrentLogLevel, level);

    if (oldLevel != level) {
        [self logWithLevel:TSLogLevelInfo
                 className:@"TSLog"
                    format:@"Log level changed: %@ -> %@",
         [self levelName:oldLevel],
         [self levelName:level]];
    }
}

+(void)setLogSinkBlock:(TSLogSinkBlock _Nullable)block
{
    os_unfair_lock_lock(&sLogSinkLock);
    sLogSinkBlock = [block copy];
    os_unfair_lock_unlock(&sLogSinkLock);
}

+(TSLogLevel)currentLevel
{
    return atomic_load(&sCurrentLogLevel);
}

+(NSString*)levelName:(TSLogLevel)level
{
    switch (level) {
        case TSLogLevelNone:  return @"NONE";
        case TSLogLevelError: return @"ERROR";
        case TSLogLevelWarn:  return @"WARN";
        case TSLogLevelInfo:  return @"INFO";
        case TSLogLevelDebug: return @"DEBUG";
        case TSLogLevelTrace: return @"TRACE";
        default:              return @"?";
    }
}

+(void)logWithLevel:(TSLogLevel)level
          className:(NSString*)className
             format:(NSString*)format, ...
{
    // Format the user message
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // Format final log line: [timestamp] [TS] [LEVEL] [ClassName] Message
    NSDate *now = [NSDate date];
    NSString *timestamp = [self utcTimestampFromDate:now];
    NSString *levelName = [self levelName:level];
    NSLog(@"[%@] [TS] [%@] [%@] %@", timestamp, levelName, className, message);

    // Call sink block if set
    os_unfair_lock_lock(&sLogSinkLock);
    TSLogSinkBlock lBlock = sLogSinkBlock;
    os_unfair_lock_unlock(&sLogSinkLock);

    if (lBlock) {
        lBlock(level, className, message, [now timeIntervalSince1970]);
    }
}

#pragma mark - Private Helpers

/**
 * Returns date as UTC ISO 8601 timestamp with milliseconds.
 * Uses thread-local cached formatter for performance.
 * Format: 2024-01-15T10:30:45.123Z
 */
+(NSString*)utcTimestampFromDate:(NSDate*)date
{
    // Get or create thread-local date formatter
    NSMutableDictionary *threadDict = [[NSThread currentThread] threadDictionary];
    NSDateFormatter *formatter = threadDict[kTSLogDateFormatKey];

    if (!formatter) {
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        threadDict[kTSLogDateFormatKey] = formatter;
    }

    return [formatter stringFromDate:date];
}

@end
