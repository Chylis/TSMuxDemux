//
//  TSPmtUpdateTests.m
//  TSMuxDemuxTests
//
//  Tests for dynamic PMT updates - adding, removing, and replacing streams.
//

#import <XCTest/XCTest.h>
#import "../TSTestUtils.h"
@import TSMuxDemux;

static const uint16_t kTestPmtPid = 0x100;
static const uint16_t kTestVideoPid = 0x101;
static const uint16_t kTestAudioPid = 0x102;
static const uint16_t kTestAudio2Pid = 0x103;

#pragma mark - Test Delegate

@interface TSPmtUpdateTestDelegate : NSObject <TSDemuxerDelegate>
@property (nonatomic, strong) NSMutableArray<TSProgramMapTable *> *receivedPmts;
@property (nonatomic, strong) NSMutableArray *receivedPreviousPmts;  // TSProgramMapTable or NSNull
@property (nonatomic, strong) NSMutableArray<TSAccessUnit *> *receivedAccessUnits;
@end

@implementation TSPmtUpdateTestDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _receivedPmts = [NSMutableArray array];
        _receivedPreviousPmts = [NSMutableArray array];
        _receivedAccessUnits = [NSMutableArray array];
    }
    return self;
}

- (void)demuxer:(TSDemuxer *)demuxer didReceivePat:(TSProgramAssociationTable *)pat previousPat:(TSProgramAssociationTable *)previousPat {}

- (void)demuxer:(TSDemuxer *)demuxer didReceivePmt:(TSProgramMapTable *)pmt previousPmt:(TSProgramMapTable *)previousPmt {
    [self.receivedPmts addObject:pmt];
    [self.receivedPreviousPmts addObject:(id)(previousPmt ?: [NSNull null])];
}

- (void)demuxer:(TSDemuxer *)demuxer didReceiveAccessUnit:(TSAccessUnit *)accessUnit {
    [self.receivedAccessUnits addObject:accessUnit];
}

@end

#pragma mark - Tests

@interface TSPmtUpdateTests : XCTestCase
@property (nonatomic, strong) TSPmtUpdateTestDelegate *delegate;
@property (nonatomic, strong) TSDemuxer *demuxer;
@end

@implementation TSPmtUpdateTests

- (void)setUp {
    [super setUp];
    self.delegate = [[TSPmtUpdateTestDelegate alloc] init];
    self.demuxer = [[TSDemuxer alloc] initWithDelegate:self.delegate mode:TSDemuxerModeDVB];

    // Setup PAT
    [self.demuxer demux:[TSTestUtils createPatDataWithPmtPid:kTestPmtPid] dataArrivalHostTimeNanos:0];
}

#pragma mark - Stream Addition Tests

- (void)test_pmtUpdate_addAudioStream {
    // Initial PMT with video only
    TSElementaryStream *videoStream = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                                   streamType:kRawStreamTypeH264
                                                                  descriptors:nil];
    NSData *pmt1 = [TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                 pcrPid:kTestVideoPid
                                                streams:@[videoStream]
                                          versionNumber:0
                                      continuityCounter:0];
    [self.demuxer demux:pmt1 dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPmts.count, 1);
    XCTAssertEqual(self.delegate.receivedPmts[0].elementaryStreams.count, 1);

    // Updated PMT with video + audio (version 1)
    TSElementaryStream *audioStream = [[TSElementaryStream alloc] initWithPid:kTestAudioPid
                                                                   streamType:kRawStreamTypeADTSAAC
                                                                  descriptors:nil];
    NSData *pmt2 = [TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                 pcrPid:kTestVideoPid
                                                streams:@[videoStream, audioStream]
                                          versionNumber:1
                                      continuityCounter:1];
    [self.demuxer demux:pmt2 dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPmts.count, 2);
    XCTAssertEqual(self.delegate.receivedPmts[1].elementaryStreams.count, 2);

    // Verify previous PMT was provided
    XCTAssertNotEqual(self.delegate.receivedPreviousPmts[1], [NSNull null]);
    TSProgramMapTable *prevPmt = self.delegate.receivedPreviousPmts[1];
    XCTAssertEqual(prevPmt.elementaryStreams.count, 1);
}

