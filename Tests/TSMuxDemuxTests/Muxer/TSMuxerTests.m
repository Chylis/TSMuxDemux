//
//  TSMuxerTests.m
//  TSMuxDemuxTests
//
//  Tests for TS packet muxing (packetization).
//

#import <XCTest/XCTest.h>
@import TSMuxDemux;

static const NSUInteger kTSAdaptationHeaderSize = 2;  // 1 byte length + 1 byte flags
static const NSUInteger kMaxPayloadSize = 188 - 4 - 2;  // TS_PACKET_SIZE - HEADER_SIZE - ADAPTATION_HEADER

@interface TSMuxerTests : XCTestCase
@end

@implementation TSMuxerTests

#pragma mark - Payload Packetization Tests

- (void)test_packetizePayload_sizing {
    NSArray<NSNumber *> *payloadSizes = @[@0, @1, @182, @183, @187, @188, @189, @364, @5000, @15000];

    for (NSNumber *sizeNum in payloadSizes) {
        NSUInteger payloadSize = sizeNum.unsignedIntegerValue;
        NSMutableArray<NSData *> *packets = [NSMutableArray array];

        TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:256
                                                                 streamType:kRawStreamTypeH264
                                                                descriptors:nil];

        // Create a properly allocated buffer
        NSMutableData *payload = [NSMutableData dataWithLength:payloadSize];
        if (payloadSize > 0) {
            memset(payload.mutableBytes, 0xEE, payloadSize);
        }

        [TSPacket packetizePayload:payload
                             track:track
    
                           pcrBase:kNoPcr
                            pcrExt:0
                 discontinuityFlag:NO
                  randomAccessFlag:NO
                    onTsPacketData:^(NSData * _Nonnull tsPacketData, uint16_t pid, uint8_t cc) {
            [packets addObject:tsPacketData];
        }];

        // Verify basic invariants
        if (payloadSize == 0) {
            XCTAssertEqual(packets.count, (NSUInteger)0, @"Empty payload should produce no packets");
        } else {
            XCTAssertGreaterThan(packets.count, (NSUInteger)0,
                                 @"Non-empty payload should produce at least one packet");
        }

        // Every packet should be exactly 188 bytes
        for (NSData *packet in packets) {
            XCTAssertEqual(packet.length, (NSUInteger)TS_PACKET_SIZE_188,
                           @"Each TS packet should be %u bytes", TS_PACKET_SIZE_188);
        }

        // Verify total payload extracted equals input (approximately - adaptation may add overhead)
        NSUInteger totalPayloadBytes = 0;
        for (NSData *packetData in packets) {
            NSArray<TSPacket *> *parsed = [TSPacket packetsFromChunkedTsData:packetData
                                                                 packetSize:TS_PACKET_SIZE_188];
            if (parsed.count > 0 && parsed[0].payload) {
                totalPayloadBytes += parsed[0].payload.length;
            }
        }
        XCTAssertGreaterThanOrEqual(totalPayloadBytes, payloadSize,
                                    @"Total payload capacity should fit input payload");
    }
}

- (void)test_packetizePayload_contents {
    const uint8_t payloadByte = 0xAB;
    const uint16_t pid = 7777;

    // Create payload that spans multiple packets
    const NSUInteger totalPayloadBytes = 1000;

    NSMutableData *payload = [NSMutableData dataWithLength:totalPayloadBytes];
    memset(payload.mutableBytes, payloadByte, totalPayloadBytes);

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:pid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    NSMutableArray<NSData *> *packets = [NSMutableArray array];
    [TSPacket packetizePayload:payload
                         track:track

                       pcrBase:kNoPcr
                        pcrExt:0
             discontinuityFlag:NO
              randomAccessFlag:NO
                onTsPacketData:^(NSData * _Nonnull tsPacketData, uint16_t pid, uint8_t cc) {
        [packets addObject:tsPacketData];
    }];

    XCTAssertGreaterThan(packets.count, (NSUInteger)1);

    for (NSUInteger i = 0; i < packets.count; i++) {
        NSData *packetData = packets[i];

        // Every packet must be exactly 188 bytes
        XCTAssertEqual(packetData.length, (NSUInteger)TS_PACKET_SIZE_188);

        // Parse and verify header
        NSArray<TSPacket *> *parsed = [TSPacket packetsFromChunkedTsData:packetData
                                                             packetSize:TS_PACKET_SIZE_188];
        XCTAssertEqual(parsed.count, (NSUInteger)1);
        TSPacket *packet = parsed[0];

        // Verify header fields
        XCTAssertEqual(packet.header.syncByte, TS_PACKET_HEADER_SYNC_BYTE);
        XCTAssertEqual(packet.header.pid, pid);
        XCTAssertEqual(packet.header.payloadUnitStartIndicator, i == 0);  // PUSI only on first
        XCTAssertEqual(packet.header.continuityCounter, (uint8_t)(i % 16));
        XCTAssertFalse(packet.header.transportErrorIndicator);
        XCTAssertFalse(packet.header.isScrambled);

        // Verify payload exists and contains our data
        XCTAssertNotNil(packet.payload);
        if (packet.payload) {
            const uint8_t *payloadBytes = packet.payload.bytes;
            for (NSUInteger j = 0; j < packet.payload.length; j++) {
                XCTAssertEqual(payloadBytes[j], payloadByte,
                               @"Packet %lu payload byte %lu should be 0x%02X",
                               (unsigned long)i, (unsigned long)j, payloadByte);
            }
        }
    }
}

