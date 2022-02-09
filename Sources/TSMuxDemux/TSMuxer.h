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

@end

/// A (basic) "single program" transport stream muxer.
/// Usage: Feed it with access units (in local/host timescale) and receive ts-packets via the delegate method.
@interface TSMuxer : NSObject

@property(nonatomic, weak, nullable) id<TSMuxerDelegate> delegate;

/// Initial muxer settings - cannot be modified after initialisation.
@property(nonatomic, readonly, nonnull) TSMuxerSettings *settings;

/// Throws upon validation error on other initialisation error.
-(instancetype _Nonnull)initWithSettings:(TSMuxerSettings * _Nonnull)settings
                                delegate:(id<TSMuxerDelegate> _Nullable)delegate;

/// Feed the muxer with access units. The PTS and DTS of the access units should be
/// in the local/host timescale (i.e. do NOT convert to MPEGTS timescale).
/// (Currently) not thread safe - i.e. make sure you call this from the same thread.
-(void)mux:(TSAccessUnit* _Nonnull)accessUnit;

@end
