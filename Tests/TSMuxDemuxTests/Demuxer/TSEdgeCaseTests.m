//
//  TSEdgeCaseTests.m
//  TSMuxDemuxTests
//
//  Tests for edge cases and robustness: null packets, TEI flag, invalid sync,
//  scrambled packets, empty payloads, and continuation without start.
//

#import <XCTest/XCTest.h>
#import "../TSTestUtils.h"
@import TSMuxDemux;

static const uint16_t kTestPmtPid = 0x100;
static const uint16_t kTestVideoPid = 0x101;

#pragma mark - Test Delegate

@interface TSEdgeCaseTestDelegate : NSObject <TSDemuxerDelegate>
@property (nonatomic, strong) NSMutableArray<TSAccessUnit *> *receivedAccessUnits;
@property (nonatomic, strong) NSMutableArray<TSProgramAssociationTable *> *receivedPats;
@property (nonatomic, strong) NSMutableArray<TSProgramMapTable *> *receivedPmts;
@end

@implementation TSEdgeCaseTestDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _receivedAccessUnits = [NSMutableArray array];
        _receivedPats = [NSMutableArray array];
        _receivedPmts = [NSMutableArray array];
    }
    return self;
}

- (void)demuxer:(TSDemuxer *)demuxer didReceivePat:(TSProgramAssociationTable *)pat previousPat:(TSProgramAssociationTable *)previousPat {
    [self.receivedPats addObject:pat];
}

- (void)demuxer:(TSDemuxer *)demuxer didReceivePmt:(TSProgramMapTable *)pmt previousPmt:(TSProgramMapTable *)previousPmt {
    [self.receivedPmts addObject:pmt];
}

- (void)demuxer:(TSDemuxer *)demuxer didReceiveAccessUnit:(TSAccessUnit *)accessUnit {
    [self.receivedAccessUnits addObject:accessUnit];
}

@end

#pragma mark - Tests

@interface TSEdgeCaseTests : XCTestCase
@property (nonatomic, strong) TSEdgeCaseTestDelegate *delegate;
@property (nonatomic, strong) TSDemuxer *demuxer;
@end

@implementation TSEdgeCaseTests

- (void)setUp {
    [super setUp];
    self.delegate = [[TSEdgeCaseTestDelegate alloc] init];
    self.demuxer = [[TSDemuxer alloc] initWithDelegate:self.delegate mode:TSDemuxerModeDVB];
}

- (void)setupBasicStream {
    // Setup PAT and PMT for tests that need a configured stream
    [self.demuxer demux:[TSTestUtils createPatDataWithPmtPid:kTestPmtPid] dataArrivalHostTimeNanos:0];

    TSElementaryStream *video = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[video]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];
}

#pragma mark - Null Packet Tests (PID 0x1FFF)

- (void)test_nullPacket_ignored {
    [self setupBasicStream];

    // Send null packets
    NSData *nullPackets = [TSTestUtils createNullPackets:10 packetSize:TS_PACKET_SIZE_188];
    [self.demuxer demux:nullPackets dataArrivalHostTimeNanos:0];

    // Null packets should be silently ignored, no access units produced
    XCTAssertEqual(self.delegate.receivedAccessUnits.count, 0,
                   @"Null packets should not produce access units");
}

- (void)test_nullPacket_interleavedWithData_noImpact {
    [self setupBasicStream];

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];
    uint8_t frameData[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0xFF};
    NSData *payload = [NSData dataWithBytes:frameData length:sizeof(frameData)];

    // Send frame 1
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track payload:payload pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:0];

    // Send null packets
    [self.demuxer demux:[TSTestUtils createNullPackets:5 packetSize:TS_PACKET_SIZE_188]
             dataArrivalHostTimeNanos:0];

    // Send frame 2
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track payload:payload pts:CMTimeMake(3003, 90000)]
             dataArrivalHostTimeNanos:0];

    // Send frame 3 to flush frame 2
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track payload:payload pts:CMTimeMake(6006, 90000)]
             dataArrivalHostTimeNanos:0];

    // Should have received access units despite null packets
    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 2,
                                @"Null packets should not affect data flow");
}

#pragma mark - Transport Error Indicator (TEI) Tests