- (void)test_packetizePayload_withPCR {
    const uint64_t pcrBase = 12345678;
    const uint16_t pcrExt = 123;
    const uint16_t pid = 100;

    // Create a small payload that fits in one packet
    NSData *payload = [NSData dataWithBytes:(uint8_t[]){0x01, 0x02, 0x03, 0x04} length:4];

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:pid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    NSMutableArray<NSData *> *packets = [NSMutableArray array];
    [TSPacket packetizePayload:payload
                         track:track

                       pcrBase:pcrBase
                        pcrExt:pcrExt
             discontinuityFlag:NO
              randomAccessFlag:NO
                onTsPacketData:^(NSData * _Nonnull tsPacketData, uint16_t pid, uint8_t cc) {
        [packets addObject:tsPacketData];
    }];

    XCTAssertEqual(packets.count, (NSUInteger)1);

    NSData *packetData = packets[0];
    const uint8_t *bytes = packetData.bytes;

    // Verify adaptation field exists and has PCR flag set
    uint8_t adaptationLen = bytes[4];
    XCTAssertGreaterThan(adaptationLen, (uint8_t)0);

    uint8_t adaptationFlags = bytes[5];
    BOOL pcrFlag = (adaptationFlags & 0x10) != 0;
    XCTAssertTrue(pcrFlag, @"PCR flag should be set when pcrBase > 0");
}

- (void)test_packetizePayload_pcrOnlyOnFirstPacket {
    const uint64_t pcrBase = 12345678;
    const uint16_t pcrExt = 42;
    const uint16_t pid = 100;

    // Create payload large enough to span 2+ packets (184 bytes per packet without AF)
    const NSUInteger payloadSize = 400;
    NSMutableData *payload = [NSMutableData dataWithLength:payloadSize];
    memset(payload.mutableBytes, 0xEE, payloadSize);

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:pid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    NSMutableArray<NSData *> *packets = [NSMutableArray array];
    [TSPacket packetizePayload:payload
                         track:track

                       pcrBase:pcrBase
                        pcrExt:pcrExt
             discontinuityFlag:NO
              randomAccessFlag:NO
                onTsPacketData:^(NSData * _Nonnull tsPacketData, uint16_t pid, uint8_t cc) {
        [packets addObject:tsPacketData];
    }];

    XCTAssertGreaterThan(packets.count, (NSUInteger)1, @"Payload should span multiple packets");

    for (NSUInteger i = 0; i < packets.count; i++) {
        NSArray<TSPacket *> *parsed = [TSPacket packetsFromChunkedTsData:packets[i]
                                                             packetSize:TS_PACKET_SIZE_188];
        TSPacket *packet = parsed[0];

        if (i == 0) {
            XCTAssertTrue(packet.adaptationField.pcrFlag, @"First packet should have PCR flag set");
        } else {
            BOOL hasPcrFlag = packet.adaptationField && packet.adaptationField.pcrFlag;
            XCTAssertFalse(hasPcrFlag, @"Packet %lu should NOT have PCR flag set", (unsigned long)i);
        }
    }
}

- (void)test_packetizePayload_pusiOnlyOnFirstPacket {
    const uint16_t pid = 200;

    // Create payload that spans 3+ packets
    const NSUInteger payloadSize = 600;
    NSMutableData *payload = [NSMutableData dataWithLength:payloadSize];
    memset(payload.mutableBytes, 0xDD, payloadSize);

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:pid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    NSMutableArray<NSData *> *packets = [NSMutableArray array];
    [TSPacket packetizePayload:payload
                         track:track
                       pcrBase:kNoPcr
                        pcrExt:0
             discontinuityFlag:NO
              randomAccessFlag:NO
                onTsPacketData:^(NSData * _Nonnull tsPacketData, uint16_t pid, uint8_t cc) {
        [packets addObject:tsPacketData];
    }];

    XCTAssertGreaterThanOrEqual(packets.count, (NSUInteger)3);

    for (NSUInteger i = 0; i < packets.count; i++) {
        NSArray<TSPacket *> *parsed = [TSPacket packetsFromChunkedTsData:packets[i]
                                                             packetSize:TS_PACKET_SIZE_188];
        TSPacket *packet = parsed[0];

        if (i == 0) {
            XCTAssertTrue(packet.header.payloadUnitStartIndicator,
                          @"First packet should have PUSI set");
        } else {
            XCTAssertFalse(packet.header.payloadUnitStartIndicator,
                           @"Packet %lu should NOT have PUSI set", (unsigned long)i);
        }
    }
}

