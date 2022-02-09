//
//  TSElementaryStream.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSAccessUnit.h"

@interface TSElementaryStream: NSObject

/// Each ts-packet is tagged with a PID value indicating to which elementary stream its payload belongs.
@property(nonatomic, readonly) uint16_t pid;
@property(nonatomic, readonly) TSStreamType streamType;

/// A 4-bit field incrementing with each ts-packet with the same PID. Wraps to 0 after its max value of 15 (max value = 2^4=16).
@property(nonatomic) uint8_t continuityCounter;

-(instancetype _Nonnull)initWithPid:(uint16_t)pid streamType:(TSStreamType)streamType;

@end