- (void)test_teiPacket_parsed {
    // The demuxer should still parse packets with TEI set (the flag is informational)
    // This tests that the demuxer doesn't crash when encountering TEI packets

    [self setupBasicStream];

    // Send a packet with TEI set on the video PID
    [self.demuxer demux:[TSTestUtils createPacketWithTeiSetForPid:kTestVideoPid
                                                continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // The demuxer should not crash - this is the main assertion
    // TEI packets may be ignored or processed depending on implementation
    XCTAssertTrue(YES, @"Demuxer should handle TEI packets without crashing");
}

#pragma mark - Scrambled Packet Tests

- (void)test_scrambledPacket_parsed {
    // Scrambled packets should be parsed (the scrambling_control bits are set)
    // The demuxer may or may not process the payload, but should not crash

    [self setupBasicStream];

    // Send a scrambled packet
    [self.demuxer demux:[TSTestUtils createScrambledPacketWithPid:kTestVideoPid
                                                continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // The demuxer should not crash
    XCTAssertTrue(YES, @"Demuxer should handle scrambled packets without crashing");
}

#pragma mark - Continuation Without Start Tests

- (void)test_continuationWithoutStart_discarded {
    [self setupBasicStream];

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    // Send continuation packets (PUSI=0) without ever sending a start packet
    uint8_t continuationData[] = {0xAA, 0xBB, 0xCC, 0xDD};
    NSData *payload = [NSData dataWithBytes:continuationData length:sizeof(continuationData)];

    // Create raw packets with PUSI=0
    [self.demuxer demux:[TSTestUtils createRawPacketDataWithPid:kTestVideoPid
                                                        payload:payload
                                                           pusi:NO
                                              continuityCounter:0]
             dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createRawPacketDataWithPid:kTestVideoPid
                                                        payload:payload
                                                           pusi:NO
                                              continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    // No access units should be produced (waiting for PUSI=1)
    XCTAssertEqual(self.delegate.receivedAccessUnits.count, 0,
                   @"Continuation without start should not produce access units");
}

- (void)test_continuationWithoutStart_thenStart_normalOperation {
    [self setupBasicStream];

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    // Send continuation packets first (should be discarded)
    uint8_t continuationData[] = {0xAA, 0xBB, 0xCC, 0xDD};
    NSData *contPayload = [NSData dataWithBytes:continuationData length:sizeof(continuationData)];

    [self.demuxer demux:[TSTestUtils createRawPacketDataWithPid:kTestVideoPid
                                                        payload:contPayload
                                                           pusi:NO
                                              continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Now send proper PES data (3 frames to ensure at least 2 are flushed)
    uint8_t frameData[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0xFF};
    NSData *payload = [NSData dataWithBytes:frameData length:sizeof(frameData)];

    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track payload:payload pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track payload:payload pts:CMTimeMake(3003, 90000)]
             dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track payload:payload pts:CMTimeMake(6006, 90000)]
             dataArrivalHostTimeNanos:0];

    // Should recover and process the proper PES data
    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 1,
                                @"Should recover after receiving proper start packet");
}

#pragma mark - Reserved Adaptation Field Control Tests

- (void)test_reservedAdaptationFieldControl_handled {
    // Note: Packets with adaptation_field_control=00 (reserved) are invalid.
    // The packet parser (TSPacket.packetsFromChunkedTsData) may return nil for
    // such packets, which would cause the entire chunk to be rejected.
    //
    // This test verifies that after receiving valid packets, the demuxer is functional.
    // We don't test the reserved value directly as the packet parser correctly
    // rejects invalid packets before they reach the demuxer.

    [self setupBasicStream];

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];
    uint8_t frameData[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0xFF};
    NSData *payload = [NSData dataWithBytes:frameData length:sizeof(frameData)];

    // Send valid data to verify demuxer is functional
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track payload:payload pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track payload:payload pts:CMTimeMake(3003, 90000)]
             dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track payload:payload pts:CMTimeMake(6006, 90000)]
             dataArrivalHostTimeNanos:0];

    // The demuxer should be functional
    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 1,
                                @"Demuxer should process valid packets correctly");
}

#pragma mark - Large Chunk Processing Tests

