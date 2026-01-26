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

#pragma mark - Section Spanning Tests

/// Helper to create a raw TS packet for PSI section spanning tests.
- (NSData *)createSpanningPsiPacketWithPid:(uint16_t)pid
                                   tableId:(uint8_t)tableId
                             sectionLength:(uint16_t)sectionLength
                                      pusi:(BOOL)pusi
                         continuityCounter:(uint8_t)cc
                               sectionData:(NSData *)sectionData
{
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = (pusi ? 0x40 : 0x00) | ((pid >> 8) & 0x1F);
    bytes[2] = pid & 0xFF;
    bytes[3] = 0x10 | (cc & 0x0F);

    NSUInteger offset = 4;

    if (pusi) {
        bytes[offset++] = 0x00;  // pointer_field
        bytes[offset++] = tableId;
        bytes[offset++] = 0xB0 | ((sectionLength >> 8) & 0x0F);
        bytes[offset++] = sectionLength & 0xFF;
    }

    NSUInteger copyLen = MIN(sectionData.length, TS_PACKET_SIZE_188 - offset);
    memcpy(bytes + offset, sectionData.bytes, copyLen);
    offset += copyLen;

    while (offset < TS_PACKET_SIZE_188) {
        bytes[offset++] = 0xFF;
    }

    return packet;
}

