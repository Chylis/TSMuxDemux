//
//  TSPtsParsingTests.m
//  TSMuxDemuxTests
//
//  Tests for PTS/DTS timestamp parsing from PES headers.
//  Verifies the 33-bit timestamp encoding per ITU-T H.222.0 §2.4.3.7.
//

#import <XCTest/XCTest.h>
@import TSMuxDemux;

static const int64_t kTimescale = 90000;  // 90kHz clock

#pragma mark - Helper Functions

/// Encodes a 33-bit timestamp into 5-byte PES format.
/// @param timestamp The 33-bit timestamp value.
/// @param prefix The 4-bit prefix (0x2 for PTS-only, 0x3 for PTS when DTS present, 0x1 for DTS).
/// @param bytes Output buffer (must be at least 5 bytes).
static void encodeTimestamp(uint64_t timestamp, uint8_t prefix, uint8_t *bytes) {
    // Byte 0: [prefix:4][ts32-30:3][marker:1]
    bytes[0] = (prefix << 4) | (((timestamp >> 30) & 0x7) << 1) | 0x01;
    // Byte 1: [ts29-22:8]
    bytes[1] = (timestamp >> 22) & 0xFF;
    // Byte 2: [ts21-15:7][marker:1]
    bytes[2] = (((timestamp >> 15) & 0x7F) << 1) | 0x01;
    // Byte 3: [ts14-7:8]
    bytes[3] = (timestamp >> 7) & 0xFF;
    // Byte 4: [ts6-0:7][marker:1]
    bytes[4] = (((timestamp >> 0) & 0x7F) << 1) | 0x01;
}

/// Creates a TS packet containing a PES header with PTS only.
/// @param pts The PTS value (33-bit timestamp).
/// @return NSData containing the raw TS packet.
static NSData *createPesPacketWithPts(uint64_t pts) {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    // TS Header
    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x41;  // PUSI=1, PID high
    bytes[2] = 0x00;  // PID low
    bytes[3] = 0x10;  // Payload only, CC=0

    // PES Header starts at byte 4
    NSUInteger offset = 4;

    // PES start code (0x00 0x00 0x01)
    bytes[offset++] = 0x00;
    bytes[offset++] = 0x00;
    bytes[offset++] = 0x01;

    // Stream ID (video)
    bytes[offset++] = 0xE0;

    // PES packet length (0 = unbounded)
    bytes[offset++] = 0x00;
    bytes[offset++] = 0x00;

    // Optional PES header
    bytes[offset++] = 0x80;  // '10' marker, no scrambling, no priority, no alignment, no copyright, no original
    bytes[offset++] = 0x80;  // PTS present, no DTS, no ESCR, etc.
    bytes[offset++] = 0x05;  // PES header data length (5 bytes for PTS)

    // PTS (5 bytes)
    encodeTimestamp(pts, 0x2, &bytes[offset]);
    offset += 5;

    // Fill rest with stuffing
    while (offset < TS_PACKET_SIZE_188) {
        bytes[offset++] = 0xFF;
    }

    return packet;
}

/// Creates a TS packet containing a PES header with both PTS and DTS.
/// @param pts The PTS value (33-bit timestamp).
/// @param dts The DTS value (33-bit timestamp).
/// @return NSData containing the raw TS packet.
static NSData *createPesPacketWithPtsAndDts(uint64_t pts, uint64_t dts) {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    // TS Header
    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x41;  // PUSI=1, PID high
    bytes[2] = 0x00;  // PID low
    bytes[3] = 0x10;  // Payload only, CC=0

    // PES Header starts at byte 4
    NSUInteger offset = 4;

    // PES start code
    bytes[offset++] = 0x00;
    bytes[offset++] = 0x00;
    bytes[offset++] = 0x01;

    // Stream ID (video)
    bytes[offset++] = 0xE0;

    // PES packet length (0 = unbounded)
    bytes[offset++] = 0x00;
    bytes[offset++] = 0x00;

    // Optional PES header
    bytes[offset++] = 0x80;  // '10' marker
    bytes[offset++] = 0xC0;  // PTS and DTS present
    bytes[offset++] = 0x0A;  // PES header data length (10 bytes for PTS + DTS)

    // PTS (5 bytes) - prefix 0x3 when DTS is also present
    encodeTimestamp(pts, 0x3, &bytes[offset]);
    offset += 5;

    // DTS (5 bytes) - prefix 0x1
    encodeTimestamp(dts, 0x1, &bytes[offset]);
    offset += 5;

    // Fill rest with stuffing
    while (offset < TS_PACKET_SIZE_188) {
        bytes[offset++] = 0xFF;
    }

    return packet;
}

