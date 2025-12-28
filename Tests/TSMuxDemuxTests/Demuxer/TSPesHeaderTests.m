//
//  TSPesHeaderTests.m
//  TSMuxDemuxTests
//
//  Tests for TSPesHeader parsing (demuxer functionality).
//

#import <XCTest/XCTest.h>
#import "../TSTestUtils.h"
@import TSMuxDemux;

@interface TSPesHeaderTests : XCTestCase
@end

@implementation TSPesHeaderTests

#pragma mark - Stream IDs With No Optional Header

- (void)test_paddingStream_noOptionalHeader {
    // padding_stream (0xBE) has no optional header, payload starts at byte 6
    NSMutableData *pes = [NSMutableData data];
    uint8_t header[] = {0x00, 0x00, 0x01, 0xBE, 0x00, 0x10};
    [pes appendBytes:header length:6];
    for (int i = 0; i < 16; i++) {
        uint8_t pad = 0xFF;
        [pes appendBytes:&pad length:1];
    }

    TSPacket *packet = [TSTestUtils createPacketWithPesPayload:pes];
    TSPesHeader *pesHeader = [TSPesHeader parseFromPacket:packet];

    XCTAssertNotNil(pesHeader);
    XCTAssertEqual(pesHeader.payloadOffset, 6);
    XCTAssertTrue(CMTIME_IS_INVALID(pesHeader.pts));
}

- (void)test_ecmStream_noOptionalHeader {
    // ECM_stream (0xF0) has no optional header
    NSMutableData *pes = [NSMutableData data];
    uint8_t header[] = {0x00, 0x00, 0x01, 0xF0, 0x00, 0x08};
    [pes appendBytes:header length:6];
    uint8_t data[] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08};
    [pes appendBytes:data length:8];

    TSPacket *packet = [TSTestUtils createPacketWithPesPayload:pes];
    TSPesHeader *pesHeader = [TSPesHeader parseFromPacket:packet];

    XCTAssertNotNil(pesHeader);
    XCTAssertEqual(pesHeader.payloadOffset, 6);
}

- (void)test_emmStream_noOptionalHeader {
    // EMM_stream (0xF1) has no optional header
    NSMutableData *pes = [NSMutableData data];
    uint8_t header[] = {0x00, 0x00, 0x01, 0xF1, 0x00, 0x08};
    [pes appendBytes:header length:6];
    uint8_t data[] = {0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88};
    [pes appendBytes:data length:8];

    TSPacket *packet = [TSTestUtils createPacketWithPesPayload:pes];
    TSPesHeader *pesHeader = [TSPesHeader parseFromPacket:packet];

    XCTAssertNotNil(pesHeader);
    XCTAssertEqual(pesHeader.payloadOffset, 6);
}

- (void)test_privateStream2_noOptionalHeader {
    // private_stream_2 (0xBF) has no optional header
    NSMutableData *pes = [NSMutableData data];
    uint8_t header[] = {0x00, 0x00, 0x01, 0xBF, 0x00, 0x04};
    [pes appendBytes:header length:6];
    uint8_t data[] = {0xDE, 0xAD, 0xBE, 0xEF};
    [pes appendBytes:data length:4];

    TSPacket *packet = [TSTestUtils createPacketWithPesPayload:pes];
    TSPesHeader *pesHeader = [TSPesHeader parseFromPacket:packet];

    XCTAssertNotNil(pesHeader);
    XCTAssertEqual(pesHeader.payloadOffset, 6);
}

@end