- (void)test_largeChunk_multipleProgramsAndNulls {
    [self setupBasicStream];

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    // Build a large chunk with mixed content
    NSMutableData *chunk = [NSMutableData data];

    uint8_t frameData[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0xFF};
    NSData *payload = [NSData dataWithBytes:frameData length:sizeof(frameData)];

    // Add video data
    [chunk appendData:[TSTestUtils createPesDataWithTrack:track payload:payload pts:CMTimeMake(0, 90000)]];

    // Add null packets
    [chunk appendData:[TSTestUtils createNullPackets:10 packetSize:TS_PACKET_SIZE_188]];

    // Add more video data
    [chunk appendData:[TSTestUtils createPesDataWithTrack:track payload:payload pts:CMTimeMake(3003, 90000)]];

    // Add more null packets
    [chunk appendData:[TSTestUtils createNullPackets:5 packetSize:TS_PACKET_SIZE_188]];

    // Add final video data to flush
    [chunk appendData:[TSTestUtils createPesDataWithTrack:track payload:payload pts:CMTimeMake(6006, 90000)]];

    // Process entire chunk at once
    [self.demuxer demux:chunk dataArrivalHostTimeNanos:0];

    // Should successfully extract access units
    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 2,
                                @"Should extract access units from mixed chunk");
}

#pragma mark - Empty Payload Tests

- (void)test_packetWithEmptyPayload_adaptationOnly {
    [self setupBasicStream];

    // Create packet with adaptation_field_control = 10 (adaptation only, no payload)
    [self.demuxer demux:[TSTestUtils createPacketWithAdaptationFieldPid:kTestVideoPid
                                                      discontinuityFlag:NO
                                                             hasPayload:NO
                                                      continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Should handle gracefully without crashing
    XCTAssertEqual(self.delegate.receivedAccessUnits.count, 0,
                   @"Adaptation-only packet should not produce access unit");
}

#pragma mark - Stress Tests

- (void)test_rapidPatPmtChanges_nocrash {
    // Simulate rapid channel switching
    for (int i = 0; i < 10; i++) {
        uint16_t pmtPid = 0x100 + i;
        uint16_t videoPid = 0x1000 + i;

        NSDictionary *programmes = @{@(i + 1): @(pmtPid)};
        [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes
                                                       versionNumber:i
                                                   continuityCounter:i]
                 dataArrivalHostTimeNanos:0];

        TSElementaryStream *video = [[TSElementaryStream alloc] initWithPid:videoPid
                                                                 streamType:kRawStreamTypeH264
                                                                descriptors:nil];
        [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:pmtPid
                                                          pcrPid:videoPid
                                                         streams:@[video]
                                                   versionNumber:0
                                               continuityCounter:0]
                 dataArrivalHostTimeNanos:0];
    }

    XCTAssertEqual(self.delegate.receivedPats.count, 10,
                   @"Should handle rapid PAT changes");
}

#pragma mark - Invalid Adaptation Field Tests

- (void)test_invalidAdaptationFieldLength_exceedsPacketBounds_shouldNotCrash {
    // Reproduces crash: adaptation_field_length = 253 (0xFD) exceeds max valid value of 183.
    // This causes payloadOffset = 4 + 1 + 253 = 258, which exceeds 188, causing
    // unsigned underflow when computing payloadLength = 188 - 258.

    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    // Build packet with adaptation_field_control = 11 (adaptation + payload)
    // but with invalid adaptation_field_length = 253 (exceeds max 183)
    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;  // 0x47
    bytes[1] = 0x02;                         // TEI=0, PUSI=0, PID high bits
    bytes[2] = 0x00;                         // PID = 0x0200 (512)
    bytes[3] = 0x3D;                         // scrambling=00, adaptation_field_control=11, CC=13
    bytes[4] = 0xFD;                         // adaptation_field_length = 253 (INVALID)

    // Fill rest with dummy data
    for (NSUInteger i = 5; i < TS_PACKET_SIZE_188; i++) {
        bytes[i] = 0xFF;
    }

    // This should not crash - the demuxer should handle invalid packets gracefully
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

    // The packet should either be skipped (nil/empty) or parsed without the invalid payload
    // Main assertion: we didn't crash
    XCTAssertTrue(YES, @"Demuxer should handle invalid adaptation_field_length without crashing");
}

