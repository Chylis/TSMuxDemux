//
//  TSElementaryStreamTests.m
//  TSMuxDemuxTests
//
//  Tests for TSElementaryStream.
//

#import <XCTest/XCTest.h>
@import TSMuxDemux;

@interface TSElementaryStreamTests : XCTestCase
@end

@implementation TSElementaryStreamTests

#pragma mark - Continuity Counter Tests

- (void)test_continuityCounter_wrapsAt16 {
    // Continuity counter is a 4-bit field (0-15), should wrap at 16
    TSElementaryStream *stream = [[TSElementaryStream alloc] initWithPid:256
                                                              streamType:kRawStreamTypeADTSAAC
                                                             descriptors:nil];

    // Set to max uint8 value
    stream.continuityCounter = UINT8_MAX;

    // Should wrap to 15 (UINT8_MAX % 16 = 255 % 16 = 15)
    XCTAssertEqual(stream.continuityCounter, (uint8_t)(UINT8_MAX % 16));
}

- (void)test_continuityCounter_incrementsCorrectly {
    TSElementaryStream *stream = [[TSElementaryStream alloc] initWithPid:100
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];

    // Start at 0
    stream.continuityCounter = 0;
    XCTAssertEqual(stream.continuityCounter, (uint8_t)0);

    // Increment through valid range
    for (uint8_t i = 1; i <= 15; i++) {
        stream.continuityCounter = i;
        XCTAssertEqual(stream.continuityCounter, i);
    }

    // At 16 it should wrap to 0
    stream.continuityCounter = 16;
    XCTAssertEqual(stream.continuityCounter, (uint8_t)0);

    // At 17 it should be 1
    stream.continuityCounter = 17;
    XCTAssertEqual(stream.continuityCounter, (uint8_t)1);
}

- (void)test_continuityCounter_multipleWraps {
    TSElementaryStream *stream = [[TSElementaryStream alloc] initWithPid:200
                                                              streamType:kRawStreamTypeADTSAAC
                                                             descriptors:nil];

    // Test values that would wrap multiple times
    stream.continuityCounter = 32;  // 32 % 16 = 0
    XCTAssertEqual(stream.continuityCounter, (uint8_t)0);

    stream.continuityCounter = 47;  // 47 % 16 = 15
    XCTAssertEqual(stream.continuityCounter, (uint8_t)15);

    stream.continuityCounter = 100; // 100 % 16 = 4
    XCTAssertEqual(stream.continuityCounter, (uint8_t)4);
}

#pragma mark - Initialization Tests

- (void)test_initialization_properties {
    const uint16_t testPid = 0x100;
    const uint8_t testStreamType = kRawStreamTypeH264;

    TSElementaryStream *stream = [[TSElementaryStream alloc] initWithPid:testPid
                                                              streamType:testStreamType
                                                             descriptors:nil];

    XCTAssertEqual(stream.pid, testPid);
    XCTAssertEqual(stream.streamType, testStreamType);
    XCTAssertNil(stream.descriptors);
}

- (void)test_initialization_pidRange {
    // PID is 13 bits (0-8191), but certain ranges are reserved
    uint16_t validPids[] = {0x20, 0x100, 0x1000, 0x1FFE};

    for (int i = 0; i < 4; i++) {
        TSElementaryStream *stream = [[TSElementaryStream alloc] initWithPid:validPids[i]
                                                                  streamType:kRawStreamTypeH264
                                                                 descriptors:nil];
        XCTAssertEqual(stream.pid, validPids[i]);
    }
}

#pragma mark - Stream Type Tests

- (void)test_isVideo_H264 {
    TSElementaryStream *stream = [[TSElementaryStream alloc] initWithPid:256
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    XCTAssertTrue([stream isVideo]);
    XCTAssertFalse([stream isAudio]);
}

- (void)test_isAudio_AAC {
    TSElementaryStream *stream = [[TSElementaryStream alloc] initWithPid:257
                                                              streamType:kRawStreamTypeADTSAAC
                                                             descriptors:nil];
    XCTAssertTrue([stream isAudio]);
    XCTAssertFalse([stream isVideo]);
}

- (void)test_resolvedStreamType_H264 {
    TSElementaryStream *stream = [[TSElementaryStream alloc] initWithPid:256
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    XCTAssertEqual([stream resolvedStreamType], TSResolvedStreamTypeH264);
}

- (void)test_resolvedStreamType_AAC {
    TSElementaryStream *stream = [[TSElementaryStream alloc] initWithPid:257
                                                              streamType:kRawStreamTypeADTSAAC
                                                             descriptors:nil];
    XCTAssertEqual([stream resolvedStreamType], TSResolvedStreamTypeAAC_ADTS);
}

@end