/// Creates a TS packet with custom PES header bytes for testing invalid cases.
static NSData *createPesPacketWithRawPtsBytes(const uint8_t *ptsBytes) {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    // TS Header
    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x41;
    bytes[2] = 0x00;
    bytes[3] = 0x10;

    NSUInteger offset = 4;

    // PES start code
    bytes[offset++] = 0x00;
    bytes[offset++] = 0x00;
    bytes[offset++] = 0x01;
    bytes[offset++] = 0xE0;  // Stream ID
    bytes[offset++] = 0x00;  // Length high
    bytes[offset++] = 0x00;  // Length low
    bytes[offset++] = 0x80;  // Flags1
    bytes[offset++] = 0x80;  // Flags2 (PTS present)
    bytes[offset++] = 0x05;  // Header data length

    // Copy raw PTS bytes
    memcpy(&bytes[offset], ptsBytes, 5);
    offset += 5;

    while (offset < TS_PACKET_SIZE_188) {
        bytes[offset++] = 0xFF;
    }

    return packet;
}

#pragma mark - Tests

@interface TSPtsParsingTests : XCTestCase
@end

@implementation TSPtsParsingTests

#pragma mark - PTS-Only Tests

- (void)test_ptsOnly_zeroValue {
    NSData *packet = createPesPacketWithPts(0);
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

    TSPesHeader *header = [TSPesHeader parseFromPacket:packets.firstObject];

    XCTAssertNotNil(header);
    XCTAssertTrue(CMTIME_IS_VALID(header.pts));
    XCTAssertEqual(header.pts.value, 0);
    XCTAssertEqual(header.pts.timescale, kTimescale);
    XCTAssertTrue(CMTIME_IS_INVALID(header.dts));
}

- (void)test_ptsOnly_oneSecond {
    uint64_t oneSecondPts = 90000;  // 90kHz * 1s
    NSData *packet = createPesPacketWithPts(oneSecondPts);
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

    TSPesHeader *header = [TSPesHeader parseFromPacket:packets.firstObject];

    XCTAssertNotNil(header);
    XCTAssertTrue(CMTIME_IS_VALID(header.pts));
    XCTAssertEqual(header.pts.value, oneSecondPts);
    XCTAssertEqualWithAccuracy(CMTimeGetSeconds(header.pts), 1.0, 0.0001);
}

- (void)test_ptsOnly_oneHour {
    uint64_t oneHourPts = 90000ULL * 3600;  // 324,000,000
    NSData *packet = createPesPacketWithPts(oneHourPts);
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

    TSPesHeader *header = [TSPesHeader parseFromPacket:packets.firstObject];

    XCTAssertNotNil(header);
    XCTAssertTrue(CMTIME_IS_VALID(header.pts));
    XCTAssertEqual(header.pts.value, oneHourPts);
    XCTAssertEqualWithAccuracy(CMTimeGetSeconds(header.pts), 3600.0, 0.0001);
}

- (void)test_ptsOnly_maxValue {
    // Maximum 33-bit value: 2^33 - 1 = 8589934591
    // This represents ~26.5 hours at 90kHz
    uint64_t maxPts = 0x1FFFFFFFFULL;
    NSData *packet = createPesPacketWithPts(maxPts);
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

    TSPesHeader *header = [TSPesHeader parseFromPacket:packets.firstObject];

    XCTAssertNotNil(header);
    XCTAssertTrue(CMTIME_IS_VALID(header.pts));
    XCTAssertEqual(header.pts.value, maxPts);

    // ~26.5 hours = 95443.717 seconds
    double expectedSeconds = (double)maxPts / 90000.0;
    XCTAssertEqualWithAccuracy(CMTimeGetSeconds(header.pts), expectedSeconds, 0.001);
}

- (void)test_ptsOnly_allBitsSet {
    // Test with specific bit patterns to verify extraction
    // PTS = 0x123456789 (a value that uses multiple bit fields)
    uint64_t pts = 0x123456789ULL;
    NSData *packet = createPesPacketWithPts(pts);
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

    TSPesHeader *header = [TSPesHeader parseFromPacket:packets.firstObject];

    XCTAssertNotNil(header);
    XCTAssertTrue(CMTIME_IS_VALID(header.pts));
    XCTAssertEqual(header.pts.value, pts);
}

#pragma mark - PTS + DTS Tests

- (void)test_ptsAndDts_basicValues {
    // DTS should be <= PTS (DTS is decode time, PTS is presentation time)
    uint64_t pts = 90000;  // 1 second
    uint64_t dts = 87000;  // Slightly earlier

    NSData *packet = createPesPacketWithPtsAndDts(pts, dts);
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

    TSPesHeader *header = [TSPesHeader parseFromPacket:packets.firstObject];

    XCTAssertNotNil(header);
    XCTAssertTrue(CMTIME_IS_VALID(header.pts));
    XCTAssertTrue(CMTIME_IS_VALID(header.dts));
    XCTAssertEqual(header.pts.value, pts);
    XCTAssertEqual(header.dts.value, dts);
}

- (void)test_ptsAndDts_sameValue {
    // For I-frames, PTS == DTS
    uint64_t timestamp = 180000;

    NSData *packet = createPesPacketWithPtsAndDts(timestamp, timestamp);
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

    TSPesHeader *header = [TSPesHeader parseFromPacket:packets.firstObject];

    XCTAssertNotNil(header);
    XCTAssertEqual(header.pts.value, timestamp);
    XCTAssertEqual(header.dts.value, timestamp);
    XCTAssertEqual(CMTimeCompare(header.pts, header.dts), 0);
}