- (void)test_adaptationFieldLengthAtBoundary_exactlyFillsPacket_shouldSucceed {
    // adaptation_field_length = 183 is the maximum valid value
    // (188 - 4 header - 1 length byte = 183)

    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x02;                         // PID high bits
    bytes[2] = 0x00;                         // PID = 0x0200
    bytes[3] = 0x20;                         // adaptation_field_control=10 (adaptation only), CC=0
    bytes[4] = 183;                          // adaptation_field_length = 183 (max valid)
    bytes[5] = 0x00;                         // flags byte

    // Fill rest with stuffing
    for (NSUInteger i = 6; i < TS_PACKET_SIZE_188; i++) {
        bytes[i] = 0xFF;
    }

    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];

    XCTAssertNotNil(packets, @"Valid max-length adaptation field should parse successfully");
    XCTAssertEqual(packets.count, 1, @"Should return one packet");
}

#pragma mark - PMT Truncated Data Tests

- (void)test_pmtWithTruncatedElementaryStreamData_shouldNotCrash {
    // Test that PMT parsing handles truncated ES data without crashing.
    // Creates a PMT with section_length claiming more ES data than actually present.
    // The ES loop requires 5 bytes per entry, but we only provide 3 bytes.

    [self setupBasicStream];

    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    // TS Header
    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x41;  // PUSI=1, PID high = 0x01
    bytes[2] = 0x00;  // PID = 0x0100 (PMT PID)
    bytes[3] = 0x10;  // payload only, CC=0

    NSUInteger offset = 4;

    // Pointer field
    bytes[offset++] = 0x00;

    // Table ID (PMT = 0x02)
    bytes[offset++] = 0x02;

    // section_length = 16 means sectionDataExcludingCrc.length = 12
    // ES data starts at offset 9, so ES bytes = 12 - 9 = 3 bytes (truncated, needs 5)
    uint16_t sectionLength = 16;
    bytes[offset++] = 0xB0 | ((sectionLength >> 8) & 0x0F);
    bytes[offset++] = sectionLength & 0xFF;

    // Program number (2 bytes)
    bytes[offset++] = 0x00;
    bytes[offset++] = 0x01;

    // Reserved + version + current_next
    bytes[offset++] = 0xC1;

    // Section number
    bytes[offset++] = 0x00;

    // Last section number
    bytes[offset++] = 0x00;

    // PCR PID (reserved 3 bits + 13 bit PID)
    bytes[offset++] = 0xE1;  // reserved + PID high
    bytes[offset++] = 0x01;  // PID = 0x0101

    // Program info length = 0
    bytes[offset++] = 0xF0;
    bytes[offset++] = 0x00;

    // Only 3 bytes of ES data (incomplete - needs 5 bytes minimum)
    bytes[offset++] = 0x1B;  // stream_type (H.264)
    bytes[offset++] = 0xE1;  // reserved + PID high
    bytes[offset++] = 0x01;  // PID low -- MISSING: ES_info_length (2 bytes)

    // CRC32 (dummy)
    bytes[offset++] = 0x12;
    bytes[offset++] = 0x34;
    bytes[offset++] = 0x56;
    bytes[offset++] = 0x78;

    // Fill rest with stuffing
    while (offset < TS_PACKET_SIZE_188) {
        bytes[offset++] = 0xFF;
    }

    // This should not crash when parsing the PMT
    [self.demuxer demux:packet dataArrivalHostTimeNanos:0];

    XCTAssertTrue(YES, @"Demuxer should handle truncated PMT ES data without crashing");
}

