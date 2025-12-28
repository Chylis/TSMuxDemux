//
//  TSPsiTableBuilderTests.m
//  TSMuxDemuxTests
//
//  Tests for TSPsiTableBuilder multi-section table handling.
//

#import <XCTest/XCTest.h>
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

#pragma mark - Helper Methods

/// Creates a TS packet containing a complete PSI section.
/// sectionData layout (after section_length):
///   Bytes 0-1: tableIdExtension
///   Byte 2: reserved + versionNumber + currentNextIndicator
///   Byte 3: sectionNumber
///   Byte 4: lastSectionNumber
///   Bytes 5+: payload
- (TSPacket *)createPsiPacketWithPid:(uint16_t)pid
                             tableId:(uint8_t)tableId
                    tableIdExtension:(uint16_t)tableIdExtension
                       versionNumber:(uint8_t)versionNumber
                       sectionNumber:(uint8_t)sectionNumber
                   lastSectionNumber:(uint8_t)lastSectionNumber
                             payload:(NSData *)payload
                  continuityCounter:(uint8_t)cc {
    // Build raw 188-byte TS packet
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    // TS Header (4 bytes)
    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;                    // Sync byte 0x47
    bytes[1] = 0x40 | ((pid >> 8) & 0x1F);                    // PUSI=1, PID high bits
    bytes[2] = pid & 0xFF;                                     // PID low bits
    bytes[3] = 0x10 | (cc & 0x0F);                            // Payload only, CC

    // TS Payload starts at byte 4
    NSUInteger offset = 4;

    // Pointer field (1 byte) - 0 means section starts immediately after
    bytes[offset++] = 0x00;

    // PSI Section Header
    bytes[offset++] = tableId;                                 // Table ID

    // Build section data to calculate section_length
    NSMutableData *sectionData = [NSMutableData data];

    // Table ID extension (2 bytes)
    uint16_t tidExt = CFSwapInt16HostToBig(tableIdExtension);
    [sectionData appendBytes:&tidExt length:2];

    // Reserved + version + current_next (1 byte): 11vvvvvc
    uint8_t versionByte = 0xC0 | ((versionNumber & 0x1F) << 1) | 0x01;
    [sectionData appendBytes:&versionByte length:1];

    // Section number
    [sectionData appendBytes:&sectionNumber length:1];

    // Last section number
    [sectionData appendBytes:&lastSectionNumber length:1];

    // Payload
    if (payload) {
        [sectionData appendData:payload];
    }

    // section_length = sectionData.length + CRC (4 bytes)
    uint16_t sectionLength = (uint16_t)(sectionData.length + 4);

    // Section syntax indicator (1) + private bit (0) + reserved (11) + section_length (12 bits)
    uint16_t byte2and3 = 0xB000 | (sectionLength & 0x0FFF);
    bytes[offset++] = (byte2and3 >> 8) & 0xFF;
    bytes[offset++] = byte2and3 & 0xFF;

    // Section data (excluding CRC)
    memcpy(bytes + offset, sectionData.bytes, sectionData.length);
    offset += sectionData.length;

    // CRC32 (4 bytes) - use dummy value for testing
    uint32_t crc = CFSwapInt32HostToBig(0x12345678);
    memcpy(bytes + offset, &crc, 4);
    offset += 4;

    // Fill rest with stuffing bytes (0xFF)
    while (offset < TS_PACKET_SIZE_188) {
        bytes[offset++] = 0xFF;
    }

    // Parse raw data into TSPacket
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];
    return packets.firstObject;
}

#pragma mark - Tests

- (void)test_singleSectionTable_deliveredImmediately {
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    // Create single-section table (sectionNumber=0, lastSectionNumber=0)
    NSData *payload = [@"SINGLE" dataUsingEncoding:NSUTF8StringEncoding];
    TSPacket *packet = [self createPsiPacketWithPid:0x00
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
    TSPacket *packet0 = [self createPsiPacketWithPid:0x00
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
    TSPacket *packet0 = [self createPsiPacketWithPid:0x00
                                             tableId:0x00
                                    tableIdExtension:0x0001
                                       versionNumber:1
                                       sectionNumber:0
                                   lastSectionNumber:1
                                             payload:payload0
                                  continuityCounter:0];

    // Create section 1 of 2
    NSData *payload1 = [@"PART1" dataUsingEncoding:NSUTF8StringEncoding];
    TSPacket *packet1 = [self createPsiPacketWithPid:0x00
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
    TSPacket *packet0 = [self createPsiPacketWithPid:0x00
                                             tableId:0x00
                                    tableIdExtension:0x0001
                                       versionNumber:1
                                       sectionNumber:0
                                   lastSectionNumber:1
                                             payload:payload0
                                  continuityCounter:0];

    // Create section 1 of 2
    NSData *payload1 = [@"BBB" dataUsingEncoding:NSUTF8StringEncoding];
    TSPacket *packet1 = [self createPsiPacketWithPid:0x00
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
    TSPacket *packet1 = [self createPsiPacketWithPid:0x00
                                             tableId:0x00
                                    tableIdExtension:0x0001
                                       versionNumber:1
                                       sectionNumber:1
                                   lastSectionNumber:1
                                             payload:payload1
                                  continuityCounter:0];

    // Then section 0
    NSData *payload0 = [@"AAA" dataUsingEncoding:NSUTF8StringEncoding];
    TSPacket *packet0 = [self createPsiPacketWithPid:0x00
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

- (void)test_versionChange_discardsOldSections {
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:self pid:0x00];

    // Create section 0 of version 1
    NSData *payload0 = [@"OLD" dataUsingEncoding:NSUTF8StringEncoding];
    TSPacket *packet0 = [self createPsiPacketWithPid:0x00
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
    TSPacket *packetNew = [self createPsiPacketWithPid:0x00
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
