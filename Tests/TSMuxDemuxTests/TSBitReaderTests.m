//
//  TSBitReaderTests.m
//  TSMuxDemuxTests
//
//  Tests for TSBitReader bit/byte-stream parsing utility.
//

#import <XCTest/XCTest.h>
@import TSMuxDemux;

@interface TSBitReaderTests : XCTestCase
@end

@implementation TSBitReaderTests

#pragma mark - Initialization Tests

- (void)test_makeFromNSData {
    uint8_t bytes[] = {0x01, 0x02, 0x03, 0x04};
    NSData *data = [NSData dataWithBytes:bytes length:4];

    TSBitReader reader = TSBitReaderMake(data);

    XCTAssertEqual(reader.length, (NSUInteger)4);
    XCTAssertEqual(reader.byteOffset, (NSUInteger)0);
    XCTAssertEqual(reader.bitOffset, (uint8_t)0);
    XCTAssertFalse(reader.error);
    XCTAssertEqual(reader.bytes[0], (uint8_t)0x01);
}

- (void)test_makeFromBytes {
    uint8_t bytes[] = {0xAA, 0xBB, 0xCC};

    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 3);

    XCTAssertEqual(reader.length, (NSUInteger)3);
    XCTAssertEqual(reader.byteOffset, (NSUInteger)0);
    XCTAssertEqual(reader.bitOffset, (uint8_t)0);
    XCTAssertFalse(reader.error);
}

#pragma mark - Bit-Level Read Tests

- (void)test_readBits_singleBit {
    // 0b10101010 = 0xAA
    uint8_t bytes[] = {0xAA};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 1);

    XCTAssertEqual(TSBitReaderReadBits(&reader, 1), (uint32_t)1);  // bit 7
    XCTAssertEqual(TSBitReaderReadBits(&reader, 1), (uint32_t)0);  // bit 6
    XCTAssertEqual(TSBitReaderReadBits(&reader, 1), (uint32_t)1);  // bit 5
    XCTAssertEqual(TSBitReaderReadBits(&reader, 1), (uint32_t)0);  // bit 4
    XCTAssertFalse(reader.error);
}

- (void)test_readBits_fullByte {
    uint8_t bytes[] = {0xAB};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 1);

    XCTAssertEqual(TSBitReaderReadBits(&reader, 8), (uint32_t)0xAB);
    XCTAssertFalse(reader.error);
    XCTAssertEqual(reader.byteOffset, reader.length);
}

- (void)test_readBits_crossByteBoundary {
    // Read 12 bits starting at bit 4 of first byte
    // 0xAB = 10101011, 0xCD = 11001101
    // Skip 4 bits (1010), read 12 bits: 1011 11001101 = 0xBCD
    uint8_t bytes[] = {0xAB, 0xCD};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 2);

    TSBitReaderSkipBits(&reader, 4);
    uint32_t value = TSBitReaderReadBits(&reader, 12);

    XCTAssertEqual(value, (uint32_t)0xBCD);
    XCTAssertFalse(reader.error);
}

- (void)test_readBits_13bitPID {
    // TS packet bytes 2-3: 0x5F 0xFF
    // bits: 0101 1111 1111 1111
    // First 3 bits are flags (010), next 13 bits are PID
    // PID = 1 1111 1111 1111 = 0x1FFF (max PID value)
    uint8_t bytes[] = {0x5F, 0xFF};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 2);

    TSBitReaderSkipBits(&reader, 3);  // Skip flags
    uint32_t pid = TSBitReaderReadBits(&reader, 13);

    XCTAssertEqual(pid, (uint32_t)0x1FFF);
    XCTAssertFalse(reader.error);
}

- (void)test_readBits_32bits {
    uint8_t bytes[] = {0x12, 0x34, 0x56, 0x78};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 4);

    uint32_t value = TSBitReaderReadBits(&reader, 32);

    XCTAssertEqual(value, (uint32_t)0x12345678);
    XCTAssertFalse(reader.error);
}

