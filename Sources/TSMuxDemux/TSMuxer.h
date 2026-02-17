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

/// PID for the PMT. Must be a valid custom PID (not reserved/occupied).
@property(nonatomic) uint16_t pmtPid;

/// PID that carries the PCR for program 1. Must be a valid custom PID.
/// Typically set to the same value as videoPid.
@property(nonatomic) uint16_t pcrPid;

/// PID for the video elementary stream. Must be a valid custom PID.
@property(nonatomic) uint16_t videoPid;

/// PID for the audio elementary stream. Must be a valid custom PID.
/// Must differ from videoPid.
@property(nonatomic) uint16_t audioPid;

/// How often to send PSI tables (PAT, PMT, etc), in milliseconds. Must be > 0.
/// The PAT should, according to TR101290, occur at least every 0.5 sec.
@property(nonatomic) NSUInteger psiIntervalMs;

/// How often to emit PCR, in milliseconds. Must be > 0.
/// ISO 13818-1 §2.7.2 recommends at most 40ms between PCRs.
@property(nonatomic) NSUInteger pcrIntervalMs;

/// Target total TS output bitrate in kilobits per second.
/// This is the wire-level rate including all TS overhead (packet headers, PES headers,
/// adaptation fields, PSI tables, null stuffing) — not the content payload rate.
/// Callers should configure their encoder bitrate below this value to leave room
/// for TS overhead; otherwise the muxer's AU queue will overflow and drop access units.
/// When set to 0, the muxer operates in VBR mode (no pacing, no null packets).
/// When > 0, the muxer operates in CBR mode: tick paces output at this rate, inserting
/// null packets (PID 0x1FFF) when no content is available to maintain a constant bitrate.
@property(nonatomic) NSUInteger targetBitrateKbps;

/// Maximum number of queued access units before oldest are dropped.
/// When 0, the queue is unlimited.
@property(nonatomic) NSUInteger maxNumQueuedAccessUnits;

@end

/// A (basic) "single program" transport stream muxer.
/// Usage: Feed it with access units (in local/host timescale) and receive ts-packets via the delegate method.
/// PTS/DTS are epoch-relative (offset so the stream starts at zero).
/// PCR derives from virtual transport time in CBR (byte-position-driven) or wall clock in VBR.
@interface TSMuxer : NSObject

@property(nonatomic, weak, nullable) id<TSMuxerDelegate> delegate;

/// Initial muxer settings - cannot be modified after initialisation.
@property(nonatomic, readonly, nonnull) TSMuxerSettings *settings;

/// Wall clock for the muxer, in nanoseconds. Used for CBR pacing and VBR transport time.
/// Must be monotonic. In VBR mode, must be the same clock used for AU PTS/DTS timestamps
/// (PCR derives directly from it). In CBR mode, PCR derives from virtual transport time instead.
@property(nonatomic, copy, readonly, nonnull) uint64_t (^wallClockNanos)(void);

/// Throws upon validation error on other initialisation error.
-(instancetype _Nonnull)initWithSettings:(TSMuxerSettings * _Nonnull)settings
                         wallClockNanos:(uint64_t (^ _Nonnull)(void))wallClockNanos
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
