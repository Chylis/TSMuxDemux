//
//  TSPesHeader.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
@class TSPacket;

/// Lightweight PES header parser that extracts timestamps and payload offset
/// without copying the payload data.
///
/// See "Rec. ITU-T H.222.0 (03/2017)" section "2.4.3.6 PES packet" page 37
@interface TSPesHeader : NSObject

/// Presentation timestamp. Set to kCMTimeInvalid if not present.
@property (nonatomic, readonly) CMTime pts;

/// Decode timestamp. Set to kCMTimeInvalid if not present.
@property (nonatomic, readonly) CMTime dts;

/// Whether the packet has the discontinuity flag set.
@property (nonatomic, readonly) BOOL isDiscontinuous;

/// Offset in packet.payload where the actual PES payload begins (after headers).
@property (nonatomic, readonly) NSUInteger payloadOffset;

/// PES packet length from header. 0 means unbounded (common for video).
@property (nonatomic, readonly) uint16_t pesPacketLength;

/// Parses the PES header from a TS packet with PUSI=true.
/// Returns nil if the packet does not contain a valid PES header.
+ (instancetype _Nullable)parseFromPacket:(TSPacket * _Nonnull)packet;

@end