- (void)test_packetizePayload_continuityCounterWraps {
    const uint16_t pid = 300;

    // Create payload that spans 20+ packets to test CC wrapping at 16
    const NSUInteger targetPackets = 20;
    const NSUInteger payloadSize = targetPackets * kMaxPayloadSize;
    NSMutableData *payload = [NSMutableData dataWithLength:payloadSize];
    memset(payload.mutableBytes, 0xCC, payloadSize);

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:pid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    NSMutableArray<NSData *> *packets = [NSMutableArray array];
    [TSPacket packetizePayload:payload
                         track:track

                       pcrBase:kNoPcr
                        pcrExt:0
             discontinuityFlag:NO
              randomAccessFlag:NO
                onTsPacketData:^(NSData * _Nonnull tsPacketData, uint16_t pid, uint8_t cc) {
        [packets addObject:tsPacketData];
    }];

    // Should have enough packets to test CC wrapping
    XCTAssertGreaterThanOrEqual(packets.count, (NSUInteger)16);

    for (NSUInteger i = 0; i < packets.count; i++) {
        NSArray<TSPacket *> *parsed = [TSPacket packetsFromChunkedTsData:packets[i]
                                                             packetSize:TS_PACKET_SIZE_188];
        TSPacket *packet = parsed[0];

        uint8_t expectedCC = (uint8_t)(i % 16);
        XCTAssertEqual(packet.header.continuityCounter, expectedCC,
                       @"Packet %lu should have CC=%u", (unsigned long)i, expectedCC);
    }
}

#pragma mark - Header Serialization Tests

- (void)test_packetHeader_serialization {
    TSAdaptationMode modes[] = {
        TSAdaptationModePayloadOnly,
        TSAdaptationModeAdaptationOnly,
        TSAdaptationModeAdaptationAndPayload
    };

    for (int modeIdx = 0; modeIdx < 3; modeIdx++) {
        TSAdaptationMode mode = modes[modeIdx];

        for (int boolVal = 0; boolVal <= 1; boolVal++) {
            BOOL flag = (boolVal == 1);
            uint16_t testPid = 777;
            uint8_t testCC = 7;

            TSPacketHeader *header = [[TSPacketHeader alloc] initWithSyncByte:TS_PACKET_HEADER_SYNC_BYTE
                                                                          tei:flag
                                                                         pusi:flag
                                                            transportPriority:flag
                                                                          pid:testPid
                                                                  isScrambled:flag
                                                               adaptationMode:mode
                                                            continuityCounter:testCC];

            NSData *data = [header getBytes];
            XCTAssertEqual(data.length, (NSUInteger)4);

            const uint8_t *bytes = data.bytes;

            // Byte 0: sync byte
            XCTAssertEqual(bytes[0], TS_PACKET_HEADER_SYNC_BYTE);

            // Byte 1: TEI, PUSI, Priority, PID high 5 bits
            BOOL parsedTei = (bytes[1] & 0x80) != 0;
            BOOL parsedPusi = (bytes[1] & 0x40) != 0;
            BOOL parsedPrio = (bytes[1] & 0x20) != 0;
            uint16_t pidHigh = (bytes[1] & 0x1F) << 8;

            XCTAssertEqual(parsedTei, flag);
            XCTAssertEqual(parsedPusi, flag);
            XCTAssertEqual(parsedPrio, flag);

            // Byte 2: PID low 8 bits
            uint16_t parsedPid = pidHigh | bytes[2];
            XCTAssertEqual(parsedPid, testPid);

            // Byte 3: Scrambling, Adaptation, CC
            BOOL parsedScrambled = (bytes[3] & 0xC0) != 0;
            TSAdaptationMode parsedMode = (bytes[3] & 0x30) >> 4;
            uint8_t parsedCC = bytes[3] & 0x0F;

            XCTAssertEqual(parsedScrambled, flag);
            XCTAssertEqual(parsedMode, mode);
            XCTAssertEqual(parsedCC, testCC);
        }
    }
}

- (void)test_packetHeader_pidRange {
    // Test PID boundary values (13-bit value: 0 to 8191)
    uint16_t testPids[] = {0, 1, 0x100, 0x1FFF, 8191};

    for (int i = 0; i < 5; i++) {
        uint16_t pid = testPids[i];

        TSPacketHeader *header = [[TSPacketHeader alloc] initWithSyncByte:TS_PACKET_HEADER_SYNC_BYTE
                                                                      tei:NO
                                                                     pusi:NO
                                                        transportPriority:NO
                                                                      pid:pid
                                                              isScrambled:NO
                                                           adaptationMode:TSAdaptationModePayloadOnly
                                                        continuityCounter:0];

        NSData *data = [header getBytes];
        const uint8_t *bytes = data.bytes;

        uint16_t parsedPid = ((bytes[1] & 0x1F) << 8) | bytes[2];
        XCTAssertEqual(parsedPid, pid, @"PID %u should serialize correctly", pid);
    }
}

