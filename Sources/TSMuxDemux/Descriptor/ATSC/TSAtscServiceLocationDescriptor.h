//
//  TSAtscServiceLocationDescriptor.h
//  TSMuxDemux
//
//  ATSC A/65 Service Location Descriptor (tag 0xA1)
//  Provides PID mappings for audio/video streams in a channel.
//

#import <Foundation/Foundation.h>
#import "../TSDescriptor.h"

/// A single elementary stream element within the Service Location Descriptor
@interface TSAtscServiceLocationElement : NSObject

/// Stream type (same values as PMT stream_type)
@property(nonatomic, readonly) uint8_t streamType;

/// Elementary stream PID
@property(nonatomic, readonly) uint16_t elementaryPid;

/// ISO 639 language code (3 chars, e.g., "eng") or empty if not specified
@property(nonatomic, readonly, nonnull) NSString *languageCode;

-(instancetype _Nonnull)initWithStreamType:(uint8_t)streamType
                             elementaryPid:(uint16_t)elementaryPid
                              languageCode:(NSString * _Nonnull)languageCode;

@end

/// ATSC Service Location Descriptor - maps channel to its A/V PIDs
@interface TSAtscServiceLocationDescriptor : TSDescriptor

/// PCR PID for this service
@property(nonatomic, readonly) uint16_t pcrPid;

/// Elementary stream elements (audio, video, data PIDs)
@property(nonatomic, readonly, nonnull) NSArray<TSAtscServiceLocationElement*> *elements;

-(instancetype _Nonnull)initWithTag:(uint8_t)tag
                            payload:(NSData * _Nullable)payload
                             length:(NSUInteger)length;

@end