- (void)test_ptsAndDts_bFramePattern {
    // B-frame typical pattern: DTS is 2-3 frame durations before PTS
    // At 30fps, frame duration = 90000/30 = 3000 ticks
    uint64_t pts = 90000 + (3 * 3000);  // Frame 4 presentation
    uint64_t dts = 90000;                // Frame 1 decode time

    NSData *packet = createPesPacketWithPtsAndDts(pts, dts);
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

    TSPesHeader *header = [TSPesHeader parseFromPacket:packets.firstObject];

    XCTAssertNotNil(header);
    XCTAssertEqual(header.pts.value, pts);
    XCTAssertEqual(header.dts.value, dts);
    XCTAssertGreaterThan(header.pts.value, header.dts.value);
}

- (void)test_ptsAndDts_largeValues {
    // Test large values near 33-bit limit
    uint64_t pts = 0x1FFFFFFF0ULL;
    uint64_t dts = 0x1FFFFFFD0ULL;

    NSData *packet = createPesPacketWithPtsAndDts(pts, dts);
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

    TSPesHeader *header = [TSPesHeader parseFromPacket:packets.firstObject];

    XCTAssertNotNil(header);
    XCTAssertEqual(header.pts.value, pts);
    XCTAssertEqual(header.dts.value, dts);
}

#pragma mark - Invalid Marker Bit Tests

- (void)test_invalidMarkerBit_byte0 {
    // Create PTS bytes with invalid marker bit in byte 0
    uint8_t ptsBytes[5];
    encodeTimestamp(90000, 0x2, ptsBytes);
    ptsBytes[0] &= 0xFE;  // Clear marker bit in byte 0

    NSData *packet = createPesPacketWithRawPtsBytes(ptsBytes);
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

    TSPesHeader *header = [TSPesHeader parseFromPacket:packets.firstObject];

    XCTAssertNotNil(header);
    XCTAssertTrue(CMTIME_IS_INVALID(header.pts), @"PTS should be invalid with bad marker bit");
}

- (void)test_invalidMarkerBit_byte2 {
    uint8_t ptsBytes[5];
    encodeTimestamp(90000, 0x2, ptsBytes);
    ptsBytes[2] &= 0xFE;  // Clear marker bit in byte 2

    NSData *packet = createPesPacketWithRawPtsBytes(ptsBytes);
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

    TSPesHeader *header = [TSPesHeader parseFromPacket:packets.firstObject];

    XCTAssertNotNil(header);
    XCTAssertTrue(CMTIME_IS_INVALID(header.pts), @"PTS should be invalid with bad marker bit");
}

- (void)test_invalidMarkerBit_byte4 {
    uint8_t ptsBytes[5];
    encodeTimestamp(90000, 0x2, ptsBytes);
    ptsBytes[4] &= 0xFE;  // Clear marker bit in byte 4

    NSData *packet = createPesPacketWithRawPtsBytes(ptsBytes);
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

    TSPesHeader *header = [TSPesHeader parseFromPacket:packets.firstObject];

    XCTAssertNotNil(header);
    XCTAssertTrue(CMTIME_IS_INVALID(header.pts), @"PTS should be invalid with bad marker bit");
}

#pragma mark - Invalid Prefix Tests

- (void)test_invalidPrefix_wrongValue {
    // PTS-only should have prefix 0x2, test with wrong prefix 0x3
    uint8_t ptsBytes[5];
    encodeTimestamp(90000, 0x3, ptsBytes);  // Wrong prefix for PTS-only

    NSData *packet = createPesPacketWithRawPtsBytes(ptsBytes);
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

    TSPesHeader *header = [TSPesHeader parseFromPacket:packets.firstObject];

    XCTAssertNotNil(header);
    XCTAssertTrue(CMTIME_IS_INVALID(header.pts), @"PTS should be invalid with wrong prefix");
}

#pragma mark - Precision Tests

- (void)test_precisionAtFrameBoundaries_30fps {
    // Test that PTS values at exact frame boundaries are preserved
    int64_t frameDuration = 3000;  // 90000 / 30 = 3000 ticks per frame

    for (int frame = 0; frame < 10; frame++) {
        uint64_t pts = frame * frameDuration;
        NSData *packet = createPesPacketWithPts(pts);
        NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

        TSPesHeader *header = [TSPesHeader parseFromPacket:packets.firstObject];

        XCTAssertEqual(header.pts.value, pts, @"Frame %d PTS mismatch", frame);
    }
}

- (void)test_precisionAtFrameBoundaries_2997fps {
    // 29.97fps (NTSC) = 90000 * 1001 / 30000 = 3003 ticks per frame
    int64_t frameDuration = 3003;

    for (int frame = 0; frame < 10; frame++) {
        uint64_t pts = frame * frameDuration;
        NSData *packet = createPesPacketWithPts(pts);
        NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

        TSPesHeader *header = [TSPesHeader parseFromPacket:packets.firstObject];

        XCTAssertEqual(header.pts.value, pts, @"Frame %d PTS mismatch", frame);
    }
}

@end
