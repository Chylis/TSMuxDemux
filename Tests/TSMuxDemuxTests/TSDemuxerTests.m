//
//  TSDemuxerTests.m
//  TSMuxDemuxTests
//
//  Tests for TSDemuxer packet size auto-detection.
//

#import <XCTest/XCTest.h>
@import TSMuxDemux;

@interface TSDemuxerTests : XCTestCase
@end

@implementation TSDemuxerTests

#pragma mark - Helper Methods

/// Creates valid TS packet data with proper sync bytes and null packet PID (0x1FFF)
- (NSData *)createValidTsPackets:(NSUInteger)count packetSize:(NSUInteger)size {
    NSMutableData *chunk = [NSMutableData dataWithCapacity:count * size];
    for (NSUInteger i = 0; i < count; i++) {
        NSMutableData *packet = [NSMutableData dataWithLength:size];
        uint8_t *bytes = packet.mutableBytes;
        bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;  // 0x47
        bytes[1] = 0x1F;                         // PID high bits (null packet)
        bytes[2] = 0xFF;                         // PID low bits (0x1FFF = null packet)
        bytes[3] = 0x10;                         // Payload only, CC=0
        [chunk appendData:packet];
    }
    return chunk;
}

#pragma mark - Packet Size Detection Tests

- (void)test_detectPacketSize_188 {
    // 2 * 188 = 376 (divisible by 188 only, not by 204)
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];
    NSData *chunk = [self createValidTsPackets:2 packetSize:TS_PACKET_SIZE_188];
    [demuxer demux:chunk dataArrivalHostTimeNanos:0];
    XCTAssertEqual(demuxer.packetSize, (NSUInteger)TS_PACKET_SIZE_188);
}

- (void)test_detectPacketSize_204 {
    // 2 * 204 = 408 (divisible by 204 only, not by 188)
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];
    NSData *chunk = [self createValidTsPackets:2 packetSize:TS_PACKET_SIZE_204];
    [demuxer demux:chunk dataArrivalHostTimeNanos:0];
    XCTAssertEqual(demuxer.packetSize, (NSUInteger)TS_PACKET_SIZE_204);
}

- (void)test_detectPacketSize_ambiguous_defaults188 {
    // 9588 bytes is divisible by both 188 (51 packets) and 204 (47 packets)
    // LCM(188, 204) = 9588
    // Should default to 188-byte packets
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];
    NSData *chunk = [self createValidTsPackets:51 packetSize:TS_PACKET_SIZE_188];
    [demuxer demux:chunk dataArrivalHostTimeNanos:0];
    XCTAssertEqual(demuxer.packetSize, (NSUInteger)TS_PACKET_SIZE_188);
}

- (void)test_detectPacketSize_singlePacket188 {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];
    NSData *chunk = [self createValidTsPackets:1 packetSize:TS_PACKET_SIZE_188];
    [demuxer demux:chunk dataArrivalHostTimeNanos:0];
    XCTAssertEqual(demuxer.packetSize, (NSUInteger)TS_PACKET_SIZE_188);
}

- (void)test_detectPacketSize_singlePacket204 {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];
    NSData *chunk = [self createValidTsPackets:1 packetSize:TS_PACKET_SIZE_204];
    [demuxer demux:chunk dataArrivalHostTimeNanos:0];
    XCTAssertEqual(demuxer.packetSize, (NSUInteger)TS_PACKET_SIZE_204);
}

- (void)test_detectPacketSize_persistsAfterFirstCall {
    // Once detected, packet size should persist for subsequent calls
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // First call with 204-byte data
    NSData *chunk204 = [self createValidTsPackets:1 packetSize:TS_PACKET_SIZE_204];
    [demuxer demux:chunk204 dataArrivalHostTimeNanos:0];
    XCTAssertEqual(demuxer.packetSize, (NSUInteger)TS_PACKET_SIZE_204);

    // Second call with different data should NOT change the detected size
    NSData *chunk2 = [self createValidTsPackets:2 packetSize:TS_PACKET_SIZE_204];
    [demuxer demux:chunk2 dataArrivalHostTimeNanos:0];
    XCTAssertEqual(demuxer.packetSize, (NSUInteger)TS_PACKET_SIZE_204);
}

@end
