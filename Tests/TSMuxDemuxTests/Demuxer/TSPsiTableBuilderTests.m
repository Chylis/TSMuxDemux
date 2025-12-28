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