#pragma mark - Adaptation Field Tests

- (void)test_adaptationField_serialization {
    // Test with valid stuffing sizes (adaptationFieldLength max is 183)
    // adaptationLen = stuffingCount + 1 (for flags byte)
    uint8_t stuffingSizes[] = {1, 50, 100, 182};

    for (int i = 0; i < 4; i++) {
        uint8_t stuffingCount = stuffingSizes[i];
        uint8_t adaptationLen = stuffingCount + 1;  // +1 for flags byte

        TSAdaptationField *field = [[TSAdaptationField alloc] initWithAdaptationFieldLength:adaptationLen
                                                                          discontinuityFlag:NO
                                                                           randomAccessFlag:NO
                                                                             esPriorityFlag:NO
                                                                                    pcrFlag:NO
                                                                                   oPcrFlag:NO
                                                                          splicingPointFlag:NO
                                                                   transportPrivateDataFlag:NO
                                                               adaptationFieldExtensionFlag:NO
                                                                                    pcrBase:kNoPcr
                                                                                     pcrExt:0
                                                                       numberOfStuffedBytes:stuffingCount];

        NSData *data = [field getBytes];
        const uint8_t *bytes = data.bytes;

        // First byte is the adaptation_field_length
        XCTAssertEqual(bytes[0], adaptationLen);

        // Verify total size: 1 (length byte) + adaptationLen
        XCTAssertEqual(data.length, (NSUInteger)(1 + adaptationLen));

        // Verify stuffing bytes are 0xFF (starts at offset 2, after length and flags)
        for (NSUInteger j = 2; j < data.length; j++) {
            XCTAssertEqual(bytes[j], (uint8_t)0xFF,
                           @"Stuffing byte at offset %lu should be 0xFF", (unsigned long)j);
        }
    }
}

- (void)test_adaptationField_maxLength {
    // When adaptation_field_control = '10' (adaptation only), length must be 183
    const uint8_t maxAdaptationLen = 183;

    TSAdaptationField *field = [[TSAdaptationField alloc] initWithAdaptationFieldLength:maxAdaptationLen
                                                                      discontinuityFlag:NO
                                                                       randomAccessFlag:NO
                                                                         esPriorityFlag:NO
                                                                                pcrFlag:NO
                                                                               oPcrFlag:NO
                                                                      splicingPointFlag:NO
                                                               transportPrivateDataFlag:NO
                                                           adaptationFieldExtensionFlag:NO
                                                                                pcrBase:kNoPcr
                                                                                 pcrExt:0
                                                                   numberOfStuffedBytes:182];  // 183 - 1 flags byte

    NSData *data = [field getBytes];
    XCTAssertEqual(data.length, (NSUInteger)184);  // 1 + 183
    XCTAssertEqual(((uint8_t *)data.bytes)[0], maxAdaptationLen);
}

#pragma mark - Algorithm Invariant Tests

- (void)test_adaptationField_getBytes_sizeMatchesLength {
    // Verify: data.length == adaptationFieldLength + 1 for all valid lengths
    uint8_t testLengths[] = {0, 1, 7, 50, 100, 182, 183};

    for (int i = 0; i < sizeof(testLengths)/sizeof(testLengths[0]); i++) {
        uint8_t adapLen = testLengths[i];
        // numberOfStuffedBytes = adapLen - 1 (for flags byte), but 0 if adapLen is 0
        NSUInteger stuffing = (adapLen > 0) ? (adapLen - 1) : 0;

        TSAdaptationField *field = [[TSAdaptationField alloc] initWithAdaptationFieldLength:adapLen
                                                                          discontinuityFlag:NO
                                                                           randomAccessFlag:NO
                                                                             esPriorityFlag:NO
                                                                                    pcrFlag:NO
                                                                                   oPcrFlag:NO
                                                                          splicingPointFlag:NO
                                                                   transportPrivateDataFlag:NO
                                                               adaptationFieldExtensionFlag:NO
                                                                                    pcrBase:kNoPcr
                                                                                     pcrExt:0
                                                                       numberOfStuffedBytes:stuffing];

        NSData *data = [field getBytes];
        XCTAssertEqual(data.length, (NSUInteger)(adapLen + 1),
                       @"getBytes length should be adaptationFieldLength + 1 for adapLen=%u", adapLen);
    }
}

