//
//  TSPsiTableBuilderTests.m
//  TSMuxDemuxTests
//
//  Tests for TSPsiTableBuilder multi-section table handling.
//

#import <XCTest/XCTest.h>
#import "../TSTestUtils.h"
@import TSMuxDemux;

@interface TSPsiTableBuilderTests : XCTestCase <TSPsiTableBuilderDelegate>
@property (nonatomic, strong) NSMutableArray<TSProgramSpecificInformationTable *> *receivedTables;
@end

@implementation TSPsiTableBuilderTests

- (void)setUp {
    [super setUp];
    self.receivedTables = [NSMutableArray array];
}

#pragma mark - TSPsiTableBuilderDelegate

- (void)tableBuilder:(TSPsiTableBuilder *)builder didBuildTable:(TSProgramSpecificInformationTable *)table {
    [self.receivedTables addObject:table];
}

#pragma mark - Tests

- (void)test_singleSectionTable_deliveredImmediately {
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    // Create single-section table (sectionNumber=0, lastSectionNumber=0)
    NSData *payload = [@"SINGLE" dataUsingEncoding:NSUTF8StringEncoding];
    TSPacket *packet = [TSTestUtils createPsiPacketWithPid:0x00
                                            tableId:0x00
                                   tableIdExtension:0x0001
                                      versionNumber:1
                                      sectionNumber:0
                                  lastSectionNumber:0
                                            payload:payload
                                 continuityCounter:0];

    [builder addTsPacket:packet];

    XCTAssertEqual(self.receivedTables.count, 1, @"Single-section table should be delivered immediately");
    XCTAssertEqual(self.receivedTables[0].sectionNumber, 0);
    XCTAssertEqual(self.receivedTables[0].lastSectionNumber, 0);
}

- (void)test_multiSectionTable_notDeliveredUntilComplete {
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    // Create section 0 of 2 (lastSectionNumber=1 means 2 sections total)
    NSData *payload0 = [@"PART0" dataUsingEncoding:NSUTF8StringEncoding];
    TSPacket *packet0 = [TSTestUtils createPsiPacketWithPid:0x00
                                             tableId:0x00
                                    tableIdExtension:0x0001
                                       versionNumber:1
                                       sectionNumber:0
                                   lastSectionNumber:1
                                             payload:payload0
                                  continuityCounter:0];

    [builder addTsPacket:packet0];

    XCTAssertEqual(self.receivedTables.count, 0, @"Multi-section table should not be delivered until all sections received");
}

- (void)test_multiSectionTable_deliveredWhenComplete {
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    // Create section 0 of 2
    NSData *payload0 = [@"PART0" dataUsingEncoding:NSUTF8StringEncoding];
    TSPacket *packet0 = [TSTestUtils createPsiPacketWithPid:0x00
                                             tableId:0x00
                                    tableIdExtension:0x0001
                                       versionNumber:1
                                       sectionNumber:0
                                   lastSectionNumber:1
                                             payload:payload0
                                  continuityCounter:0];

    // Create section 1 of 2
    NSData *payload1 = [@"PART1" dataUsingEncoding:NSUTF8StringEncoding];
    TSPacket *packet1 = [TSTestUtils createPsiPacketWithPid:0x00
                                             tableId:0x00
                                    tableIdExtension:0x0001
                                       versionNumber:1
                                       sectionNumber:1
                                   lastSectionNumber:1
                                             payload:payload1
                                  continuityCounter:1];

    [builder addTsPacket:packet0];
    XCTAssertEqual(self.receivedTables.count, 0, @"Should not deliver after first section");

    [builder addTsPacket:packet1];
    XCTAssertEqual(self.receivedTables.count, 1, @"Should deliver after all sections received");

    // Verify aggregated table has sectionNumber=0, lastSectionNumber=0
    TSProgramSpecificInformationTable *aggregated = self.receivedTables[0];
    XCTAssertEqual(aggregated.sectionNumber, 0);
    XCTAssertEqual(aggregated.lastSectionNumber, 0);
}

