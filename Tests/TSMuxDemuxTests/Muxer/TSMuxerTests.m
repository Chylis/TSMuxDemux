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
                         forcePusi:NO
                           pcrBase:0
                            pcrExt:0
                  randomAccessFlag:NO
                    onTsPacketData:^(NSData * _Nonnull tsPacketData) {
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
                     forcePusi:NO
                       pcrBase:0
                        pcrExt:0
              randomAccessFlag:NO
                onTsPacketData:^(NSData * _Nonnull tsPacketData) {
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
                     forcePusi:NO
                       pcrBase:pcrBase
                        pcrExt:pcrExt
              randomAccessFlag:NO
                onTsPacketData:^(NSData * _Nonnull tsPacketData) {
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

- (void)test_packetizePayload_forcePusi {
    const uint16_t pid = 200;

    // Create payload that spans multiple packets
    const NSUInteger payloadSize = 400;
    NSMutableData *payload = [NSMutableData dataWithLength:payloadSize];
    memset(payload.mutableBytes, 0xDD, payloadSize);

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:pid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    NSMutableArray<NSData *> *packets = [NSMutableArray array];
    [TSPacket packetizePayload:payload
                         track:track
                     forcePusi:YES
                       pcrBase:0
                        pcrExt:0
              randomAccessFlag:NO
                onTsPacketData:^(NSData * _Nonnull tsPacketData) {
        [packets addObject:tsPacketData];
    }];

    XCTAssertGreaterThan(packets.count, (NSUInteger)1);

    // With forcePusi=YES, ALL packets should have PUSI set
    for (NSUInteger i = 0; i < packets.count; i++) {
        NSArray<TSPacket *> *parsed = [TSPacket packetsFromChunkedTsData:packets[i]
                                                             packetSize:TS_PACKET_SIZE_188];
        TSPacket *packet = parsed[0];
        XCTAssertTrue(packet.header.payloadUnitStartIndicator,
                      @"Packet %lu should have PUSI set when forcePusi=YES", (unsigned long)i);
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
                     forcePusi:NO
                       pcrBase:0
                        pcrExt:0
              randomAccessFlag:NO
                onTsPacketData:^(NSData * _Nonnull tsPacketData) {
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
                                                                                    pcrBase:0
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
                                                                                pcrBase:0
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
                                                                                    pcrBase:0
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
                                                     randomAccessFlag:NO
                                                 remainingPayloadSize:payloadSize];
        XCTAssertLessThanOrEqual(field.adaptationFieldLength, (uint8_t)182,
                                 @"With payload=%lu, adapLen should be <= 182", (unsigned long)payloadSize);

        // With PCR
        TSAdaptationField *fieldWithPcr = [TSAdaptationField initWithPcrBase:12345
                                                                      pcrExt:0
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
                                                 randomAccessFlag:NO
                                             remainingPayloadSize:0];
    XCTAssertEqual(field.adaptationFieldLength, (uint8_t)183,
                   @"With no payload, adapLen should be 183");

    // With PCR
    TSAdaptationField *fieldWithPcr = [TSAdaptationField initWithPcrBase:12345
                                                                  pcrExt:0
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
                         forcePusi:NO
                           pcrBase:0
                            pcrExt:0
                  randomAccessFlag:NO
                    onTsPacketData:^(NSData * _Nonnull tsPacketData) {
            [packets addObject:tsPacketData];
        }];

        for (NSUInteger j = 0; j < packets.count; j++) {
            XCTAssertEqual(packets[j].length, (NSUInteger)TS_PACKET_SIZE_188,
                           @"Payload size %lu, packet %lu should be 188 bytes",
                           (unsigned long)payloadSize, (unsigned long)j);
        }
    }
}

@end