- (void)test_readBits_exceedsBounds {
    uint8_t bytes[] = {0xAB};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 1);

    TSBitReaderReadBits(&reader, 4);
    uint32_t value = TSBitReaderReadBits(&reader, 8);  // Only 4 bits left

    XCTAssertEqual(value, (uint32_t)0);
    XCTAssertTrue(reader.error);
}

- (void)test_readBits_zeroBits_setsError {
    uint8_t bytes[] = {0xAB};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 1);

    TSBitReaderReadBits(&reader, 0);

    XCTAssertTrue(reader.error);
}

- (void)test_readBits_moreThan32_setsError {
    uint8_t bytes[] = {0x00, 0x00, 0x00, 0x00, 0x00};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 5);

    TSBitReaderReadBits(&reader, 33);

    XCTAssertTrue(reader.error);
}

- (void)test_readBits_afterError_returnsZero {
    uint8_t bytes[] = {0xAB};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 1);

    TSBitReaderReadBits(&reader, 16);  // Sets error
    XCTAssertTrue(reader.error);

    uint32_t value = TSBitReaderReadBits(&reader, 4);  // Should return 0

    XCTAssertEqual(value, (uint32_t)0);
}

#pragma mark - Bit-Level Skip Tests

- (void)test_skipBits_withinByte {
    uint8_t bytes[] = {0xAB, 0xCD};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 2);

    TSBitReaderSkipBits(&reader, 4);

    XCTAssertEqual(reader.byteOffset, (NSUInteger)0);
    XCTAssertEqual(reader.bitOffset, (uint8_t)4);
    XCTAssertFalse(reader.error);
}

- (void)test_skipBits_crossByteBoundary {
    uint8_t bytes[] = {0xAB, 0xCD, 0xEF};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 3);

    TSBitReaderSkipBits(&reader, 12);

    XCTAssertEqual(reader.byteOffset, (NSUInteger)1);
    XCTAssertEqual(reader.bitOffset, (uint8_t)4);
    XCTAssertFalse(reader.error);
}

- (void)test_skipBits_exceedsBounds {
    uint8_t bytes[] = {0xAB};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 1);

    TSBitReaderSkipBits(&reader, 16);

    XCTAssertTrue(reader.error);
}

#pragma mark - Byte-Level Read Tests

- (void)test_readUInt8_success {
    uint8_t bytes[] = {0x42, 0xFF};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 2);

    XCTAssertEqual(TSBitReaderReadUInt8(&reader), (uint8_t)0x42);
    XCTAssertEqual(TSBitReaderReadUInt8(&reader), (uint8_t)0xFF);
    XCTAssertFalse(reader.error);
}

- (void)test_readUInt8_atBounds {
    uint8_t bytes[] = {0xAA};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 1);

    XCTAssertEqual(TSBitReaderReadUInt8(&reader), (uint8_t)0xAA);
    TSBitReaderReadUInt8(&reader);  // Should set error

    XCTAssertTrue(reader.error);
}

- (void)test_readUInt8_notAligned_setsError {
    uint8_t bytes[] = {0xAB, 0xCD};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 2);

    TSBitReaderReadBits(&reader, 4);  // Now misaligned
    TSBitReaderReadUInt8(&reader);

    XCTAssertTrue(reader.error);
}

- (void)test_readUInt16BE_success {
    uint8_t bytes[] = {0x12, 0x34};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 2);

    XCTAssertEqual(TSBitReaderReadUInt16BE(&reader), (uint16_t)0x1234);
    XCTAssertFalse(reader.error);
}

- (void)test_readUInt16BE_insufficientBytes {
    uint8_t bytes[] = {0x12};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 1);

    TSBitReaderReadUInt16BE(&reader);

    XCTAssertTrue(reader.error);
}

- (void)test_readUInt32BE_success {
    uint8_t bytes[] = {0x12, 0x34, 0x56, 0x78};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 4);

    XCTAssertEqual(TSBitReaderReadUInt32BE(&reader), (uint32_t)0x12345678);
    XCTAssertFalse(reader.error);
}

- (void)test_readUInt32BE_maxValue {
    uint8_t bytes[] = {0xFF, 0xFF, 0xFF, 0xFF};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 4);

    XCTAssertEqual(TSBitReaderReadUInt32BE(&reader), (uint32_t)0xFFFFFFFF);
    XCTAssertFalse(reader.error);
}

