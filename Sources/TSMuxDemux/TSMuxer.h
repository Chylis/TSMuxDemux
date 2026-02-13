//
//  TSMuxer.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-01.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSConstants.h"
#import "TSAccessUnit.h"
@class TSMuxer;

@protocol TSMuxerDelegate
-(void)muxer:(TSMuxer * _Nonnull)muxer didMuxTSPacketData:(NSData* _Nonnull)tsPacketData;
@end

@interface TSMuxerSettings : NSObject <NSCopying>

/// Used to set the PID to use for the PMT PID.
/// Defaults to 4096.
/// If this PID is set to an reserved/occupied/invalid value then an exception will be thrown when initializing the muxer.
@property(nonatomic) uint16_t pmtPid;

/// How often to send PSI tables (PAT, PMT, etc).
/// The PAT should, according to TR101290, occur at least every 0.5 sec.
/// Defaults to 250 ms.
@property(nonatomic) NSUInteger psiIntervalMs;

/// Target total TS output bitrate in kilobits per second.
/// This is the wire-level rate including all TS overhead (packet headers, PES headers,
/// adaptation fields, PSI tables, null stuffing) — not the content payload rate.
/// Callers should configure their encoder bitrate below this value to leave room
/// for TS overhead; otherwise the muxer's AU queue will overflow and drop access units.
/// When set to 0 (default), the muxer operates in VBR mode (no pacing, no null packets).
/// When > 0, the muxer operates in CBR mode: tick paces output at this rate, inserting
/// null packets (PID 0x1FFF) when no content is available to maintain a constant bitrate.
@property(nonatomic) NSUInteger targetBitrateKbps;

/// Maximum number of queued access units before oldest are dropped.
/// When 0, the queue is unlimited. Defaults to 300.
@property(nonatomic) NSUInteger maxNumQueuedAccessUnits;

@end

/// A (basic) "single program" transport stream muxer.
/// Usage: Feed it with access units (in local/host timescale) and receive ts-packets via the delegate method.
@interface TSMuxer : NSObject

@property(nonatomic, weak, nullable) id<TSMuxerDelegate> delegate;

/// Initial muxer settings - cannot be modified after initialisation.
@property(nonatomic, readonly, nonnull) TSMuxerSettings *settings;

/// Clock source for the muxer. Returns the current time in nanoseconds.
/// Defaults to [TSTimeUtil nowHostTimeNanos]. Override for deterministic testing.
@property(nonatomic, copy, nonnull) uint64_t (^nowNanosProvider)(void);

/// Throws upon validation error on other initialisation error.
-(instancetype _Nonnull)initWithSettings:(TSMuxerSettings * _Nonnull)settings
                                delegate:(id<TSMuxerDelegate> _Nullable)delegate;

/// Enqueue an access unit. Does NOT emit any packets.
/// The PTS and DTS should be in the local/host timescale (i.e. do NOT convert to MPEGTS timescale).
/// Not thread safe — call from the same thread/queue as tick.
-(void)enqueueAccessUnit:(TSAccessUnit* _Nonnull)accessUnit;

/// Emit packets up to the current wall-clock time.
/// In CBR mode: paces content + null packets to maintain targetBitrateKbps.
/// In VBR mode: flushes all queued access units immediately.
/// The caller is responsible for calling this at a regular interval (e.g. every 10ms).
/// Not thread safe — call from the same thread/queue as enqueueAccessUnit:.
-(void)tick;

@end