- (void)test_pmtUpdate_addedStreamReceivesData {
    // Initial PMT with video only
    TSElementaryStream *videoStream = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                                   streamType:kRawStreamTypeH264
                                                                  descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[videoStream]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Add audio stream
    TSElementaryStream *audioStream = [[TSElementaryStream alloc] initWithPid:kTestAudioPid
                                                                   streamType:kRawStreamTypeADTSAAC
                                                                  descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[videoStream, audioStream]
                                               versionNumber:1
                                           continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    // Send audio data - should be received after PMT update
    TSElementaryStream *audioTrack = [[TSElementaryStream alloc] initWithPid:kTestAudioPid
                                                                  streamType:kRawStreamTypeADTSAAC
                                                                 descriptors:nil];
    uint8_t audioPayload[] = {0xFF, 0xF1, 0x50, 0x80, 0x02, 0x1F, 0xFC};
    NSData *audioData = [NSData dataWithBytes:audioPayload length:sizeof(audioPayload)];

    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:audioTrack
                                                    payload:audioData
                                                        pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:audioTrack
                                                    payload:audioData
                                                        pts:CMTimeMake(3000, 90000)]
             dataArrivalHostTimeNanos:0];

    // Should have received audio access unit
    NSUInteger audioAuCount = 0;
    for (TSAccessUnit *au in self.delegate.receivedAccessUnits) {
        if (au.pid == kTestAudioPid) {
            audioAuCount++;
        }
    }
    XCTAssertGreaterThanOrEqual(audioAuCount, 1, @"Should receive audio after stream added to PMT");
}

#pragma mark - Stream Removal Tests

- (void)test_pmtUpdate_removeAudioStream {
    // Initial PMT with video + audio
    TSElementaryStream *videoStream = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                                   streamType:kRawStreamTypeH264
                                                                  descriptors:nil];
    TSElementaryStream *audioStream = [[TSElementaryStream alloc] initWithPid:kTestAudioPid
                                                                   streamType:kRawStreamTypeADTSAAC
                                                                  descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[videoStream, audioStream]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPmts[0].elementaryStreams.count, 2);

    // Updated PMT with video only (audio removed)
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[videoStream]
                                               versionNumber:1
                                           continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPmts.count, 2);
    XCTAssertEqual(self.delegate.receivedPmts[1].elementaryStreams.count, 1);

    // Verify previous PMT had 2 streams
    TSProgramMapTable *prevPmt = self.delegate.receivedPreviousPmts[1];
    XCTAssertEqual(prevPmt.elementaryStreams.count, 2);
}

- (void)test_pmtUpdate_removedStreamIgnored {
    // Initial PMT with video + audio
    TSElementaryStream *videoStream = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                                   streamType:kRawStreamTypeH264
                                                                  descriptors:nil];
    TSElementaryStream *audioStream = [[TSElementaryStream alloc] initWithPid:kTestAudioPid
                                                                   streamType:kRawStreamTypeADTSAAC
                                                                  descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[videoStream, audioStream]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Send some audio data
    TSElementaryStream *audioTrack = [[TSElementaryStream alloc] initWithPid:kTestAudioPid
                                                                  streamType:kRawStreamTypeADTSAAC
                                                                 descriptors:nil];
    uint8_t audioPayload[] = {0xFF, 0xF1, 0x50, 0x80, 0x02, 0x1F, 0xFC};
    NSData *audioData = [NSData dataWithBytes:audioPayload length:sizeof(audioPayload)];
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:audioTrack
                                                    payload:audioData
                                                        pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:audioTrack
                                                    payload:audioData
                                                        pts:CMTimeMake(3000, 90000)]
             dataArrivalHostTimeNanos:0];

    NSUInteger audioCountBefore = 0;
    for (TSAccessUnit *au in self.delegate.receivedAccessUnits) {
        if (au.pid == kTestAudioPid) audioCountBefore++;
    }

    // Remove audio from PMT
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[videoStream]
                                               versionNumber:1
                                           continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    // Send more audio data - should be ignored (no builder for this PID)
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:audioTrack
                                                    payload:audioData
                                                        pts:CMTimeMake(6000, 90000)]
             dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:audioTrack
                                                    payload:audioData
                                                        pts:CMTimeMake(9000, 90000)]
             dataArrivalHostTimeNanos:0];

    NSUInteger audioCountAfter = 0;
    for (TSAccessUnit *au in self.delegate.receivedAccessUnits) {
        if (au.pid == kTestAudioPid) audioCountAfter++;
    }

    // Should not have received any new audio after removal
    XCTAssertEqual(audioCountAfter, audioCountBefore,
                   @"Should not receive audio data after stream removed from PMT");
}

#pragma mark - Stream Replacement Tests

