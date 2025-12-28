//
//  TSAdaptationFieldTests.m
//  TSMuxDemuxTests
//
//  Tests for adaptation field parsing including PCR (demuxer functionality).
//

#import <XCTest/XCTest.h>
#import "../TSTestUtils.h"
@import TSMuxDemux;

@interface TSAdaptationFieldTests : XCTestCase
@end

@implementation TSAdaptationFieldTests

#pragma mark - PCR Parsing Tests

- (void)test_pcrParsing_validPcr {
    // PCR: base=90000 (1 second at 90kHz)
    TSPacket *parsed = [TSTestUtils createPacketWithPid:0x20 pcrBase:90000 pcrExt:0 continuityCounter:0];

    XCTAssertNotNil(parsed.adaptationField);
    XCTAssertTrue(parsed.adaptationField.pcrFlag);
    XCTAssertEqual(parsed.adaptationField.pcrBase, 90000ULL);
    XCTAssertEqual(parsed.adaptationField.pcrExt, 0);
}

- (void)test_pcrParsing_withExtension {
    uint64_t pcrBase = 12345678;
    uint16_t pcrExt = 123;
    TSPacket *parsed = [TSTestUtils createPacketWithPid:0x20 pcrBase:pcrBase pcrExt:pcrExt continuityCounter:0];

    XCTAssertEqual(parsed.adaptationField.pcrBase, pcrBase);
    XCTAssertEqual(parsed.adaptationField.pcrExt, pcrExt);
}

- (void)test_pcrParsing_noPcrFlag {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x00;
    bytes[2] = 0x20;
    bytes[3] = 0x30;  // Adaptation + payload

    bytes[4] = 1;       // adaptation_field_length (just flags byte)
    bytes[5] = 0x00;    // No flags set

    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];
    TSPacket *parsed = packets.firstObject;

    XCTAssertNotNil(parsed.adaptationField);
    XCTAssertFalse(parsed.adaptationField.pcrFlag);
    XCTAssertEqual(parsed.adaptationField.pcrBase, 0ULL);
}

- (void)test_pcrParsing_largePcrBase {
    uint64_t pcrBase = 0x1FFFFFFFFULL;  // Max 33-bit value
    TSPacket *parsed = [TSTestUtils createPacketWithPid:0x20 pcrBase:pcrBase pcrExt:0 continuityCounter:0];

    XCTAssertEqual(parsed.adaptationField.pcrBase, pcrBase);
}

@end