- (void)test_initWithPcrBase_validLengthWithPayload {
    // When hasPayload (remainingPayloadSize > 0), adaptationFieldLength should be 0-182
    NSUInteger payloadSizes[] = {1, 50, 100, 182, 183, 184};

    for (int i = 0; i < sizeof(payloadSizes)/sizeof(payloadSizes[0]); i++) {
        NSUInteger payloadSize = payloadSizes[i];

        // Without PCR
        TSAdaptationField *field = [TSAdaptationField initWithPcrBase:0
                                                               pcrExt:0
                                                    discontinuityFlag:NO
                                                     randomAccessFlag:NO
                                                 remainingPayloadSize:payloadSize];
        XCTAssertLessThanOrEqual(field.adaptationFieldLength, (uint8_t)182,
                                 @"With payload=%lu, adapLen should be <= 182", (unsigned long)payloadSize);

        // With PCR
        TSAdaptationField *fieldWithPcr = [TSAdaptationField initWithPcrBase:12345
                                                                      pcrExt:0
                                                           discontinuityFlag:NO
                                                            randomAccessFlag:NO
                                                        remainingPayloadSize:payloadSize];
        XCTAssertLessThanOrEqual(fieldWithPcr.adaptationFieldLength, (uint8_t)182,
                                 @"With PCR and payload=%lu, adapLen should be <= 182", (unsigned long)payloadSize);
    }
}

- (void)test_initWithPcrBase_validLengthNoPayload {
    // When no payload (remainingPayloadSize = 0), adaptationFieldLength should be 183
    TSAdaptationField *field = [TSAdaptationField initWithPcrBase:0
                                                           pcrExt:0
                                                discontinuityFlag:NO
                                                 randomAccessFlag:NO
                                             remainingPayloadSize:0];
    XCTAssertEqual(field.adaptationFieldLength, (uint8_t)183,
                   @"With no payload, adapLen should be 183");

    // With PCR
    TSAdaptationField *fieldWithPcr = [TSAdaptationField initWithPcrBase:12345
                                                                  pcrExt:0
                                                       discontinuityFlag:NO
                                                        randomAccessFlag:NO
                                                    remainingPayloadSize:0];
    XCTAssertEqual(fieldWithPcr.adaptationFieldLength, (uint8_t)183,
                   @"With PCR and no payload, adapLen should be 183");
}

- (void)test_packetizePayload_allPacketsAre188Bytes {
    // Verify all generated packets are exactly 188 bytes
    NSUInteger payloadSizes[] = {1, 100, 184, 185, 368, 1000, 5000};

    for (int i = 0; i < sizeof(payloadSizes)/sizeof(payloadSizes[0]); i++) {
        NSUInteger payloadSize = payloadSizes[i];
        NSMutableData *payload = [NSMutableData dataWithLength:payloadSize];
        memset(payload.mutableBytes, 0xAB, payloadSize);

        TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:256
                                                                 streamType:kRawStreamTypeH264
                                                                descriptors:nil];

        NSMutableArray<NSData *> *packets = [NSMutableArray array];
        [TSPacket packetizePayload:payload
                             track:track
    
                           pcrBase:kNoPcr
                            pcrExt:0
                 discontinuityFlag:NO
                  randomAccessFlag:NO
                    onTsPacketData:^(NSData * _Nonnull tsPacketData, uint16_t pid, uint8_t cc) {
            [packets addObject:tsPacketData];
        }];

        for (NSUInteger j = 0; j < packets.count; j++) {
            XCTAssertEqual(packets[j].length, (NSUInteger)TS_PACKET_SIZE_188,
                           @"Payload size %lu, packet %lu should be 188 bytes",
                           (unsigned long)payloadSize, (unsigned long)j);
        }
    }
}

#pragma mark - TSTimeUtil Tests

- (void)test_secondsToNanos_fractionalSeconds {
    uint64_t result = [TSTimeUtil secondsToNanos:1.5];
    XCTAssertEqual(result, (uint64_t)1500000000ULL,
                   @"1.5 seconds should be 1500000000 nanoseconds, got %llu", result);
}

- (void)test_secondsToNanos_wholeSeconds {
    uint64_t result = [TSTimeUtil secondsToNanos:2.0];
    XCTAssertEqual(result, (uint64_t)2000000000ULL,
                   @"2.0 seconds should be 2000000000 nanoseconds, got %llu", result);
}

#pragma mark - PTS 33-bit Wrapping (ISO 13818-1 §2.4.3.7)