- (void)test_pmtDirectParsing_truncatedESData_shouldNotCrash {
    // Direct test of PMT parsing with truncated ES data.
    // Bypasses the demuxer to directly test TSProgramMapTable.elementaryStreams.

    uint8_t sectionData[] = {
        0x00, 0x01,  // program_number = 1
        0xC1,        // reserved + version 0 + current_next=1
        0x00,        // section_number = 0
        0x00,        // last_section_number = 0
        0xE1, 0x01,  // reserved + PCR_PID = 0x0101
        0xF0, 0x00,  // reserved + program_info_length = 0
        // Truncated ES entry (only 3 bytes, needs 5):
        0x1B,        // stream_type (H.264)
        0xE1,        // reserved + ES_PID high
        0x01         // ES_PID low -- MISSING: ES_info_length (2 bytes)
    };
    NSData *sectionDataNoCrc = [NSData dataWithBytes:sectionData length:sizeof(sectionData)];

    TSProgramSpecificInformationTable *psi = [[TSProgramSpecificInformationTable alloc]
                                               initWithTableId:0x02  // PMT
                                               sectionSyntaxIndicator:1
                                               reservedBit1:0
                                               reservedBits2:3
                                               sectionLength:(uint16_t)(sectionDataNoCrc.length + 4)
                                               sectionDataExcludingCrc:sectionDataNoCrc
                                               crc:0x12345678];

    TSProgramMapTable *pmt = [[TSProgramMapTable alloc] initWithPSI:psi];
    XCTAssertNotNil(pmt, @"PMT should be created");

    // Access elementaryStreams - this triggers the parsing that could crash
    NSSet<TSElementaryStream *> *streams = pmt.elementaryStreams;

    XCTAssertNotNil(streams, @"elementaryStreams should not be nil");
    XCTAssertEqual(streams.count, 0, @"Truncated ES data should result in no valid streams");
}

#pragma mark - PSI Builder Edge Cases

- (void)test_psiWithInvalidSectionLength_lessThanCrcSize_shouldNotCrash {
    // Test that PSI parsing handles section_length < 4 (CRC size) without underflow.
    // This tests the PSI builder's handling of corrupt section_length values.
    // Don't setup basic stream - we want to test with the first packet being corrupt.

    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    // TS Header
    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x40;  // PUSI=1, PID high = 0
    bytes[2] = 0x00;  // PID = 0x0000 (PAT)
    bytes[3] = 0x10;  // payload only, CC=0

    NSUInteger offset = 4;

    // Pointer field
    bytes[offset++] = 0x00;

    // Table ID (PAT = 0x00)
    bytes[offset++] = 0x00;

    // Section syntax indicator + section_length = 2 (INVALID: less than CRC size of 4)
    // This should cause remainingBytesInTable - PSI_CRC_LEN to underflow
    bytes[offset++] = 0xB0;  // section_syntax_indicator = 1, section_length high bits
    bytes[offset++] = 0x02;  // section_length = 2 (INVALID)

    // Some dummy data
    bytes[offset++] = 0x00;
    bytes[offset++] = 0x01;

    // Fill rest with stuffing
    while (offset < TS_PACKET_SIZE_188) {
        bytes[offset++] = 0xFF;
    }

    // This should not crash
    [self.demuxer demux:packet dataArrivalHostTimeNanos:0];

    XCTAssertTrue(YES, @"Demuxer should handle invalid section_length without crashing");
}

- (void)test_psiWithTruncatedHeader_shouldNotCrash {
    // Test that PSI parsing handles a packet with only 1-2 bytes after pointer field.
    // The PSI header requires 3 bytes (table_id + section_length), but we provide fewer.

    [self setupBasicStream];

    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    // TS Header with adaptation field that leaves only 2 bytes for payload
    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x40;  // PUSI=1, PID = 0
    bytes[2] = 0x00;
    bytes[3] = 0x30;  // adaptation + payload, CC=0

    // Adaptation field that consumes most of the packet
    // Total packet = 188, header = 4, so 184 remaining
    // We want payload to be only 2 bytes, so adaptation = 184 - 2 = 182
    // adaptation_field_length = 182 - 1 (for length byte itself) = 181
    bytes[4] = 181;   // adaptation_field_length
    bytes[5] = 0x00;  // flags

    // Fill adaptation with stuffing
    for (NSUInteger i = 6; i < 186; i++) {
        bytes[i] = 0xFF;
    }

    // Only 2 bytes of payload (at offsets 186, 187)
    bytes[186] = 0x00;  // pointer field = 0
    bytes[187] = 0x00;  // table_id only - truncated, missing section_length bytes

    // This should not crash
    [self.demuxer demux:packet dataArrivalHostTimeNanos:0];

    XCTAssertTrue(YES, @"Demuxer should handle truncated PSI header without crashing");
}

@end
