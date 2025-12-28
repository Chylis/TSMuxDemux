//
//  TSAccessUnitExtractionTests.m
//  TSMuxDemuxTests
//
//  Tests for end-to-end Access Unit extraction from TS packets.
//

#import <XCTest/XCTest.h>
#import "../TSTestUtils.h"
@import TSMuxDemux;

static const uint16_t kTestPmtPid = 0x100;
static const uint16_t kTestVideoPid = 0x101;

#pragma mark - Test Delegate

@interface TSAccessUnitTestDelegate : NSObject <TSDemuxerDelegate>
@property (nonatomic, strong) NSMutableArray<TSProgramAssociationTable *> *receivedPats;
@property (nonatomic, strong) NSMutableArray<TSProgramMapTable *> *receivedPmts;
@property (nonatomic, strong) NSMutableArray<TSAccessUnit *> *receivedAccessUnits;
@end

@implementation TSAccessUnitTestDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _receivedPats = [NSMutableArray array];
        _receivedPmts = [NSMutableArray array];
        _receivedAccessUnits = [NSMutableArray array];
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

@interface TSAccessUnitExtractionTests : XCTestCase
@property (nonatomic, strong) TSAccessUnitTestDelegate *delegate;
@property (nonatomic, strong) TSDemuxer *demuxer;
@end

@implementation TSAccessUnitExtractionTests

- (void)setUp {
    [super setUp];
    self.delegate = [[TSAccessUnitTestDelegate alloc] init];
    self.demuxer = [[TSDemuxer alloc] initWithDelegate:self.delegate mode:TSDemuxerModeDVB];
}

#pragma mark - Access Unit Extraction Tests

- (void)test_accessUnitExtraction_h264Video {
    // Create test payload (simulated H.264 NAL unit)
    uint8_t nalData[] = {0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1E,
                         0x9A, 0x74, 0x05, 0x81, 0x10, 0x00, 0x00, 0x03};
    NSData *videoPayload = [NSData dataWithBytes:nalData length:sizeof(nalData)];
    CMTime pts = CMTimeMake(90000, 90000);  // 1 second

    // Feed PAT
    NSData *patData = [TSTestUtils createPatDataWithPmtPid:kTestPmtPid];
    [self.demuxer demux:patData dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats.count, 1, @"Should receive PAT");

    // Feed PMT
    NSData *pmtData = [TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                    pcrPid:kTestVideoPid
                                        elementaryStreamPid:kTestVideoPid
                                                 streamType:kRawStreamTypeH264];
    [self.demuxer demux:pmtData dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPmts.count, 1, @"Should receive PMT");

    // Create track for consistent continuity counter across PES packets
    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    // Feed PES packets (first access unit)
    NSData *pesData1 = [TSTestUtils createPesDataWithTrack:track
                                                   payload:videoPayload
                                                       pts:pts];
    [self.demuxer demux:pesData1 dataArrivalHostTimeNanos:0];

    // Feed another PES to trigger delivery of first access unit
    // (access units are delivered when the next one starts)
    NSData *pesData2 = [TSTestUtils createPesDataWithTrack:track
                                                   payload:videoPayload
                                                       pts:CMTimeMake(93000, 90000)];
    [self.demuxer demux:pesData2 dataArrivalHostTimeNanos:0];

    // Verify access unit was extracted
    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 1,
                                @"Should receive at least one access unit");

    if (self.delegate.receivedAccessUnits.count > 0) {
        TSAccessUnit *au = self.delegate.receivedAccessUnits[0];
        XCTAssertEqual(au.pid, kTestVideoPid);
        XCTAssertEqual(au.streamType, kRawStreamTypeH264);
        XCTAssertEqual([au resolvedStreamType], TSResolvedStreamTypeH264);
        XCTAssertTrue([au isVideo]);
        XCTAssertFalse([au isAudio]);
        XCTAssertTrue(CMTIME_IS_VALID(au.pts), @"PTS should be valid");
        XCTAssertEqualWithAccuracy(CMTimeGetSeconds(au.pts), 1.0, 0.001);
        XCTAssertTrue(au.compressedData.length > 0, @"Should have compressed data");
    }
}

