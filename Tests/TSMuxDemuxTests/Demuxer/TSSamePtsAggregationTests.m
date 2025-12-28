//
//  TSSamePtsAggregationTests.m
//  TSMuxDemuxTests
//
//  Tests for same-PTS aggregation in TSElementaryStreamBuilder.
//  This handles interlaced video (top/bottom fields) and multi-slice frames
//  that are sent in separate PES packets but share the same PTS.
//

#import <XCTest/XCTest.h>
#import "../TSTestUtils.h"
@import TSMuxDemux;

static const uint16_t kTestPmtPid = 0x100;
static const uint16_t kTestVideoPid = 0x101;

#pragma mark - Test Delegate

@interface TSSamePtsTestDelegate : NSObject <TSDemuxerDelegate>
@property (nonatomic, strong) NSMutableArray<TSAccessUnit *> *receivedAccessUnits;
@end

@implementation TSSamePtsTestDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _receivedAccessUnits = [NSMutableArray array];
    }
    return self;
}

- (void)demuxer:(TSDemuxer *)demuxer didReceivePat:(TSProgramAssociationTable *)pat previousPat:(TSProgramAssociationTable *)previousPat {}
- (void)demuxer:(TSDemuxer *)demuxer didReceivePmt:(TSProgramMapTable *)pmt previousPmt:(TSProgramMapTable *)previousPmt {}

- (void)demuxer:(TSDemuxer *)demuxer didReceiveAccessUnit:(TSAccessUnit *)accessUnit {
    [self.receivedAccessUnits addObject:accessUnit];
}

@end

#pragma mark - Tests

@interface TSSamePtsAggregationTests : XCTestCase
@property (nonatomic, strong) TSSamePtsTestDelegate *delegate;
@property (nonatomic, strong) TSDemuxer *demuxer;
@property (nonatomic, strong) TSElementaryStream *videoTrack;
@end

@implementation TSSamePtsAggregationTests

- (void)setUp {
    [super setUp];
    self.delegate = [[TSSamePtsTestDelegate alloc] init];
    self.demuxer = [[TSDemuxer alloc] initWithDelegate:self.delegate mode:TSDemuxerModeDVB];

    // Setup PAT and PMT
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

    self.videoTrack = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                   streamType:kRawStreamTypeH264
                                                  descriptors:nil];
}

#pragma mark - Interlaced Video Tests (Two Fields, Same PTS)

- (void)test_samePts_interlacedFields_aggregated {
    // Simulate interlaced video: top field and bottom field with same PTS
    CMTime pts = CMTimeMake(90000, 90000);  // 1 second

    uint8_t topFieldData[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0x01, 0x02, 0x03};  // NAL slice top
    uint8_t bottomFieldData[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0x04, 0x05, 0x06};  // NAL slice bottom

    NSData *topField = [NSData dataWithBytes:topFieldData length:sizeof(topFieldData)];
    NSData *bottomField = [NSData dataWithBytes:bottomFieldData length:sizeof(bottomFieldData)];

    // Send top field
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack payload:topField pts:pts]
             dataArrivalHostTimeNanos:0];

    // Send bottom field with SAME PTS
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack payload:bottomField pts:pts]
             dataArrivalHostTimeNanos:0];

    // Send next frame to flush the aggregated data
    CMTime nextPts = CMTimeMake(93003, 90000);  // ~33ms later (30fps interlaced)
    uint8_t nextFrameData[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0x07, 0x08, 0x09};
    NSData *nextFrame = [NSData dataWithBytes:nextFrameData length:sizeof(nextFrameData)];
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack payload:nextFrame pts:nextPts]
             dataArrivalHostTimeNanos:0];

    // Should have received 1 access unit with combined data
    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 1);

    TSAccessUnit *firstAu = self.delegate.receivedAccessUnits[0];
    XCTAssertEqual(CMTimeCompare(firstAu.pts, pts), 0, @"PTS should match original");

    // Aggregated data should contain both fields
    NSUInteger expectedLength = sizeof(topFieldData) + sizeof(bottomFieldData);
    XCTAssertEqual(firstAu.compressedData.length, expectedLength,
                   @"Aggregated access unit should contain both fields");

    // Verify data integrity
    XCTAssertTrue(memcmp(firstAu.compressedData.bytes, topFieldData, sizeof(topFieldData)) == 0,
                  @"Top field data should be at the start");
    XCTAssertTrue(memcmp(firstAu.compressedData.bytes + sizeof(topFieldData), bottomFieldData, sizeof(bottomFieldData)) == 0,
                  @"Bottom field data should follow top field");
}

#pragma mark - Multi-Slice Frame Tests