- (void)test_readData_success {
    uint8_t bytes[] = {0xAA, 0xBB, 0xCC, 0xDD};
    NSData *data = [NSData dataWithBytes:bytes length:4];
    TSBitReader reader = TSBitReaderMake(data);

    NSData *result = TSBitReaderReadData(&reader, 2);

    XCTAssertNotNil(result);
    XCTAssertEqual(result.length, (NSUInteger)2);
    const uint8_t *resultBytes = result.bytes;
    XCTAssertEqual(resultBytes[0], (uint8_t)0xAA);
    XCTAssertEqual(resultBytes[1], (uint8_t)0xBB);
    XCTAssertFalse(reader.error);
}

- (void)test_readData_insufficientBytes {
    uint8_t bytes[] = {0x01};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 1);

    NSData *result = TSBitReaderReadData(&reader, 5);

    XCTAssertNil(result);
    XCTAssertTrue(reader.error);
}

#pragma mark - Skip Bytes Tests

- (void)test_skip_success {
    uint8_t bytes[] = {0x01, 0x02, 0x03, 0x04, 0x05};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 5);

    TSBitReaderSkip(&reader, 3);

    XCTAssertEqual(reader.byteOffset, (NSUInteger)3);
    XCTAssertFalse(reader.error);
    XCTAssertEqual(TSBitReaderReadUInt8(&reader), (uint8_t)0x04);
}

- (void)test_skip_exceedsBounds {
    uint8_t bytes[] = {0x01, 0x02};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 2);

    TSBitReaderSkip(&reader, 5);

    XCTAssertTrue(reader.error);
}

- (void)test_skip_notAligned_setsError {
    uint8_t bytes[] = {0x01, 0x02, 0x03};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 3);

    TSBitReaderReadBits(&reader, 4);
    TSBitReaderSkip(&reader, 1);

    XCTAssertTrue(reader.error);
}

#pragma mark - State Query Tests

- (void)test_remainingBits {
    uint8_t bytes[] = {0x01, 0x02, 0x03};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 3);

    XCTAssertEqual(TSBitReaderRemainingBits(&reader), (NSUInteger)24);

    TSBitReaderReadBits(&reader, 5);
    XCTAssertEqual(TSBitReaderRemainingBits(&reader), (NSUInteger)19);

    TSBitReaderReadBits(&reader, 11);
    XCTAssertEqual(TSBitReaderRemainingBits(&reader), (NSUInteger)8);
}

- (void)test_remainingBytes {
    uint8_t bytes[] = {0x01, 0x02, 0x03, 0x04, 0x05};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 5);

    XCTAssertEqual(TSBitReaderRemainingBytes(&reader), (NSUInteger)5);

    TSBitReaderReadUInt8(&reader);
    XCTAssertEqual(TSBitReaderRemainingBytes(&reader), (NSUInteger)4);
}

- (void)test_remainingBytes_whenNotAligned {
    uint8_t bytes[] = {0x01, 0x02, 0x03};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 3);

    TSBitReaderReadBits(&reader, 4);  // Now at byte 0, bit 4

    // Should return 2 (bytes 1 and 2, excluding partial byte 0)
    XCTAssertEqual(TSBitReaderRemainingBytes(&reader), (NSUInteger)2);
}

- (void)test_hasBits {
    uint8_t bytes[] = {0x01, 0x02};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 2);

    XCTAssertTrue(TSBitReaderHasBits(&reader, 16));
    XCTAssertTrue(TSBitReaderHasBits(&reader, 1));
    XCTAssertFalse(TSBitReaderHasBits(&reader, 17));
}

#pragma mark - SubReader Tests