- (void)test_pmtUpdate_replaceAudioStream {
    // Initial PMT with video + audio1
    TSElementaryStream *videoStream = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                                   streamType:kRawStreamTypeH264
                                                                  descriptors:nil];
    TSElementaryStream *audio1Stream = [[TSElementaryStream alloc] initWithPid:kTestAudioPid
                                                                    streamType:kRawStreamTypeADTSAAC
                                                                   descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[videoStream, audio1Stream]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Replace audio1 with audio2 (different PID)
    TSElementaryStream *audio2Stream = [[TSElementaryStream alloc] initWithPid:kTestAudio2Pid
                                                                    streamType:kRawStreamTypeADTSAAC
                                                                   descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[videoStream, audio2Stream]
                                               versionNumber:1
                                           continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPmts.count, 2);

    // New PMT should have audio2, not audio1
    TSProgramMapTable *newPmt = self.delegate.receivedPmts[1];
    XCTAssertNotNil([newPmt elementaryStreamWithPid:kTestAudio2Pid]);
    XCTAssertNil([newPmt elementaryStreamWithPid:kTestAudioPid]);

    // Previous PMT should have audio1
    TSProgramMapTable *prevPmt = self.delegate.receivedPreviousPmts[1];
    XCTAssertNotNil([prevPmt elementaryStreamWithPid:kTestAudioPid]);
    XCTAssertNil([prevPmt elementaryStreamWithPid:kTestAudio2Pid]);
}

- (void)test_pmtUpdate_replacedStreamReceivesData {
    // Initial PMT with video + audio1
    TSElementaryStream *videoStream = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                                   streamType:kRawStreamTypeH264
                                                                  descriptors:nil];
    TSElementaryStream *audio1Stream = [[TSElementaryStream alloc] initWithPid:kTestAudioPid
                                                                    streamType:kRawStreamTypeADTSAAC
                                                                   descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[videoStream, audio1Stream]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Replace with audio2
    TSElementaryStream *audio2Stream = [[TSElementaryStream alloc] initWithPid:kTestAudio2Pid
                                                                    streamType:kRawStreamTypeADTSAAC
                                                                   descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[videoStream, audio2Stream]
                                               versionNumber:1
                                           continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    // Send data on new audio PID
    TSElementaryStream *audio2Track = [[TSElementaryStream alloc] initWithPid:kTestAudio2Pid
                                                                   streamType:kRawStreamTypeADTSAAC
                                                                  descriptors:nil];
    uint8_t audioPayload[] = {0xFF, 0xF1, 0x50, 0x80, 0x02, 0x1F, 0xFC};
    NSData *audioData = [NSData dataWithBytes:audioPayload length:sizeof(audioPayload)];

    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:audio2Track
                                                    payload:audioData
                                                        pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:audio2Track
                                                    payload:audioData
                                                        pts:CMTimeMake(3000, 90000)]
             dataArrivalHostTimeNanos:0];

    // Should have received audio2 data
    NSUInteger audio2Count = 0;
    for (TSAccessUnit *au in self.delegate.receivedAccessUnits) {
        if (au.pid == kTestAudio2Pid) audio2Count++;
    }
    XCTAssertGreaterThanOrEqual(audio2Count, 1, @"Should receive data on replacement stream");
}

#pragma mark - No-Change Tests

- (void)test_pmtUpdate_identicalPmt_noCallback {
    // Send initial PMT
    TSElementaryStream *videoStream = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                                   streamType:kRawStreamTypeH264
                                                                  descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[videoStream]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPmts.count, 1);

    // Send identical PMT again (same version, same streams)
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[videoStream]
                                               versionNumber:0
                                           continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    // Should not trigger another callback
    XCTAssertEqual(self.delegate.receivedPmts.count, 1,
                   @"Identical PMT should not trigger delegate callback");
}

- (void)test_pmtUpdate_versionChangeOnly_triggersCallback {
    // Send initial PMT
    TSElementaryStream *videoStream = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                                   streamType:kRawStreamTypeH264
                                                                  descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[videoStream]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPmts.count, 1);

    // Send PMT with new version but same streams
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[videoStream]
                                               versionNumber:1
                                           continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    // Version change should trigger callback
    XCTAssertEqual(self.delegate.receivedPmts.count, 2,
                   @"Version change should trigger delegate callback");
}

#pragma mark - First PMT Tests

- (void)test_firstPmt_previousPmtIsNil {
    TSElementaryStream *videoStream = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                                   streamType:kRawStreamTypeH264
                                                                  descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                                     streams:@[videoStream]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPmts.count, 1);
    XCTAssertEqual(self.delegate.receivedPreviousPmts[0], [NSNull null],
                   @"First PMT should have nil previousPmt");
}

@end