- (void)test_samePts_multipleSlices_aggregated {
    // Simulate multi-slice frame: 3 slices with same PTS
    CMTime pts = CMTimeMake(0, 90000);

    uint8_t slice1Data[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0x11};
    uint8_t slice2Data[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0x22};
    uint8_t slice3Data[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0x33};

    NSData *slice1 = [NSData dataWithBytes:slice1Data length:sizeof(slice1Data)];
    NSData *slice2 = [NSData dataWithBytes:slice2Data length:sizeof(slice2Data)];
    NSData *slice3 = [NSData dataWithBytes:slice3Data length:sizeof(slice3Data)];

    // Send all 3 slices with same PTS
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack payload:slice1 pts:pts]
             dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack payload:slice2 pts:pts]
             dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack payload:slice3 pts:pts]
             dataArrivalHostTimeNanos:0];

    // Flush with next frame
    CMTime nextPts = CMTimeMake(3003, 90000);
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack
                                                    payload:[NSData dataWithBytes:slice1Data length:sizeof(slice1Data)]
                                                        pts:nextPts]
             dataArrivalHostTimeNanos:0];

    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 1);

    TSAccessUnit *au = self.delegate.receivedAccessUnits[0];
    NSUInteger expectedLength = sizeof(slice1Data) + sizeof(slice2Data) + sizeof(slice3Data);
    XCTAssertEqual(au.compressedData.length, expectedLength,
                   @"Aggregated access unit should contain all slices");
}

#pragma mark - Different PTS Tests (No Aggregation)

- (void)test_differentPts_notAggregated {
    // Two PES packets with different PTS should produce separate access units
    CMTime pts1 = CMTimeMake(0, 90000);
    CMTime pts2 = CMTimeMake(3003, 90000);  // Different PTS

    uint8_t frame1Data[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0xAA};
    uint8_t frame2Data[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0xBB};

    NSData *frame1 = [NSData dataWithBytes:frame1Data length:sizeof(frame1Data)];
    NSData *frame2 = [NSData dataWithBytes:frame2Data length:sizeof(frame2Data)];

    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack payload:frame1 pts:pts1]
             dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack payload:frame2 pts:pts2]
             dataArrivalHostTimeNanos:0];

    // Flush with a third frame
    CMTime pts3 = CMTimeMake(6006, 90000);
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack payload:frame1 pts:pts3]
             dataArrivalHostTimeNanos:0];

    // Should have 2 separate access units
    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 2);

    TSAccessUnit *au1 = self.delegate.receivedAccessUnits[0];
    TSAccessUnit *au2 = self.delegate.receivedAccessUnits[1];

    XCTAssertEqual(au1.compressedData.length, sizeof(frame1Data));
    XCTAssertEqual(au2.compressedData.length, sizeof(frame2Data));
    XCTAssertEqual(CMTimeCompare(au1.pts, pts1), 0);
    XCTAssertEqual(CMTimeCompare(au2.pts, pts2), 0);
}

#pragma mark - Edge Cases

- (void)test_samePts_preservesFirstDts {
    // When aggregating, the DTS from the first PES should be preserved
    CMTime pts = CMTimeMake(90000, 90000);

    uint8_t field1Data[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0x01};
    uint8_t field2Data[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0x02};

    NSData *field1 = [NSData dataWithBytes:field1Data length:sizeof(field1Data)];
    NSData *field2 = [NSData dataWithBytes:field2Data length:sizeof(field2Data)];

    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack payload:field1 pts:pts]
             dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack payload:field2 pts:pts]
             dataArrivalHostTimeNanos:0];

    // Flush
    CMTime nextPts = CMTimeMake(93003, 90000);
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack payload:field1 pts:nextPts]
             dataArrivalHostTimeNanos:0];

    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 1);

    TSAccessUnit *au = self.delegate.receivedAccessUnits[0];
    XCTAssertEqual(CMTimeCompare(au.pts, pts), 0,
                   @"PTS should be preserved from first PES");
}

- (void)test_samePts_largeFrame_aggregated {
    // Test aggregation with larger payloads (simulating 4K content)
    CMTime pts = CMTimeMake(0, 90000);

    // Create two 50KB "slices"
    NSMutableData *slice1 = [NSMutableData dataWithLength:50 * 1024];
    NSMutableData *slice2 = [NSMutableData dataWithLength:50 * 1024];
    memset(slice1.mutableBytes, 0xAA, slice1.length);
    memset(slice2.mutableBytes, 0xBB, slice2.length);

    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack payload:slice1 pts:pts]
             dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack payload:slice2 pts:pts]
             dataArrivalHostTimeNanos:0];

    // Flush
    CMTime nextPts = CMTimeMake(3003, 90000);
    uint8_t smallFrame[] = {0x00, 0x00, 0x00, 0x01, 0x41};
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.videoTrack
                                                    payload:[NSData dataWithBytes:smallFrame length:sizeof(smallFrame)]
                                                        pts:nextPts]
             dataArrivalHostTimeNanos:0];

    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 1);

    TSAccessUnit *au = self.delegate.receivedAccessUnits[0];
    XCTAssertEqual(au.compressedData.length, 100 * 1024,
                   @"Large aggregated frame should contain both 50KB slices");
}

@end
