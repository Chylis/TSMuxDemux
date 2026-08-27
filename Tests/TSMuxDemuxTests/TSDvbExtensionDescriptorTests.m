//
//  TSDvbExtensionDescriptorTests.m
//  TSMuxDemuxTests
//

#import <XCTest/XCTest.h>
@import TSMuxDemux;

static const uint8_t kPrivateDataStreamType = 0x06;

@interface TSDvbExtensionDescriptorTests : XCTestCase
@end

@implementation TSDvbExtensionDescriptorTests

-(TSDescriptor *)descriptorWithBytes:(const uint8_t *)bytes length:(NSUInteger)length
{
    NSData *payload = [NSData dataWithBytes:bytes length:length];
    return [TSDescriptor makeWithTag:TSDvbDescriptorTagExtension
                              length:(uint8_t)length
                                data:payload];
}

-(void)test_ac4DescriptorParsesExtensionTagAndData
{
    const uint8_t bytes[] = { TSExtensionDescriptorTagAc4, 0x00 };
    TSDescriptor *descriptor = [self descriptorWithBytes:bytes length:sizeof(bytes)];

    XCTAssertTrue([descriptor isKindOfClass:[TSDvbExtensionDescriptor class]]);
    TSDvbExtensionDescriptor *extension = (TSDvbExtensionDescriptor *)descriptor;
    XCTAssertEqual(extension.descriptorTagExtension, TSExtensionDescriptorTagAc4);
    XCTAssertEqualObjects(extension.extensionData, [NSData dataWithBytes:&bytes[1] length:1]);
    XCTAssertEqualObjects(extension.tagDescription, @"Extension: AC-4");
}

-(void)test_extensionDescriptorEqualityIncludesTypeSpecificData
{
    const uint8_t firstBytes[] = { TSExtensionDescriptorTagAc4, 0x00 };
    const uint8_t secondBytes[] = { TSExtensionDescriptorTagAc4, 0x01 };
    TSDescriptor *first = [self descriptorWithBytes:firstBytes length:sizeof(firstBytes)];
    TSDescriptor *same = [self descriptorWithBytes:firstBytes length:sizeof(firstBytes)];
    TSDescriptor *different = [self descriptorWithBytes:secondBytes length:sizeof(secondBytes)];

    XCTAssertEqualObjects(first, same);
    XCTAssertEqual(first.hash, same.hash);
    XCTAssertNotEqualObjects(first, different);
}

-(void)test_truncatedExtensionDescriptorIsRejected
{
    XCTAssertNil([TSDescriptor makeWithTag:TSDvbDescriptorTagExtension length:1 data:nil]);

    const uint8_t selector = TSExtensionDescriptorTagAc4;
    NSData *shortPayload = [NSData dataWithBytes:&selector length:1];
    XCTAssertNil([TSDescriptor makeWithTag:TSDvbDescriptorTagExtension
                                    length:2
                                      data:shortPayload]);
}

-(void)test_privateDataWithAc4ExtensionResolvesAsUnsupportedAudioCodec
{
    const uint8_t bytes[] = { TSExtensionDescriptorTagAc4, 0x00 };
    TSDescriptor *descriptor = [self descriptorWithBytes:bytes length:sizeof(bytes)];
    TSElementaryStream *stream = [[TSElementaryStream alloc] initWithPid:64
                                                              streamType:kPrivateDataStreamType
                                                             descriptors:@[descriptor]];

    XCTAssertEqual(stream.resolvedStreamType, TSResolvedStreamTypeAC4);
    XCTAssertTrue(stream.isAudio);
    XCTAssertFalse(stream.isVideo);
    XCTAssertEqualObjects([TSStreamType descriptionForResolvedStreamType:stream.resolvedStreamType], @"AC-4");
}

-(void)test_otherOrUnparsedExtensionsDoNotResolveAsAc4
{
    const uint8_t otherBytes[] = { 0x19, 0x08 };
    TSDescriptor *otherExtension = [self descriptorWithBytes:otherBytes length:sizeof(otherBytes)];
    TSElementaryStream *other = [[TSElementaryStream alloc] initWithPid:64
                                                             streamType:kPrivateDataStreamType
                                                            descriptors:@[otherExtension]];
    XCTAssertEqual(other.resolvedStreamType, TSResolvedStreamTypeUnknown);
    XCTAssertFalse(other.isAudio);

    TSDescriptor *unparsed = [[TSDescriptor alloc] initWithTag:TSDvbDescriptorTagExtension length:2];
    TSElementaryStream *generic = [[TSElementaryStream alloc] initWithPid:64
                                                               streamType:kPrivateDataStreamType
                                                              descriptors:@[unparsed]];
    XCTAssertEqual(generic.resolvedStreamType, TSResolvedStreamTypeUnknown);

    const uint8_t ac4Bytes[] = { TSExtensionDescriptorTagAc4, 0x00 };
    NSData *ac4Payload = [NSData dataWithBytes:ac4Bytes length:sizeof(ac4Bytes)];
    TSDvbExtensionDescriptor *wrongOuterTag = [[TSDvbExtensionDescriptor alloc]
                                               initWithTag:TSDescriptorTagAudioStream
                                               payload:ac4Payload
                                               length:sizeof(ac4Bytes)];
    TSElementaryStream *notAnExtension = [[TSElementaryStream alloc]
                                          initWithPid:64
                                          streamType:kPrivateDataStreamType
                                          descriptors:@[wrongOuterTag]];
    XCTAssertEqual(notAnExtension.resolvedStreamType, TSResolvedStreamTypeUnknown);
}

@end