- (void)test_pes_ptsOnly_wrapsAt33Bits {
    // PTS exceeding 2^33 (8589934592) simulates >26.5 hours of continuous media.
    // The PTS field is 33 bits; without masking, bit 33 leaks into the pts_dts_indicator
    // prefix byte, corrupting it from 0010 (PTS-only) to 0011 (PTS+DTS).
    const uint64_t ptsIn90kHz = 8595000000ULL;
    const uint64_t expectedWrapped = ptsIn90kHz & 0x1FFFFFFFFULL;

    TSAccessUnit *au = [[TSAccessUnit alloc] initWithPid:256
                                                     pts:CMTimeMake(ptsIn90kHz, 90000)
                                                     dts:kCMTimeInvalid
                                         isDiscontinuous:NO
                                      isRandomAccessPoint:NO
                                              streamType:kRawStreamTypeADTSAAC
                                              descriptors:nil
                                          compressedData:[NSData dataWithBytes:(uint8_t[]){0x01} length:1]];

    NSData *pes = [au toTsPacketPayloadWithEpoch:kCMTimeInvalid];
    const uint8_t *bytes = pes.bytes;

    // PES header: start_code(4) + pes_length(2) + flags1(1) + flags2(1) + header_data_length(1) = 9
    // PTS field starts at byte 9

    // flags2 (byte 7): pts_dts_indicator in bits 7-6 should be 10 (PTS only)
    uint8_t flags2 = bytes[7];
    XCTAssertEqual((flags2 >> 6) & 0x03, (uint8_t)0x02, @"flags2 should indicate PTS-only");

    // PTS byte 0 (byte 9): bits 7-4 are the prefix and must match the indicator.
    // PTS-only prefix is 0010. Bug: bit 33 of PTS leaks into bit 4, giving 0011.
    uint8_t ptsPrefix = (bytes[9] >> 4) & 0x0F;
    XCTAssertEqual(ptsPrefix, (uint8_t)0x02,
                   @"PTS prefix should be 0010 (PTS-only), got 0x%X. "
                   @"Bit 33 must not leak into the indicator prefix.", ptsPrefix);

    // Decode and verify the 33-bit wrapped PTS value
    uint64_t decoded = ((uint64_t)(bytes[9]  & 0x0E) << 29)
                     | ((uint64_t) bytes[10]         << 22)
                     | ((uint64_t)(bytes[11] & 0xFE) << 14)
                     | ((uint64_t) bytes[12]         << 7)
                     | ((uint64_t) bytes[13]         >> 1);
    XCTAssertEqual(decoded, expectedWrapped,
                   @"PTS should wrap to 33-bit value %llu, got %llu", expectedWrapped, decoded);
}

- (void)test_pes_ptsDts_wrapsAt33Bits {
    // Verify both PTS and DTS wrap correctly when exceeding 33 bits.
    const uint64_t ptsIn90kHz = 8595000000ULL;
    const uint64_t dtsIn90kHz = 8594000000ULL;
    const uint64_t expectedPts = ptsIn90kHz & 0x1FFFFFFFFULL;
    const uint64_t expectedDts = dtsIn90kHz & 0x1FFFFFFFFULL;

    TSAccessUnit *au = [[TSAccessUnit alloc] initWithPid:256
                                                     pts:CMTimeMake(ptsIn90kHz, 90000)
                                                     dts:CMTimeMake(dtsIn90kHz, 90000)
                                         isDiscontinuous:NO
                                      isRandomAccessPoint:NO
                                              streamType:kRawStreamTypeH264
                                              descriptors:nil
                                          compressedData:[NSData dataWithBytes:(uint8_t[]){0x01} length:1]];

    NSData *pes = [au toTsPacketPayloadWithEpoch:kCMTimeInvalid];
    const uint8_t *bytes = pes.bytes;

    // PTS at offset 9, DTS at offset 14
    // PTS prefix for PTS+DTS mode: 0011
    uint8_t ptsPrefix = (bytes[9] >> 4) & 0x0F;
    XCTAssertEqual(ptsPrefix, (uint8_t)0x03,
                   @"PTS prefix should be 0011 (PTS+DTS), got 0x%X", ptsPrefix);

    // DTS prefix: 0001
    uint8_t dtsPrefix = (bytes[14] >> 4) & 0x0F;
    XCTAssertEqual(dtsPrefix, (uint8_t)0x01,
                   @"DTS prefix should be 0001, got 0x%X", dtsPrefix);

    // Decode PTS
    uint64_t decodedPts = ((uint64_t)(bytes[9]  & 0x0E) << 29)
                        | ((uint64_t) bytes[10]         << 22)
                        | ((uint64_t)(bytes[11] & 0xFE) << 14)
                        | ((uint64_t) bytes[12]         << 7)
                        | ((uint64_t) bytes[13]         >> 1);
    XCTAssertEqual(decodedPts, expectedPts,
                   @"PTS should wrap to %llu, got %llu", expectedPts, decodedPts);

    // Decode DTS
    uint64_t decodedDts = ((uint64_t)(bytes[14] & 0x0E) << 29)
                        | ((uint64_t) bytes[15]         << 22)
                        | ((uint64_t)(bytes[16] & 0xFE) << 14)
                        | ((uint64_t) bytes[17]         << 7)
                        | ((uint64_t) bytes[18]         >> 1);
    XCTAssertEqual(decodedDts, expectedDts,
                   @"DTS should wrap to %llu, got %llu", expectedDts, decodedDts);
}

#pragma mark - PTS/DTS Epoch Offset