- (void)test_subReader_success {
    uint8_t bytes[] = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 6);

    TSBitReaderSkip(&reader, 1);

    TSBitReader sub = TSBitReaderSubReader(&reader, 3);

    XCTAssertEqual(sub.length, (NSUInteger)3);
    XCTAssertEqual(sub.byteOffset, (NSUInteger)0);
    XCTAssertEqual(sub.bytes[0], (uint8_t)0x01);
    XCTAssertEqual(sub.bytes[2], (uint8_t)0x03);
    XCTAssertFalse(sub.error);

    XCTAssertEqual(reader.byteOffset, (NSUInteger)4);
    XCTAssertFalse(reader.error);
}

- (void)test_subReader_exceedsBounds {
    uint8_t bytes[] = {0x01, 0x02};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 2);

    TSBitReader sub = TSBitReaderSubReader(&reader, 10);

    XCTAssertEqual(sub.length, (NSUInteger)0);
    XCTAssertTrue(sub.error);
    XCTAssertTrue(reader.error);
}

- (void)test_subReader_notAligned_setsError {
    uint8_t bytes[] = {0x01, 0x02, 0x03};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 3);

    TSBitReaderReadBits(&reader, 4);
    TSBitReader sub = TSBitReaderSubReader(&reader, 1);

    XCTAssertTrue(sub.error);
    XCTAssertTrue(reader.error);
}

#pragma mark - Mixed Bit/Byte Operations

- (void)test_mixedOperations_tsPacketHeader {
    // Simulated TS packet header: 0x47 0x5F 0xFF 0x10
    // sync=0x47, TEI=0, PUSI=1, priority=0, PID=0x1FFF, scrambling=0, adapt=01, CC=0
    uint8_t bytes[] = {0x47, 0x5F, 0xFF, 0x10};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 4);

    uint8_t sync = TSBitReaderReadUInt8(&reader);
    XCTAssertEqual(sync, (uint8_t)0x47);

    uint32_t tei = TSBitReaderReadBits(&reader, 1);
    uint32_t pusi = TSBitReaderReadBits(&reader, 1);
    uint32_t priority = TSBitReaderReadBits(&reader, 1);
    uint32_t pid = TSBitReaderReadBits(&reader, 13);

    XCTAssertEqual(tei, (uint32_t)0);
    XCTAssertEqual(pusi, (uint32_t)1);
    XCTAssertEqual(priority, (uint32_t)0);
    XCTAssertEqual(pid, (uint32_t)0x1FFF);

    uint32_t scrambling = TSBitReaderReadBits(&reader, 2);
    uint32_t adaptation = TSBitReaderReadBits(&reader, 2);
    uint32_t cc = TSBitReaderReadBits(&reader, 4);

    XCTAssertEqual(scrambling, (uint32_t)0);
    XCTAssertEqual(adaptation, (uint32_t)1);
    XCTAssertEqual(cc, (uint32_t)0);

    XCTAssertFalse(reader.error);
    XCTAssertEqual(reader.byteOffset, reader.length);
}

- (void)test_mixedOperations_readBitsThenBytes {
    uint8_t bytes[] = {0xF0, 0x12, 0x34};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 3);

    uint32_t nibble = TSBitReaderReadBits(&reader, 4);  // 0xF
    XCTAssertEqual(nibble, (uint32_t)0xF);

    TSBitReaderSkipBits(&reader, 4);  // Skip remaining 4 bits to align

    uint16_t value = TSBitReaderReadUInt16BE(&reader);
    XCTAssertEqual(value, (uint16_t)0x1234);
    XCTAssertFalse(reader.error);
}

#pragma mark - Error State Persistence

- (void)test_errorState_persistsAcrossOperations {
    uint8_t bytes[] = {0xAB};
    TSBitReader reader = TSBitReaderMakeWithBytes(bytes, 1);

    TSBitReaderReadBits(&reader, 16);  // Sets error
    XCTAssertTrue(reader.error);

    // All subsequent operations should fail gracefully
    XCTAssertEqual(TSBitReaderReadBits(&reader, 1), (uint32_t)0);
    XCTAssertEqual(TSBitReaderReadUInt8(&reader), (uint8_t)0);
    XCTAssertEqual(TSBitReaderReadUInt16BE(&reader), (uint16_t)0);
    XCTAssertNil(TSBitReaderReadData(&reader, 1));

    XCTAssertTrue(reader.error);
}

@end