- (void)test_accessUnitExtraction_aacAudio {
    // Create test payload (simulated ADTS AAC frame)
    uint8_t adtsData[] = {0xFF, 0xF1, 0x50, 0x80, 0x03, 0x1F, 0xFC,  // ADTS header
                          0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06};  // Audio data
    NSData *audioPayload = [NSData dataWithBytes:adtsData length:sizeof(adtsData)];
    CMTime pts = CMTimeMake(45000, 90000);  // 0.5 seconds

    // Feed PAT
    NSData *patData = [TSTestUtils createPatDataWithPmtPid:kTestPmtPid];
    [self.demuxer demux:patData dataArrivalHostTimeNanos:0];

    // Feed PMT with AAC stream
    NSData *pmtData = [TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                    pcrPid:kTestVideoPid
                                        elementaryStreamPid:kTestVideoPid
                                                 streamType:kRawStreamTypeADTSAAC];
    [self.demuxer demux:pmtData dataArrivalHostTimeNanos:0];

    // Create track for consistent continuity counter
    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeADTSAAC
                                                            descriptors:nil];

    // Feed PES packets
    NSData *pesData1 = [TSTestUtils createPesDataWithTrack:track
                                                   payload:audioPayload
                                                       pts:pts];
    [self.demuxer demux:pesData1 dataArrivalHostTimeNanos:0];

    // Feed another PES to trigger delivery
    NSData *pesData2 = [TSTestUtils createPesDataWithTrack:track
                                                   payload:audioPayload
                                                       pts:CMTimeMake(48000, 90000)];
    [self.demuxer demux:pesData2 dataArrivalHostTimeNanos:0];

    // Verify access unit was extracted
    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 1,
                                @"Should receive at least one access unit");

    if (self.delegate.receivedAccessUnits.count > 0) {
        TSAccessUnit *au = self.delegate.receivedAccessUnits[0];
        XCTAssertEqual(au.pid, kTestVideoPid);
        XCTAssertEqual(au.streamType, kRawStreamTypeADTSAAC);
        XCTAssertEqual([au resolvedStreamType], TSResolvedStreamTypeAAC_ADTS);
        XCTAssertTrue([au isAudio]);
        XCTAssertFalse([au isVideo]);
    }
}

- (void)test_accessUnitExtraction_noAccessUnitWithoutPmt {
    // Create test payload
    uint8_t nalData[] = {0x00, 0x00, 0x00, 0x01, 0x67};
    NSData *videoPayload = [NSData dataWithBytes:nalData length:sizeof(nalData)];
    CMTime pts = CMTimeMake(90000, 90000);

    // Feed PAT only (no PMT)
    NSData *patData = [TSTestUtils createPatDataWithPmtPid:kTestPmtPid];
    [self.demuxer demux:patData dataArrivalHostTimeNanos:0];

    // Create track
    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    // Feed PES packets directly (without PMT, demuxer doesn't know about the PID)
    NSData *pesData = [TSTestUtils createPesDataWithTrack:track
                                                  payload:videoPayload
                                                      pts:pts];
    [self.demuxer demux:pesData dataArrivalHostTimeNanos:0];

    // Should not receive access units without PMT
    XCTAssertEqual(self.delegate.receivedAccessUnits.count, 0,
                   @"Should not receive access units without PMT");
}

- (void)test_accessUnitExtraction_preservesPayloadIntegrity {
    // Create specific test payload to verify integrity
    uint8_t testPattern[] = {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE};
    NSData *payload = [NSData dataWithBytes:testPattern length:sizeof(testPattern)];
    CMTime pts = CMTimeMake(0, 90000);

    // Setup demuxer with PAT and PMT
    [self.demuxer demux:[TSTestUtils createPatDataWithPmtPid:kTestPmtPid] dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                          elementaryStreamPid:kTestVideoPid
                                                   streamType:kRawStreamTypeH264]
             dataArrivalHostTimeNanos:0];

    // Create track for consistent CC
    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    // Feed PES
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:payload
                                                        pts:pts]
             dataArrivalHostTimeNanos:0];

    // Trigger delivery with second PES
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:payload
                                                        pts:CMTimeMake(3000, 90000)]
             dataArrivalHostTimeNanos:0];

    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 1);

    if (self.delegate.receivedAccessUnits.count > 0) {
        TSAccessUnit *au = self.delegate.receivedAccessUnits[0];
        // Verify the payload is intact
        const uint8_t *bytes = au.compressedData.bytes;
        BOOL found = NO;
        for (NSUInteger i = 0; i + sizeof(testPattern) <= au.compressedData.length; i++) {
            if (memcmp(bytes + i, testPattern, sizeof(testPattern)) == 0) {
                found = YES;
                break;
            }
        }
        XCTAssertTrue(found, @"Original payload pattern should be present in access unit");
    }
}

@end