- (void)test_multiSectionTable_aggregatesPayload {
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    // Create section 0 of 2
    NSData *payload0 = [@"AAA" dataUsingEncoding:NSUTF8StringEncoding];
    TSPacket *packet0 = [TSTestUtils createPsiPacketWithPid:0x00
                                             tableId:0x00
                                    tableIdExtension:0x0001
                                       versionNumber:1
                                       sectionNumber:0
                                   lastSectionNumber:1
                                             payload:payload0
                                  continuityCounter:0];

    // Create section 1 of 2
    NSData *payload1 = [@"BBB" dataUsingEncoding:NSUTF8StringEncoding];
    TSPacket *packet1 = [TSTestUtils createPsiPacketWithPid:0x00
                                             tableId:0x00
                                    tableIdExtension:0x0001
                                       versionNumber:1
                                       sectionNumber:1
                                   lastSectionNumber:1
                                             payload:payload1
                                  continuityCounter:1];

    [builder addTsPacket:packet0];
    [builder addTsPacket:packet1];

    TSProgramSpecificInformationTable *aggregated = self.receivedTables[0];

    // Aggregated sectionData should contain combined payload
    // Layout: bytes 0-4 = header, bytes 5+ = combined payload
    NSData *sectionData = aggregated.sectionDataExcludingCrc;
    XCTAssertTrue(sectionData.length >= 5 + 6, @"Should have header + combined payload");

    // Extract payload portion (after 5-byte header)
    NSData *combinedPayload = [sectionData subdataWithRange:NSMakeRange(5, sectionData.length - 5)];
    NSString *payloadString = [[NSString alloc] initWithData:combinedPayload encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(payloadString, @"AAABBB", @"Payload should be concatenated in order");
}

- (void)test_multiSectionTable_outOfOrderDelivery {
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    // Create section 1 first (out of order)
    NSData *payload1 = [@"BBB" dataUsingEncoding:NSUTF8StringEncoding];
    TSPacket *packet1 = [TSTestUtils createPsiPacketWithPid:0x00
                                             tableId:0x00
                                    tableIdExtension:0x0001
                                       versionNumber:1
                                       sectionNumber:1
                                   lastSectionNumber:1
                                             payload:payload1
                                  continuityCounter:0];

    // Then section 0
    NSData *payload0 = [@"AAA" dataUsingEncoding:NSUTF8StringEncoding];
    TSPacket *packet0 = [TSTestUtils createPsiPacketWithPid:0x00
                                             tableId:0x00
                                    tableIdExtension:0x0001
                                       versionNumber:1
                                       sectionNumber:0
                                   lastSectionNumber:1
                                             payload:payload0
                                  continuityCounter:1];

    [builder addTsPacket:packet1];
    XCTAssertEqual(self.receivedTables.count, 0);

    [builder addTsPacket:packet0];
    XCTAssertEqual(self.receivedTables.count, 1, @"Should deliver when all sections received regardless of order");

    // Verify payload is still in correct order (section 0 then section 1)
    TSProgramSpecificInformationTable *aggregated = self.receivedTables[0];
    NSData *sectionData = aggregated.sectionDataExcludingCrc;
    NSData *combinedPayload = [sectionData subdataWithRange:NSMakeRange(5, sectionData.length - 5)];
    NSString *payloadString = [[NSString alloc] initWithData:combinedPayload encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(payloadString, @"AAABBB", @"Payload should be in section order, not arrival order");
}

/// Helper to create a raw TS packet for PSI section spanning tests.
/// Returns packet data with section header started but not completed.
- (NSData *)createSpanningPsiPacketWithPid:(uint16_t)pid
                                   tableId:(uint8_t)tableId
                             sectionLength:(uint16_t)sectionLength
                                      pusi:(BOOL)pusi
                         continuityCounter:(uint8_t)cc
                               sectionData:(NSData *)sectionData
{
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    // TS Header
    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = (pusi ? 0x40 : 0x00) | ((pid >> 8) & 0x1F);
    bytes[2] = pid & 0xFF;
    bytes[3] = 0x10 | (cc & 0x0F);

    NSUInteger offset = 4;

    if (pusi) {
        // Pointer field
        bytes[offset++] = 0x00;

        // PSI section header (3 bytes)
        bytes[offset++] = tableId;
        bytes[offset++] = 0xB0 | ((sectionLength >> 8) & 0x0F);
        bytes[offset++] = sectionLength & 0xFF;
    }

    // Copy section data
    NSUInteger copyLen = MIN(sectionData.length, TS_PACKET_SIZE_188 - offset);
    memcpy(bytes + offset, sectionData.bytes, copyLen);
    offset += copyLen;

    // Fill remaining with stuffing
    while (offset < TS_PACKET_SIZE_188) {
        bytes[offset++] = 0xFF;
    }

    return packet;
}

- (void)test_sectionSpanningTwoPackets_deliversCompleteSection {
    // Section spans 2 packets: first packet fills completely, second packet completes section
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    // TS payload = 184 bytes. PUSI packet overhead: 1 (pointer) + 3 (section header) = 4 bytes
    // Available for section data in first packet: 180 bytes
    // section_length = 190 ensures section spans into second packet (190 > 180)

    uint16_t sectionLength = 190;

    // Build section data that will span packets
    NSMutableData *fullSectionData = [NSMutableData dataWithLength:sectionLength];
    uint8_t *sd = fullSectionData.mutableBytes;
    // PSI header: tableIdExt(2) + version(1) + sectionNum(1) + lastSectionNum(1) = 5 bytes
    sd[0] = 0x00; sd[1] = 0x01;  // tableIdExtension = 1
    sd[2] = 0xC1;                 // version=0, current_next=1
    sd[3] = 0x00;                 // sectionNumber = 0
    sd[4] = 0x00;                 // lastSectionNumber = 0
    // Fill payload with pattern (190 - 5 - 4 = 181 bytes payload)
    for (int i = 5; i < sectionLength - 4; i++) {
        sd[i] = (uint8_t)(i & 0xFF);
    }
    // CRC at end
    sd[sectionLength - 4] = 0x12;
    sd[sectionLength - 3] = 0x34;
    sd[sectionLength - 2] = 0x56;
    sd[sectionLength - 1] = 0x78;

    // First packet: 180 bytes of section data (all that fits)
    NSData *packet1Data = [self createSpanningPsiPacketWithPid:0x00
                                                       tableId:0x00
                                                 sectionLength:sectionLength
                                                          pusi:YES
                                             continuityCounter:0
                                                   sectionData:[fullSectionData subdataWithRange:NSMakeRange(0, 180)]];
    NSArray<TSPacket *> *packets1 = [TSPacket packetsFromChunkedTsData:packet1Data packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets1[0]];

    XCTAssertEqual(self.receivedTables.count, 0, @"Incomplete section should not be delivered");

    // Second packet: remaining 10 bytes (190 - 180)
    NSMutableData *packet2 = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes2 = packet2.mutableBytes;
    bytes2[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes2[1] = 0x00;  // PUSI=0
    bytes2[2] = 0x00;
    bytes2[3] = 0x11;  // CC=1

    memcpy(bytes2 + 4, (uint8_t *)fullSectionData.bytes + 180, 10);
    memset(bytes2 + 4 + 10, 0xFF, TS_PACKET_SIZE_188 - 4 - 10);

    NSArray<TSPacket *> *packets2 = [TSPacket packetsFromChunkedTsData:packet2 packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets2[0]];

    XCTAssertEqual(self.receivedTables.count, 1, @"Complete section should be delivered");
    XCTAssertEqual(self.receivedTables[0].tableId, 0x00);
    XCTAssertEqual(self.receivedTables[0].sectionLength, sectionLength);
}

- (void)test_sectionSpanningPackets_firstPacketExactlyFilled {
    // Edge case: first packet payload is exactly filled (0 bytes remaining)
    // This triggered an infinite loop bug when the while condition included || sectionInProgress
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    // TS payload = 184 bytes. With PUSI: 1 (pointer) + 3 (section header) = 4 bytes overhead
    // Available for section data in first packet: 180 bytes
    // We need section_length > 180 to span packets, and exactly 180 bytes of section data in first packet

    uint16_t sectionLength = 200;  // Total section data needed (will span to second packet)

    // Build section data for first packet (exactly 180 bytes to fill the packet)
    NSMutableData *sectionDataPart1 = [NSMutableData dataWithLength:180];
    uint8_t *part1 = sectionDataPart1.mutableBytes;
    // Header
    part1[0] = 0x00; part1[1] = 0x01;  // tableIdExtension
    part1[2] = 0xC1;  // version + current_next
    part1[3] = 0x00;  // sectionNumber
    part1[4] = 0x00;  // lastSectionNumber
    // Fill rest with pattern
    for (int i = 5; i < 180; i++) {
        part1[i] = (uint8_t)(i & 0xFF);
    }

    NSData *packet1Data = [self createSpanningPsiPacketWithPid:0x00
                                                       tableId:0x00
                                                 sectionLength:sectionLength
                                                          pusi:YES
                                             continuityCounter:0
                                                   sectionData:sectionDataPart1];

    NSArray<TSPacket *> *packets1 = [TSPacket packetsFromChunkedTsData:packet1Data packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets1[0]];

    XCTAssertEqual(self.receivedTables.count, 0, @"Incomplete section should not be delivered");

    // Second packet: remaining 20 bytes (200 - 180) including CRC
    NSMutableData *packet2 = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes2 = packet2.mutableBytes;
    bytes2[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes2[1] = 0x00;  // PUSI=0
    bytes2[2] = 0x00;
    bytes2[3] = 0x11;  // CC=1

    // 16 bytes more data + 4 bytes CRC = 20 bytes
    for (int i = 0; i < 16; i++) {
        bytes2[4 + i] = 0xBB;
    }
    bytes2[20] = 0x12; bytes2[21] = 0x34; bytes2[22] = 0x56; bytes2[23] = 0x78;  // CRC
    memset(bytes2 + 24, 0xFF, TS_PACKET_SIZE_188 - 24);

    NSArray<TSPacket *> *packets2 = [TSPacket packetsFromChunkedTsData:packet2 packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets2[0]];

    XCTAssertEqual(self.receivedTables.count, 1, @"Complete section should be delivered after continuation");
    XCTAssertEqual(self.receivedTables[0].sectionLength, sectionLength);
}

- (void)test_sectionSpanningThreePackets_deliversCompleteSection {
    // Section spans 3 packets
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    // section_length large enough to need 3 packets
    // Packet 1: 180 bytes, Packet 2: 184 bytes, Packet 3: remaining
    uint16_t sectionLength = 400;  // Will need ~3 packets

    // First packet
    NSMutableData *sectionDataPart1 = [NSMutableData dataWithLength:180];
    memset(sectionDataPart1.mutableBytes, 0xAA, 180);
    uint8_t *p1 = sectionDataPart1.mutableBytes;
    p1[0] = 0x00; p1[1] = 0x01; p1[2] = 0xC1; p1[3] = 0x00; p1[4] = 0x00;

    NSData *packet1Data = [self createSpanningPsiPacketWithPid:0x00
                                                       tableId:0x00
                                                 sectionLength:sectionLength
                                                          pusi:YES
                                             continuityCounter:0
                                                   sectionData:sectionDataPart1];
    NSArray<TSPacket *> *packets1 = [TSPacket packetsFromChunkedTsData:packet1Data packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets1[0]];
    XCTAssertEqual(self.receivedTables.count, 0);

    // Second packet (PUSI=0): 184 bytes of continuation
    NSMutableData *packet2 = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes2 = packet2.mutableBytes;
    bytes2[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes2[1] = 0x00; bytes2[2] = 0x00; bytes2[3] = 0x11;
    memset(bytes2 + 4, 0xBB, 184);

    NSArray<TSPacket *> *packets2 = [TSPacket packetsFromChunkedTsData:packet2 packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets2[0]];
    XCTAssertEqual(self.receivedTables.count, 0);

    // Third packet: remaining 36 bytes (400 - 180 - 184 = 36, including 4-byte CRC)
    NSMutableData *packet3 = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes3 = packet3.mutableBytes;
    bytes3[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes3[1] = 0x00; bytes3[2] = 0x00; bytes3[3] = 0x12;  // CC=2
    memset(bytes3 + 4, 0xCC, 32);
    bytes3[36] = 0x12; bytes3[37] = 0x34; bytes3[38] = 0x56; bytes3[39] = 0x78;
    memset(bytes3 + 40, 0xFF, TS_PACKET_SIZE_188 - 40);

    NSArray<TSPacket *> *packets3 = [TSPacket packetsFromChunkedTsData:packet3 packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets3[0]];

    XCTAssertEqual(self.receivedTables.count, 1, @"Section spanning 3 packets should be delivered");
    XCTAssertEqual(self.receivedTables[0].sectionLength, sectionLength);
}

- (void)test_sectionSpanningPackets_minimalBytesInSecondPacket {
    // Edge case: second packet contains minimal continuation (5 bytes: 1 data + 4 CRC)
    // Note: Can't have < 4 bytes remaining because CRC is 4 bytes
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    // Available in first packet after PUSI overhead: 180 bytes
    // section_length = 185 → first packet gets 180, second packet gets 5 (1 data + 4 CRC)
    uint16_t sectionLength = 185;

    NSMutableData *fullSectionData = [NSMutableData dataWithLength:sectionLength];
    uint8_t *sd = fullSectionData.mutableBytes;
    sd[0] = 0x00; sd[1] = 0x01; sd[2] = 0xC1; sd[3] = 0x00; sd[4] = 0x00;
    for (int i = 5; i < sectionLength - 4; i++) {
        sd[i] = (uint8_t)(i & 0xFF);
    }
    sd[sectionLength - 4] = 0x12;
    sd[sectionLength - 3] = 0x34;
    sd[sectionLength - 2] = 0x56;
    sd[sectionLength - 1] = 0x78;

    // First packet: 180 bytes
    NSData *packet1Data = [self createSpanningPsiPacketWithPid:0x00
                                                       tableId:0x00
                                                 sectionLength:sectionLength
                                                          pusi:YES
                                             continuityCounter:0
                                                   sectionData:[fullSectionData subdataWithRange:NSMakeRange(0, 180)]];
    NSArray<TSPacket *> *packets1 = [TSPacket packetsFromChunkedTsData:packet1Data packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets1[0]];

    XCTAssertEqual(self.receivedTables.count, 0, @"Section should not be delivered yet");

    // Second packet: 5 bytes (1 data + 4 CRC)
    NSMutableData *packet2 = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes2 = packet2.mutableBytes;
    bytes2[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes2[1] = 0x00; bytes2[2] = 0x00; bytes2[3] = 0x11;
    memcpy(bytes2 + 4, sd + 180, 5);  // Last 5 bytes of section
    memset(bytes2 + 9, 0xFF, TS_PACKET_SIZE_188 - 9);

    NSArray<TSPacket *> *packets2 = [TSPacket packetsFromChunkedTsData:packet2 packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets2[0]];

    XCTAssertEqual(self.receivedTables.count, 1, @"Section should be delivered after continuation");
    XCTAssertEqual(self.receivedTables[0].sectionLength, sectionLength);
}

- (void)test_pointerFieldNonZero_previousSectionEndsNewSectionBegins {
    // Pointer field > 0: previous section ends mid-packet, new section starts after
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    // Create a small section that completes in first packet, followed by another section
    // Section 1: small enough to fit with room for section 2 to start
    // Section 2: starts after section 1 in same packet

    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x40;  // PUSI=1, PID=0
    bytes[2] = 0x00;
    bytes[3] = 0x10;  // CC=0

    NSUInteger offset = 4;

    // First, we need a spanning section from a "previous" packet
    // For this test, let's start fresh with PUSI and pointer_field = 0
    // Then test back-to-back sections

    // Actually, pointer_field > 0 means the packet contains the END of a previous section
    // followed by a NEW section. Let's simulate this properly:

    // Scenario: Previous section's last 10 bytes are in this packet, then new section starts

    // pointer_field = 10 (new section starts 10 bytes into payload)
    bytes[offset++] = 10;

    // Bytes 0-9 after pointer: tail of previous section (we don't have context, so builder ignores)
    // But wait - we need sectionInProgress for the builder to use these bytes
    // This test requires setting up a spanning section first

    // Let's set up properly: first packet starts a section, second packet (PUSI=1, pointer>0)
    // contains end of that section plus start of a new section

    // --- First packet: start section 1 (won't complete) ---
    uint16_t section1Length = 190;  // Spans into second packet

    NSMutableData *packet1 = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *p1 = packet1.mutableBytes;
    p1[0] = TS_PACKET_HEADER_SYNC_BYTE;
    p1[1] = 0x40; p1[2] = 0x00; p1[3] = 0x10;  // PUSI=1, PID=0, CC=0

    NSUInteger off1 = 4;
    p1[off1++] = 0x00;  // pointer_field = 0
    p1[off1++] = 0x00;  // table_id
    p1[off1++] = 0xB0 | ((section1Length >> 8) & 0x0F);
    p1[off1++] = section1Length & 0xFF;
    // Section data header
    p1[off1++] = 0x00; p1[off1++] = 0x01;  // tableIdExt
    p1[off1++] = 0xC1;  // version
    p1[off1++] = 0x00; p1[off1++] = 0x00;  // section nums
    // Fill remaining with data (180 bytes total available, used 5 for header)
    for (NSUInteger i = off1; i < TS_PACKET_SIZE_188; i++) {
        p1[i] = 0xAA;
    }

    NSArray<TSPacket *> *pkt1 = [TSPacket packetsFromChunkedTsData:packet1 packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:pkt1[0]];
    XCTAssertEqual(self.receivedTables.count, 0, @"Section 1 incomplete");

    // --- Second packet: PUSI=1, pointer_field > 0 ---
    // Contains: [end of section 1] [start of section 2]
    // Section 1 needs: 190 - 180 = 10 more bytes (including CRC)
    // pointer_field = 10 (section 2 starts at byte 10)

    NSMutableData *packet2 = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *p2 = packet2.mutableBytes;
    p2[0] = TS_PACKET_HEADER_SYNC_BYTE;
    p2[1] = 0x40; p2[2] = 0x00; p2[3] = 0x11;  // PUSI=1, PID=0, CC=1

    NSUInteger off2 = 4;
    p2[off2++] = 10;  // pointer_field: section 2 starts 10 bytes later

    // 10 bytes: end of section 1 (6 data + 4 CRC)
    for (int i = 0; i < 6; i++) p2[off2++] = 0xAA;
    p2[off2++] = 0x12; p2[off2++] = 0x34; p2[off2++] = 0x56; p2[off2++] = 0x78;  // CRC

    // Now section 2 starts (small, fits entirely)
    uint16_t section2Length = 13;  // 5 header + 4 payload + 4 CRC
    p2[off2++] = 0x02;  // table_id (different from section 1)
    p2[off2++] = 0xB0 | ((section2Length >> 8) & 0x0F);
    p2[off2++] = section2Length & 0xFF;
    p2[off2++] = 0x00; p2[off2++] = 0x02;  // tableIdExt = 2
    p2[off2++] = 0xC3;  // version = 1
    p2[off2++] = 0x00; p2[off2++] = 0x00;  // section nums
    p2[off2++] = 0xDD; p2[off2++] = 0xEE; p2[off2++] = 0xFF; p2[off2++] = 0x11;  // payload
    p2[off2++] = 0xAB; p2[off2++] = 0xCD; p2[off2++] = 0xEF; p2[off2++] = 0x00;  // CRC

    memset(p2 + off2, 0xFF, TS_PACKET_SIZE_188 - off2);

    NSArray<TSPacket *> *pkt2 = [TSPacket packetsFromChunkedTsData:packet2 packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:pkt2[0]];

    // Should have received both sections
    XCTAssertEqual(self.receivedTables.count, 2, @"Both sections should be delivered");
    XCTAssertEqual(self.receivedTables[0].tableId, 0x00, @"First section table_id");
    XCTAssertEqual(self.receivedTables[0].sectionLength, section1Length);
    XCTAssertEqual(self.receivedTables[1].tableId, 0x02, @"Second section table_id");
    XCTAssertEqual(self.receivedTables[1].sectionLength, section2Length);
}

- (void)test_backToBackSectionsInSamePacket {
    // Two complete sections in the same packet
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x40;  // PUSI=1, PID=0
    bytes[2] = 0x00;
    bytes[3] = 0x10;  // CC=0

    NSUInteger offset = 4;
    bytes[offset++] = 0x00;  // pointer_field = 0

    // Section 1: small complete section
    uint16_t section1Length = 13;  // 5 header + 4 payload + 4 CRC
    bytes[offset++] = 0x00;  // table_id
    bytes[offset++] = 0xB0 | ((section1Length >> 8) & 0x0F);
    bytes[offset++] = section1Length & 0xFF;
    bytes[offset++] = 0x00; bytes[offset++] = 0x01;  // tableIdExt
    bytes[offset++] = 0xC1;  // version 0
    bytes[offset++] = 0x00; bytes[offset++] = 0x00;  // section nums
    bytes[offset++] = 0x11; bytes[offset++] = 0x22; bytes[offset++] = 0x33; bytes[offset++] = 0x44;  // payload
    bytes[offset++] = 0x12; bytes[offset++] = 0x34; bytes[offset++] = 0x56; bytes[offset++] = 0x78;  // CRC

    // Section 2: another small complete section
    uint16_t section2Length = 13;
    bytes[offset++] = 0x02;  // table_id (different)
    bytes[offset++] = 0xB0 | ((section2Length >> 8) & 0x0F);
    bytes[offset++] = section2Length & 0xFF;
    bytes[offset++] = 0x00; bytes[offset++] = 0x02;  // tableIdExt
    bytes[offset++] = 0xC3;  // version 1
    bytes[offset++] = 0x00; bytes[offset++] = 0x00;  // section nums
    bytes[offset++] = 0xAA; bytes[offset++] = 0xBB; bytes[offset++] = 0xCC; bytes[offset++] = 0xDD;  // payload
    bytes[offset++] = 0xAB; bytes[offset++] = 0xCD; bytes[offset++] = 0xEF; bytes[offset++] = 0x01;  // CRC

    // Fill rest with stuffing
    memset(bytes + offset, 0xFF, TS_PACKET_SIZE_188 - offset);

    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets[0]];

    XCTAssertEqual(self.receivedTables.count, 2, @"Both sections should be delivered from same packet");
    XCTAssertEqual(self.receivedTables[0].tableId, 0x00);
    XCTAssertEqual(self.receivedTables[0].sectionLength, section1Length);
    XCTAssertEqual(self.receivedTables[1].tableId, 0x02);
    XCTAssertEqual(self.receivedTables[1].sectionLength, section2Length);
}

- (void)test_sectionStartsMidPacketThenSpansMultiplePackets {
    // Section A ends mid-packet, Section B starts in same packet but spans into subsequent packets
    // Packet 1 (PUSI=1, pointer>0): [End of A] [Start of B - incomplete]
    // Packet 2 (PUSI=0): [Continuation of B - still incomplete]
    // Packet 3 (PUSI=0): [End of B]
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    // --- Packet 0: Start section A (will complete in packet 1) ---
    uint16_t sectionALength = 190;  // Spans into packet 1

    NSMutableData *packet0 = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *p0 = packet0.mutableBytes;
    p0[0] = TS_PACKET_HEADER_SYNC_BYTE;
    p0[1] = 0x40; p0[2] = 0x00; p0[3] = 0x10;  // PUSI=1, PID=0, CC=0

    NSUInteger off0 = 4;
    p0[off0++] = 0x00;  // pointer_field = 0
    p0[off0++] = 0x00;  // table_id for section A
    p0[off0++] = 0xB0 | ((sectionALength >> 8) & 0x0F);
    p0[off0++] = sectionALength & 0xFF;
    p0[off0++] = 0x00; p0[off0++] = 0x01;  // tableIdExt = 1
    p0[off0++] = 0xC1;  // version 0
    p0[off0++] = 0x00; p0[off0++] = 0x00;  // section 0/0
    for (NSUInteger i = off0; i < TS_PACKET_SIZE_188; i++) {
        p0[i] = 0xAA;
    }

    NSArray<TSPacket *> *pkt0 = [TSPacket packetsFromChunkedTsData:packet0 packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:pkt0[0]];
    XCTAssertEqual(self.receivedTables.count, 0, @"Section A incomplete after packet 0");

    // --- Packet 1: PUSI=1, pointer_field > 0 ---
    // Contains: [10 bytes end of A] [start of B which will span]
    // Section A needs: 190 - 180 = 10 more bytes
    // Section B: large enough to span packets 1, 2, 3

    uint16_t sectionBLength = 300;  // Will span multiple packets

    NSMutableData *packet1 = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *p1 = packet1.mutableBytes;
    p1[0] = TS_PACKET_HEADER_SYNC_BYTE;
    p1[1] = 0x40; p1[2] = 0x00; p1[3] = 0x11;  // PUSI=1, PID=0, CC=1

    NSUInteger off1 = 4;
    p1[off1++] = 10;  // pointer_field: section B starts 10 bytes later

    // 10 bytes: end of section A (6 data + 4 CRC)
    for (int i = 0; i < 6; i++) p1[off1++] = 0xAA;
    p1[off1++] = 0x12; p1[off1++] = 0x34; p1[off1++] = 0x56; p1[off1++] = 0x78;

    // Section B header
    p1[off1++] = 0x02;  // table_id = 2
    p1[off1++] = 0xB0 | ((sectionBLength >> 8) & 0x0F);
    p1[off1++] = sectionBLength & 0xFF;
    p1[off1++] = 0x00; p1[off1++] = 0x02;  // tableIdExt = 2
    p1[off1++] = 0xC3;  // version 1
    p1[off1++] = 0x00; p1[off1++] = 0x00;  // section 0/0
    // Fill rest of packet with section B data
    for (NSUInteger i = off1; i < TS_PACKET_SIZE_188; i++) {
        p1[i] = 0xBB;
    }
    // Bytes of B in packet 1: 188 - 4 (TS header) - 1 (pointer) - 10 (A tail) - 3 (B section header) = 170 bytes
    // But we also wrote 5 bytes of B's PSI header, so section B data so far: 170 bytes

    NSArray<TSPacket *> *pkt1 = [TSPacket packetsFromChunkedTsData:packet1 packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:pkt1[0]];
    XCTAssertEqual(self.receivedTables.count, 1, @"Section A should be delivered");
    XCTAssertEqual(self.receivedTables[0].tableId, 0x00, @"Section A table_id");

    // --- Packet 2: Continuation and completion of section B (PUSI=0) ---
    // Section B needs 300 bytes. Packet 1 provided ~170 bytes.
    // Packet 2 provides 184 bytes. Total: 354 > 300, so B completes here.
    NSMutableData *packet2 = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *p2 = packet2.mutableBytes;
    p2[0] = TS_PACKET_HEADER_SYNC_BYTE;
    p2[1] = 0x00; p2[2] = 0x00; p2[3] = 0x12;  // PUSI=0, CC=2
    for (int i = 4; i < TS_PACKET_SIZE_188; i++) {
        p2[i] = 0xBB;
    }

    NSArray<TSPacket *> *pkt2 = [TSPacket packetsFromChunkedTsData:packet2 packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:pkt2[0]];

    // Both sections should now be delivered
    XCTAssertEqual(self.receivedTables.count, 2, @"Both sections should be delivered");
    XCTAssertEqual(self.receivedTables[0].tableId, 0x00, @"Section A table_id");
    XCTAssertEqual(self.receivedTables[0].sectionLength, sectionALength);
    XCTAssertEqual(self.receivedTables[1].tableId, 0x02, @"Section B table_id");
    XCTAssertEqual(self.receivedTables[1].sectionLength, sectionBLength);
}

- (void)test_versionChange_discardsOldSections {
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    // Create section 0 of version 1
    NSData *payload0 = [@"OLD" dataUsingEncoding:NSUTF8StringEncoding];
    TSPacket *packet0 = [TSTestUtils createPsiPacketWithPid:0x00
                                             tableId:0x00
                                    tableIdExtension:0x0001
                                       versionNumber:1
                                       sectionNumber:0
                                   lastSectionNumber:1
                                             payload:payload0
                                  continuityCounter:0];

    [builder addTsPacket:packet0];
    XCTAssertEqual(self.receivedTables.count, 0);

    // Now receive new version (complete single-section table)
    NSData *payloadNew = [@"NEW" dataUsingEncoding:NSUTF8StringEncoding];
    TSPacket *packetNew = [TSTestUtils createPsiPacketWithPid:0x00
                                              tableId:0x00
                                     tableIdExtension:0x0001
                                        versionNumber:2
                                        sectionNumber:0
                                    lastSectionNumber:0
                                              payload:payloadNew
                                   continuityCounter:1];

    [builder addTsPacket:packetNew];
    XCTAssertEqual(self.receivedTables.count, 1, @"New version should be delivered");
    XCTAssertEqual(self.receivedTables[0].versionNumber, 2, @"Should be the new version");
}

@end
