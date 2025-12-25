//
//  TSPacketFormatTests.m
//  TSMuxDemuxTests
//
//  Tests for 188-byte and 204-byte TS packet parsing.
//

#import <XCTest/XCTest.h>
@import TSMuxDemux;

@interface TSPacketFormatTests : XCTestCase
@end

@implementation TSPacketFormatTests

#pragma mark - 188-byte Packet Format Tests

- (void)test_packetsFromChunkedTsData_188Format {
    // Create 3 valid 188-byte TS packets
    NSUInteger numberOfPackets = 3;
    NSMutableData *chunk = [NSMutableData data];

    for (NSUInteger i = 0; i < numberOfPackets; i++) {
        NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
        uint8_t *bytes = packet.mutableBytes;
        bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;  // Sync byte 0x47
        bytes[1] = 0x00;                         // TEI=0, PUSI=0, Prio=0, PID high bits=0
        bytes[2] = (uint8_t)(i + 1);             // PID low bits
        bytes[3] = 0x10;                         // Scrambling=0, Adaptation=payload only, CC=0
        [chunk appendData:packet];
    }

    NSArray<TSPacket*> *packets = [TSPacket packetsFromChunkedTsData:chunk packetSize:TS_PACKET_SIZE_188];
    XCTAssertEqual(packets.count, numberOfPackets);

    for (NSUInteger i = 0; i < packets.count; i++) {
        TSPacket *packet = packets[i];
        XCTAssertEqual(packet.header.syncByte, TS_PACKET_HEADER_SYNC_BYTE);
        XCTAssertEqual(packet.header.pid, (uint16_t)(i + 1));
    }
}

#pragma mark - 204-byte Packet Format Tests

- (void)test_packetsFromChunkedTsData_204Format {
    // Create 3 valid 204-byte TS packets (188 + 16 RS parity)
    NSUInteger numberOfPackets = 3;
    NSMutableData *chunk = [NSMutableData data];

    for (NSUInteger i = 0; i < numberOfPackets; i++) {
        NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_204];
        uint8_t *bytes = packet.mutableBytes;
        bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;  // Sync byte 0x47
        bytes[1] = 0x00;                         // TEI=0, PUSI=0, Prio=0, PID high bits=0
        bytes[2] = (uint8_t)(i + 1);             // PID low bits
        bytes[3] = 0x10;                         // Scrambling=0, Adaptation=payload only, CC=0

        // Fill payload with pattern
        for (NSUInteger j = 4; j < 188; j++) {
            bytes[j] = (uint8_t)(j & 0xFF);
        }

        // Last 16 bytes are RS parity (fill with 0xAA pattern)
        for (NSUInteger j = 188; j < 204; j++) {
            bytes[j] = 0xAA;
        }

        [chunk appendData:packet];
    }

    NSArray<TSPacket*> *packets = [TSPacket packetsFromChunkedTsData:chunk packetSize:TS_PACKET_SIZE_204];
    XCTAssertEqual(packets.count, numberOfPackets);

    for (NSUInteger i = 0; i < packets.count; i++) {
        TSPacket *packet = packets[i];
        XCTAssertEqual(packet.header.syncByte, TS_PACKET_HEADER_SYNC_BYTE);
        XCTAssertEqual(packet.header.pid, (uint16_t)(i + 1));
        // Verify RS parity was stripped - payload should be 184 bytes (188 - 4 header)
        XCTAssertEqual(packet.payload.length, (NSUInteger)184);
    }
}

- (void)test_packetsFromChunkedTsData_204Format_payloadIntegrity {
    // Test that the payload content is correct (RS bytes not mixed in)
    NSMutableData *chunk = [NSMutableData dataWithLength:TS_PACKET_SIZE_204];
    uint8_t *bytes = chunk.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x00;
    bytes[2] = 0x42;  // PID = 0x42
    bytes[3] = 0x10;  // Payload only

    // Fill payload with sequential bytes 0x00-0xB7 (184 bytes from offset 4-187)
    for (NSUInteger j = 4; j < 188; j++) {
        bytes[j] = (uint8_t)(j - 4);
    }

    // RS parity bytes (should NOT appear in payload)
    for (NSUInteger j = 188; j < 204; j++) {
        bytes[j] = 0xFF;
    }

    NSArray<TSPacket*> *packets = [TSPacket packetsFromChunkedTsData:chunk packetSize:TS_PACKET_SIZE_204];
    XCTAssertEqual(packets.count, (NSUInteger)1);

    TSPacket *packet = packets[0];
    XCTAssertNotNil(packet.payload);
    XCTAssertEqual(packet.payload.length, (NSUInteger)184);

    // Verify payload content - should be sequential bytes, no RS bytes
    const uint8_t *payloadBytes = packet.payload.bytes;
    for (NSUInteger j = 0; j < 184; j++) {
        XCTAssertEqual(payloadBytes[j], (uint8_t)j,
                       @"Payload byte at offset %lu should be %u but was %u",
                       (unsigned long)j, (uint8_t)j, payloadBytes[j]);
    }
}

- (void)test_packetsFromChunkedTsData_multiplePacketsWithDifferentPids {
    // Test parsing multiple 204-byte packets with different PIDs
    NSMutableData *chunk = [NSMutableData data];
    uint16_t pids[] = {0x100, 0x200, 0x1FFF};  // Video, audio, null packet

    for (NSUInteger i = 0; i < 3; i++) {
        NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_204];
        uint8_t *bytes = packet.mutableBytes;
        bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
        bytes[1] = (uint8_t)((pids[i] >> 8) & 0x1F);  // PID high 5 bits
        bytes[2] = (uint8_t)(pids[i] & 0xFF);          // PID low 8 bits
        bytes[3] = 0x10;
        [chunk appendData:packet];
    }

    NSArray<TSPacket*> *packets = [TSPacket packetsFromChunkedTsData:chunk packetSize:TS_PACKET_SIZE_204];
    XCTAssertEqual(packets.count, (NSUInteger)3);

    XCTAssertEqual(packets[0].header.pid, (uint16_t)0x100);
    XCTAssertEqual(packets[1].header.pid, (uint16_t)0x200);
    XCTAssertEqual(packets[2].header.pid, (uint16_t)0x1FFF);
}

@end