- (void)test_pes_ptsDts_offsetByEpoch {
    // Simulates an encoder whose timestamps start at 50 000 seconds (e.g. host uptime).
    // Without epoch offset, PTS/DTS in the PES would be ~50 000 s while PCR starts at 0.
    // With epoch offset, PTS/DTS become relative: (absolute - epoch).
    const double epochSeconds = 50000.0;
    const double ptsSeconds   = 50000.5;   // 500 ms after epoch
    const double dtsSeconds   = 50000.466; // ~466 ms after epoch

    const CMTime epoch = CMTimeMakeWithSeconds(epochSeconds, 90000);

    TSAccessUnit *au = [[TSAccessUnit alloc] initWithPid:256
                                                     pts:CMTimeMakeWithSeconds(ptsSeconds, 90000)
                                                     dts:CMTimeMakeWithSeconds(dtsSeconds, 90000)
                                         isDiscontinuous:NO
                                      isRandomAccessPoint:YES
                                              streamType:kRawStreamTypeH264
                                              descriptors:nil
                                          compressedData:[NSData dataWithBytes:(uint8_t[]){0x01} length:1]];

    NSData *pes = [au toTsPacketPayloadWithEpoch:epoch];
    const uint8_t *bytes = pes.bytes;

    // Expected 90 kHz ticks relative to epoch
    const uint64_t expectedPts = (uint64_t)((ptsSeconds - epochSeconds) * 90000); // 45000
    const uint64_t expectedDts = (uint64_t)((dtsSeconds - epochSeconds) * 90000); // ~41940

    // Decode PTS from PES (offset 9)
    uint64_t decodedPts = ((uint64_t)(bytes[9]  & 0x0E) << 29)
                        | ((uint64_t) bytes[10]         << 22)
                        | ((uint64_t)(bytes[11] & 0xFE) << 14)
                        | ((uint64_t) bytes[12]         << 7)
                        | ((uint64_t) bytes[13]         >> 1);
    XCTAssertEqual(decodedPts, expectedPts,
                   @"PTS should be offset by epoch to %llu, got %llu", expectedPts, decodedPts);

    // Decode DTS from PES (offset 14)
    uint64_t decodedDts = ((uint64_t)(bytes[14] & 0x0E) << 29)
                        | ((uint64_t) bytes[15]         << 22)
                        | ((uint64_t)(bytes[16] & 0xFE) << 14)
                        | ((uint64_t) bytes[17]         << 7)
                        | ((uint64_t) bytes[18]         >> 1);
    XCTAssertEqual(decodedDts, expectedDts,
                   @"DTS should be offset by epoch to %llu, got %llu", expectedDts, decodedDts);
}

- (void)test_pes_ptsOnly_offsetByEpoch {
    // Audio AU: PTS only, no DTS. Epoch offset should apply to PTS.
    const double epochSeconds = 50000.0;
    const double ptsSeconds   = 50001.0; // 1 second after epoch

    const CMTime epoch = CMTimeMakeWithSeconds(epochSeconds, 90000);

    TSAccessUnit *au = [[TSAccessUnit alloc] initWithPid:210
                                                     pts:CMTimeMakeWithSeconds(ptsSeconds, 90000)
                                                     dts:kCMTimeInvalid
                                         isDiscontinuous:NO
                                      isRandomAccessPoint:NO
                                              streamType:kRawStreamTypeADTSAAC
                                              descriptors:nil
                                          compressedData:[NSData dataWithBytes:(uint8_t[]){0x01} length:1]];

    NSData *pes = [au toTsPacketPayloadWithEpoch:epoch];
    const uint8_t *bytes = pes.bytes;

    // flags2: PTS-only indicator (10)
    XCTAssertEqual((bytes[7] >> 6) & 0x03, (uint8_t)0x02, @"Should indicate PTS-only");

    const uint64_t expectedPts = (uint64_t)((ptsSeconds - epochSeconds) * 90000); // 90000

    uint64_t decodedPts = ((uint64_t)(bytes[9]  & 0x0E) << 29)
                        | ((uint64_t) bytes[10]         << 22)
                        | ((uint64_t)(bytes[11] & 0xFE) << 14)
                        | ((uint64_t) bytes[12]         << 7)
                        | ((uint64_t) bytes[13]         >> 1);
    XCTAssertEqual(decodedPts, expectedPts,
                   @"PTS should be offset by epoch to %llu, got %llu", expectedPts, decodedPts);
}

- (void)test_pes_invalidEpoch_usesAbsoluteTimestamps {
    // When epoch is kCMTimeInvalid, timestamps should pass through unchanged.
    const uint64_t absolutePts = 4500000000ULL; // ~50000 seconds in 90 kHz

    TSAccessUnit *au = [[TSAccessUnit alloc] initWithPid:256
                                                     pts:CMTimeMake(absolutePts, 90000)
                                                     dts:kCMTimeInvalid
                                         isDiscontinuous:NO
                                      isRandomAccessPoint:NO
                                              streamType:kRawStreamTypeH264
                                              descriptors:nil
                                          compressedData:[NSData dataWithBytes:(uint8_t[]){0x01} length:1]];

    NSData *pes = [au toTsPacketPayloadWithEpoch:kCMTimeInvalid];
    const uint8_t *bytes = pes.bytes;

    const uint64_t expectedPts = absolutePts & 0x1FFFFFFFFULL;

    uint64_t decodedPts = ((uint64_t)(bytes[9]  & 0x0E) << 29)
                        | ((uint64_t) bytes[10]         << 22)
                        | ((uint64_t)(bytes[11] & 0xFE) << 14)
                        | ((uint64_t) bytes[12]         << 7)
                        | ((uint64_t) bytes[13]         >> 1);
    XCTAssertEqual(decodedPts, expectedPts,
                   @"With invalid epoch, PTS should be absolute (masked to 33 bits): expected %llu, got %llu",
                   expectedPts, decodedPts);
}

