//
//  TSElementaryStream.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSAccessUnit.h"
@class TSDescriptor;
@class TSRegistrationDescriptor;
@class TSISO639LanguageDescriptor;
@class TSHEVCVideoDescriptor;
@class TSScte35CueIdentifierDescriptor;

@interface TSElementaryStream: NSObject

/// Each ts-packet is tagged with a PID value indicating to which elementary stream its payload belongs.
@property(nonatomic, readonly) uint16_t pid;
@property(nonatomic, readonly) uint8_t streamType;
@property(nonatomic, readonly, nullable) NSArray<TSDescriptor*>* descriptors;

/// A 4-bit field incrementing with each ts-packet with the same PID. Wraps to 0 after its max value of 15 (max value = 2^4=16).
@property(nonatomic) uint8_t continuityCounter;


-(instancetype _Nonnull)initWithPid:(uint16_t)pid
                         streamType:(uint8_t)streamType
                        descriptors:(NSArray<TSDescriptor*>* _Nullable)descriptors;

-(TSResolvedStreamType)resolvedStreamType;
-(BOOL)isAudio;
-(BOOL)isVideo;

#pragma mark - Util - Implemented/Parsed Descriptor Accessors

/// Returns all registration descriptors (tag 0x05) from this stream's descriptor loop.
-(NSArray<TSRegistrationDescriptor*>* _Nonnull)registrationDescriptors;

/// Returns all ISO 639 language descriptors (tag 0x0A) from this stream's descriptor loop.
-(NSArray<TSISO639LanguageDescriptor*>* _Nonnull)languageDescriptors;

/// Returns all HEVC video descriptors (tag 0x38) from this stream's descriptor loop.
-(NSArray<TSHEVCVideoDescriptor*>* _Nonnull)hevcVideoDescriptors;

/// Returns all SCTE-35 cue identifier descriptors (tag 0x8A) from this stream's descriptor loop.
-(NSArray<TSScte35CueIdentifierDescriptor*>* _Nonnull)scte35CueIdentifierDescriptors;

@end