- (void)test_sectionSpanningTwoPackets_deliversCompleteSection {
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    uint16_t sectionLength = 190;

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

    NSData *packet1Data = [self createSpanningPsiPacketWithPid:0x00
                                                       tableId:0x00
                                                 sectionLength:sectionLength
                                                          pusi:YES
                                             continuityCounter:0
                                                   sectionData:[fullSectionData subdataWithRange:NSMakeRange(0, 180)]];
    NSArray<TSPacket *> *packets1 = [TSPacket packetsFromChunkedTsData:packet1Data packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets1[0]];

    XCTAssertEqual(self.receivedTables.count, 0, @"Incomplete section should not be delivered");

    NSMutableData *packet2 = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes2 = packet2.mutableBytes;
    bytes2[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes2[1] = 0x00; bytes2[2] = 0x00; bytes2[3] = 0x11;
    memcpy(bytes2 + 4, (uint8_t *)fullSectionData.bytes + 180, 10);
    memset(bytes2 + 14, 0xFF, TS_PACKET_SIZE_188 - 14);

    NSArray<TSPacket *> *packets2 = [TSPacket packetsFromChunkedTsData:packet2 packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets2[0]];

    XCTAssertEqual(self.receivedTables.count, 1, @"Complete section should be delivered");
    XCTAssertEqual(self.receivedTables[0].sectionLength, sectionLength);
}

- (void)test_sectionSpanningPackets_firstPacketExactlyFilled {
    // Edge case: first packet payload is exactly filled (0 bytes remaining)
    // This triggered an infinite loop bug when remainingBytesInPacket == 0
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    uint16_t sectionLength = 200;

    NSMutableData *sectionDataPart1 = [NSMutableData dataWithLength:180];
    uint8_t *part1 = sectionDataPart1.mutableBytes;
    part1[0] = 0x00; part1[1] = 0x01; part1[2] = 0xC1; part1[3] = 0x00; part1[4] = 0x00;
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

    NSMutableData *packet2 = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes2 = packet2.mutableBytes;
    bytes2[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes2[1] = 0x00; bytes2[2] = 0x00; bytes2[3] = 0x11;
    for (int i = 0; i < 16; i++) bytes2[4 + i] = 0xBB;
    bytes2[20] = 0x12; bytes2[21] = 0x34; bytes2[22] = 0x56; bytes2[23] = 0x78;
    memset(bytes2 + 24, 0xFF, TS_PACKET_SIZE_188 - 24);

    NSArray<TSPacket *> *packets2 = [TSPacket packetsFromChunkedTsData:packet2 packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets2[0]];

    XCTAssertEqual(self.receivedTables.count, 1, @"Complete section should be delivered");
    XCTAssertEqual(self.receivedTables[0].sectionLength, sectionLength);
}

- (void)test_sectionSpanningThreePackets_deliversCompleteSection {
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    uint16_t sectionLength = 400;

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

    NSMutableData *packet2 = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes2 = packet2.mutableBytes;
    bytes2[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes2[1] = 0x00; bytes2[2] = 0x00; bytes2[3] = 0x11;
    memset(bytes2 + 4, 0xBB, 184);
    NSArray<TSPacket *> *packets2 = [TSPacket packetsFromChunkedTsData:packet2 packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets2[0]];
    XCTAssertEqual(self.receivedTables.count, 0);

    NSMutableData *packet3 = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes3 = packet3.mutableBytes;
    bytes3[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes3[1] = 0x00; bytes3[2] = 0x00; bytes3[3] = 0x12;
    memset(bytes3 + 4, 0xCC, 32);
    bytes3[36] = 0x12; bytes3[37] = 0x34; bytes3[38] = 0x56; bytes3[39] = 0x78;
    memset(bytes3 + 40, 0xFF, TS_PACKET_SIZE_188 - 40);
    NSArray<TSPacket *> *packets3 = [TSPacket packetsFromChunkedTsData:packet3 packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets3[0]];

    XCTAssertEqual(self.receivedTables.count, 1, @"Section spanning 3 packets should be delivered");
    XCTAssertEqual(self.receivedTables[0].sectionLength, sectionLength);
}

- (void)test_sectionSpanningPackets_minimalBytesInSecondPacket {
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    uint16_t sectionLength = 185;

    NSMutableData *fullSectionData = [NSMutableData dataWithLength:sectionLength];
    uint8_t *sd = fullSectionData.mutableBytes;
    sd[0] = 0x00; sd[1] = 0x01; sd[2] = 0xC1; sd[3] = 0x00; sd[4] = 0x00;
    for (int i = 5; i < sectionLength - 4; i++) sd[i] = (uint8_t)(i & 0xFF);
    sd[sectionLength - 4] = 0x12;
    sd[sectionLength - 3] = 0x34;
    sd[sectionLength - 2] = 0x56;
    sd[sectionLength - 1] = 0x78;

    NSData *packet1Data = [self createSpanningPsiPacketWithPid:0x00
                                                       tableId:0x00
                                                 sectionLength:sectionLength
                                                          pusi:YES
                                             continuityCounter:0
                                                   sectionData:[fullSectionData subdataWithRange:NSMakeRange(0, 180)]];
    NSArray<TSPacket *> *packets1 = [TSPacket packetsFromChunkedTsData:packet1Data packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets1[0]];
    XCTAssertEqual(self.receivedTables.count, 0);

    NSMutableData *packet2 = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes2 = packet2.mutableBytes;
    bytes2[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes2[1] = 0x00; bytes2[2] = 0x00; bytes2[3] = 0x11;
    memcpy(bytes2 + 4, sd + 180, 5);
    memset(bytes2 + 9, 0xFF, TS_PACKET_SIZE_188 - 9);
    NSArray<TSPacket *> *packets2 = [TSPacket packetsFromChunkedTsData:packet2 packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets2[0]];

    XCTAssertEqual(self.receivedTables.count, 1);
    XCTAssertEqual(self.receivedTables[0].sectionLength, sectionLength);
}

- (void)test_backToBackSectionsInSamePacket {
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x40; bytes[2] = 0x00; bytes[3] = 0x10;

    NSUInteger offset = 4;
    bytes[offset++] = 0x00;

    uint16_t section1Length = 13;
    bytes[offset++] = 0x00;
    bytes[offset++] = 0xB0 | ((section1Length >> 8) & 0x0F);
    bytes[offset++] = section1Length & 0xFF;
    bytes[offset++] = 0x00; bytes[offset++] = 0x01;
    bytes[offset++] = 0xC1;
    bytes[offset++] = 0x00; bytes[offset++] = 0x00;
    bytes[offset++] = 0x11; bytes[offset++] = 0x22; bytes[offset++] = 0x33; bytes[offset++] = 0x44;
    bytes[offset++] = 0x12; bytes[offset++] = 0x34; bytes[offset++] = 0x56; bytes[offset++] = 0x78;

    uint16_t section2Length = 13;
    bytes[offset++] = 0x02;
    bytes[offset++] = 0xB0 | ((section2Length >> 8) & 0x0F);
    bytes[offset++] = section2Length & 0xFF;
    bytes[offset++] = 0x00; bytes[offset++] = 0x02;
    bytes[offset++] = 0xC3;
    bytes[offset++] = 0x00; bytes[offset++] = 0x00;
    bytes[offset++] = 0xAA; bytes[offset++] = 0xBB; bytes[offset++] = 0xCC; bytes[offset++] = 0xDD;
    bytes[offset++] = 0xAB; bytes[offset++] = 0xCD; bytes[offset++] = 0xEF; bytes[offset++] = 0x01;

    memset(bytes + offset, 0xFF, TS_PACKET_SIZE_188 - offset);

    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];
    [builder addTsPacket:packets[0]];

    XCTAssertEqual(self.receivedTables.count, 2);
    XCTAssertEqual(self.receivedTables[0].tableId, 0x00);
    XCTAssertEqual(self.receivedTables[1].tableId, 0x02);
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