#pragma mark - PMT Deterministic ES Ordering (ISO 13818-1 §2.4.4.8)

- (void)test_pmt_elementaryStreams_sortedByPid {
    // NSSet has no contractual enumeration order. Without sorting, the ES entries
    // in the serialized PMT may appear in arbitrary order, causing CRC changes
    // without a version_number increment — confusing decoders.
    TSElementaryStream *es1 = [[TSElementaryStream alloc] initWithPid:5000 streamType:kRawStreamTypeH264 descriptors:nil];
    TSElementaryStream *es2 = [[TSElementaryStream alloc] initWithPid:100  streamType:kRawStreamTypeADTSAAC descriptors:nil];
    TSElementaryStream *es3 = [[TSElementaryStream alloc] initWithPid:200  streamType:kRawStreamTypeH264 descriptors:nil];

    NSSet *streams = [NSSet setWithArray:@[es1, es2, es3]];
    TSProgramMapTable *pmt = [[TSProgramMapTable alloc] initWithProgramNumber:1
                                                                versionNumber:0
                                                                       pcrPid:100
                                                            elementaryStreams:streams];
    NSData *payload = [pmt toTsPacketPayload];
    const uint8_t *bytes = payload.bytes;

    // PMT payload layout:
    // pointer(1) + table_id(1) + section_header(2) + common_section(5) + pcr_pid(2) + prog_info_len(2)
    // = 13 bytes before ES entries.  Each ES entry = 5 bytes.  CRC = 4 bytes at end.
    const NSUInteger esOffset = 13;
    const NSUInteger crcLen = 4;
    const NSUInteger esEntrySize = 5;
    const NSUInteger esDataLen = payload.length - esOffset - crcLen;
    const NSUInteger numStreams = esDataLen / esEntrySize;

    XCTAssertEqual(numStreams, (NSUInteger)3, @"Should have 3 ES entries");

    NSMutableArray<NSNumber*> *pids = [NSMutableArray array];
    for (NSUInteger i = 0; i < numStreams; i++) {
        NSUInteger off = esOffset + i * esEntrySize;
        uint16_t pid = ((bytes[off + 1] & 0x1F) << 8) | bytes[off + 2];
        [pids addObject:@(pid)];
    }

    // ES entries must be in ascending PID order for deterministic serialization
    for (NSUInteger i = 1; i < pids.count; i++) {
        XCTAssertLessThan(pids[i-1].unsignedShortValue, pids[i].unsignedShortValue,
                          @"ES entries must be sorted by PID for deterministic serialization: "
                          @"PID %@ appeared before PID %@", pids[i-1], pids[i]);
    }
}

- (void)test_pmt_serialization_deterministic {
    // Two independently-constructed NSSet instances with the same elements
    // must produce identical PMT serializations.
    TSElementaryStream *es_a1 = [[TSElementaryStream alloc] initWithPid:5000 streamType:kRawStreamTypeH264 descriptors:nil];
    TSElementaryStream *es_a2 = [[TSElementaryStream alloc] initWithPid:100  streamType:kRawStreamTypeADTSAAC descriptors:nil];
    TSElementaryStream *es_a3 = [[TSElementaryStream alloc] initWithPid:200  streamType:kRawStreamTypeH264 descriptors:nil];

    TSElementaryStream *es_b1 = [[TSElementaryStream alloc] initWithPid:5000 streamType:kRawStreamTypeH264 descriptors:nil];
    TSElementaryStream *es_b2 = [[TSElementaryStream alloc] initWithPid:100  streamType:kRawStreamTypeADTSAAC descriptors:nil];
    TSElementaryStream *es_b3 = [[TSElementaryStream alloc] initWithPid:200  streamType:kRawStreamTypeH264 descriptors:nil];

    // Build sets in different insertion orders
    NSSet *setA = [NSSet setWithArray:@[es_a1, es_a2, es_a3]];
    NSSet *setB = [NSSet setWithArray:@[es_b3, es_b1, es_b2]];

    TSProgramMapTable *pmtA = [[TSProgramMapTable alloc] initWithProgramNumber:1 versionNumber:0 pcrPid:100 elementaryStreams:setA];
    TSProgramMapTable *pmtB = [[TSProgramMapTable alloc] initWithProgramNumber:1 versionNumber:0 pcrPid:100 elementaryStreams:setB];

    NSData *payloadA = [pmtA toTsPacketPayload];
    NSData *payloadB = [pmtB toTsPacketPayload];

    XCTAssertEqualObjects(payloadA, payloadB,
                          @"PMT serialization must be deterministic regardless of NSSet construction order");
}

@end
