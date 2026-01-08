//
//  TSLog.h
//  TSMuxDemux
//
//  Centralized logging system with log level filtering.
//

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TSLogLevel) {
    TSLogLevelNone = 0,
    TSLogLevelError,
    TSLogLevelWarn,
    TSLogLevelInfo,
    TSLogLevelDebug,
    TSLogLevelTrace
};

typedef void (^TSLogSinkBlock)(TSLogLevel level, NSString *className, NSString *message, NSTimeInterval timestamp);

/**
 * TSLog provides centralized logging for TSMuxDemux.
 *
 * Usage:
 *   [TSLog setLevel:TSLogLevelDebug];
 *   TSLogInfo(@"Demuxer started");
 *   TSLogError(@"Failed to parse packet: %@", error);
 *
 * Log format:
 *   [2024-01-15T10:30:45.123Z] [TS] [INFO] [TSDemuxer] Message here
 */
@interface TSLog : NSObject

+(void)setLevel:(TSLogLevel)level;

+(void)setLogSinkBlock:(TSLogSinkBlock _Nullable)block;

+(TSLogLevel)currentLevel;

+(NSString*)levelName:(TSLogLevel)level;

+(void)logWithLevel:(TSLogLevel)level
          className:(NSString*)className
             format:(NSString*)format, ... NS_FORMAT_FUNCTION(3,4);

@end


#pragma mark - Logging Macros

/**
 * Check if a log level is currently enabled.
 * Use for expensive operations that should be skipped when not logging.
 */
#define TSLogIsLevelEnabled(lvl) ([TSLog currentLevel] >= (lvl))

/**
 * Internal macro for generating log calls in ObjC method context.
 * Short-circuits to avoid format string evaluation when level disabled.
 */
#define _TSLogInternal(lvl, fmt, ...) \
    do { \
        if (TSLogIsLevelEnabled(lvl)) { \
            [TSLog logWithLevel:(lvl) \
                      className:NSStringFromClass([self class]) \
                         format:(fmt), ##__VA_ARGS__]; \
        } \
    } while(0)

/**
 * Internal macro for C functions where 'self' is unavailable.
 * Uses __FILE__ for context.
 */
#define _TSLogInternalC(lvl, fmt, ...) \
    do { \
        if (TSLogIsLevelEnabled(lvl)) { \
            [TSLog logWithLevel:(lvl) \
                      className:[[NSString stringWithUTF8String:__FILE__] lastPathComponent] \
                         format:(fmt), ##__VA_ARGS__]; \
        } \
    } while(0)

/**
 * ObjC method context macros - use 'self' for class name.
 * Support NSLog-style format strings with variadic arguments.
 */
#define TSLogError(fmt, ...)  _TSLogInternal(TSLogLevelError, fmt, ##__VA_ARGS__)
#define TSLogWarn(fmt, ...)   _TSLogInternal(TSLogLevelWarn, fmt, ##__VA_ARGS__)
#define TSLogInfo(fmt, ...)   _TSLogInternal(TSLogLevelInfo, fmt, ##__VA_ARGS__)
#define TSLogDebug(fmt, ...)  _TSLogInternal(TSLogLevelDebug, fmt, ##__VA_ARGS__)
#define TSLogTrace(fmt, ...)  _TSLogInternal(TSLogLevelTrace, fmt, ##__VA_ARGS__)

/**
 * C function context macros - use __FILE__ for context.
 * Use these in C callbacks, static functions, or places where 'self' is unavailable.
 */
#define TSLogErrorC(fmt, ...)  _TSLogInternalC(TSLogLevelError, fmt, ##__VA_ARGS__)
#define TSLogWarnC(fmt, ...)   _TSLogInternalC(TSLogLevelWarn, fmt, ##__VA_ARGS__)
#define TSLogInfoC(fmt, ...)   _TSLogInternalC(TSLogLevelInfo, fmt, ##__VA_ARGS__)
#define TSLogDebugC(fmt, ...)  _TSLogInternalC(TSLogLevelDebug, fmt, ##__VA_ARGS__)
#define TSLogTraceC(fmt, ...)  _TSLogInternalC(TSLogLevelTrace, fmt, ##__VA_ARGS__)

NS_ASSUME_NONNULL_END
