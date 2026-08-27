//
//  TSDvbExtensionDescriptor.h
//  TSMuxDemux
//

#import "../TSDescriptor.h"

/// ETSI EN 300 468 extension descriptor (descriptor_tag 0x7F).
/// The first payload byte selects the extended descriptor type; the remaining
/// bytes are type-specific and intentionally left opaque here.
@interface TSDvbExtensionDescriptor : TSDescriptor

@property(nonatomic, readonly) uint8_t descriptorTagExtension;
@property(nonatomic, readonly, nullable) NSData *extensionData;

-(instancetype _Nullable)initWithTag:(uint8_t)tag
                             payload:(NSData * _Nullable)payload
                              length:(NSUInteger)length;

@end
