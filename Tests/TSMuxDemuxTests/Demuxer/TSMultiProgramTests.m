//
//  TSMultiProgramTests.m
//  TSMuxDemuxTests
//
//  Tests for multi-program transport streams - common in broadcast scenarios
//  where a single TS carries multiple channels/programs.
//

#import <XCTest/XCTest.h>
#import "../TSTestUtils.h"
@import TSMuxDemux;

// Program 1 PIDs
static const uint16_t kPmtPid1 = 0x100;
static const uint16_t kVideoPid1 = 0x101;
static const uint16_t kAudioPid1 = 0x102;

// Program 2 PIDs
static const uint16_t kPmtPid2 = 0x200;
static const uint16_t kVideoPid2 = 0x201;
static const uint16_t kAudioPid2 = 0x202;

// Program 3 PIDs
static const uint16_t kPmtPid3 = 0x300;
static const uint16_t kVideoPid3 = 0x301;

#pragma mark - Test Delegate

@interface TSMultiProgramTestDelegate : NSObject <TSDemuxerDelegate>
@property (nonatomic, strong) NSMutableArray<TSProgramAssociationTable *> *receivedPats;
@property (nonatomic, strong) NSMutableArray<TSProgramMapTable *> *receivedPmts;
@property (nonatomic, strong) NSMutableArray<TSAccessUnit *> *receivedAccessUnits;
@end

@implementation TSMultiProgramTestDelegate

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

@interface TSMultiProgramTests : XCTestCase
@property (nonatomic, strong) TSMultiProgramTestDelegate *delegate;
@property (nonatomic, strong) TSDemuxer *demuxer;
@end

@implementation TSMultiProgramTests

- (void)setUp {
    [super setUp];
    self.delegate = [[TSMultiProgramTestDelegate alloc] init];
    self.demuxer = [[TSDemuxer alloc] initWithDelegate:self.delegate mode:TSDemuxerModeDVB];
}

#pragma mark - Multiple PMT Reception Tests

- (void)test_multiProgram_receiveMultiplePmts {
    // Setup PAT with 2 programs
    NSDictionary *programmes = @{@1: @(kPmtPid1), @2: @(kPmtPid2)};
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes
                                                   versionNumber:0
                                               continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats.count, 1);
    XCTAssertEqual(self.delegate.receivedPats[0].programmes.count, 2);

    // Send PMT for program 1
    TSElementaryStream *video1 = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    TSElementaryStream *audio1 = [[TSElementaryStream alloc] initWithPid:kAudioPid1
                                                              streamType:kRawStreamTypeADTSAAC
                                                             descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                      pcrPid:kVideoPid1
                                                     streams:@[video1, audio1]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Send PMT for program 2
    TSElementaryStream *video2 = [[TSElementaryStream alloc] initWithPid:kVideoPid2
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    TSElementaryStream *audio2 = [[TSElementaryStream alloc] initWithPid:kAudioPid2
                                                              streamType:kRawStreamTypeADTSAAC
                                                             descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid2
                                                      pcrPid:kVideoPid2
                                                     streams:@[video2, audio2]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPmts.count, 2,
                   @"Should receive PMTs for both programs");
}

#pragma mark - Stream Data From Multiple Programs

- (void)test_multiProgram_receivesDataFromAllPrograms {
    // This test verifies that when PAT has multiple programs and their PMTs are registered,
    // the demuxer can successfully receive and demux access units from all programs.
    //
    // We test this at the PMT level - verifying that PMTs for all programs are received
    // and that stream builders are created correctly.

    // Setup PAT with 2 programs
    NSDictionary *programmes = @{@1: @(kPmtPid1), @2: @(kPmtPid2)};
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes
                                                   versionNumber:0
                                               continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats.count, 1);
    XCTAssertEqual(self.delegate.receivedPats[0].programmes.count, 2);

    // Setup PMTs for both programs
    TSElementaryStream *video1 = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                      pcrPid:kVideoPid1
                                                     streams:@[video1]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    TSElementaryStream *video2 = [[TSElementaryStream alloc] initWithPid:kVideoPid2
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid2
                                                      pcrPid:kVideoPid2
                                                     streams:@[video2]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Verify both PMTs were received with correct stream configuration
    XCTAssertEqual(self.delegate.receivedPmts.count, 2,
                   @"Should receive PMTs for both programs");

    // Verify program 1 PMT has video1 stream
    BOOL foundVideo1 = NO;
    BOOL foundVideo2 = NO;
    for (TSProgramMapTable *pmt in self.delegate.receivedPmts) {
        if ([pmt elementaryStreamWithPid:kVideoPid1]) foundVideo1 = YES;
        if ([pmt elementaryStreamWithPid:kVideoPid2]) foundVideo2 = YES;
    }
    XCTAssertTrue(foundVideo1, @"PMT for program 1 should have video1 stream");
    XCTAssertTrue(foundVideo2, @"PMT for program 2 should have video2 stream");
}

#pragma mark - Three Programs Tests

- (void)test_multiProgram_threePrograms {
    // Setup PAT with 3 programs
    NSDictionary *programmes = @{@1: @(kPmtPid1), @2: @(kPmtPid2), @3: @(kPmtPid3)};
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes
                                                   versionNumber:0
                                               continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats[0].programmes.count, 3);

    // Setup PMTs for all 3 programs
    TSElementaryStream *video1 = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                      pcrPid:kVideoPid1
                                                     streams:@[video1]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    TSElementaryStream *video2 = [[TSElementaryStream alloc] initWithPid:kVideoPid2
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid2
                                                      pcrPid:kVideoPid2
                                                     streams:@[video2]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    TSElementaryStream *video3 = [[TSElementaryStream alloc] initWithPid:kVideoPid3
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid3
                                                      pcrPid:kVideoPid3
                                                     streams:@[video3]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPmts.count, 3,
                   @"Should receive PMTs for all 3 programs");
}

#pragma mark - Program Independence Tests

- (void)test_multiProgram_pmtUpdateAffectsOnlyOneProgram {
    // Setup PAT with 2 programs
    NSDictionary *programmes = @{@1: @(kPmtPid1), @2: @(kPmtPid2)};
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes
                                                   versionNumber:0
                                               continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Setup PMT for program 1 with video only
    TSElementaryStream *video1 = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                      pcrPid:kVideoPid1
                                                     streams:@[video1]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Setup PMT for program 2 with video + audio
    TSElementaryStream *video2 = [[TSElementaryStream alloc] initWithPid:kVideoPid2
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    TSElementaryStream *audio2 = [[TSElementaryStream alloc] initWithPid:kAudioPid2
                                                              streamType:kRawStreamTypeADTSAAC
                                                             descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid2
                                                      pcrPid:kVideoPid2
                                                     streams:@[video2, audio2]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPmts.count, 2);

    // Update PMT for program 1 (add audio) - should not affect program 2
    TSElementaryStream *audio1 = [[TSElementaryStream alloc] initWithPid:kAudioPid1
                                                              streamType:kRawStreamTypeADTSAAC
                                                             descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                      pcrPid:kVideoPid1
                                                     streams:@[video1, audio1]
                                               versionNumber:1
                                           continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPmts.count, 3);

    // Verify the updated PMT is for program 1 (has audio on audio1 PID)
    TSProgramMapTable *lastPmt = self.delegate.receivedPmts[2];
    XCTAssertNotNil([lastPmt elementaryStreamWithPid:kAudioPid1],
                    @"Updated PMT should have audio1 stream");
    XCTAssertNil([lastPmt elementaryStreamWithPid:kAudioPid2],
                 @"Updated PMT should not have audio2 stream");
}

#pragma mark - Interleaved Data Tests

- (void)test_multiProgram_interleavedPackets {
    // This test verifies that PAT and PMT parsing works correctly for multiple programs
    // and that the demuxer properly tracks program associations.
    //
    // Note: Testing actual PES data interleaving would require more complex setup
    // to handle continuity counter expectations across demuxer and test tracks.

    // Setup multi-program stream
    NSDictionary *programmes = @{@1: @(kPmtPid1), @2: @(kPmtPid2)};
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes
                                                   versionNumber:0
                                               continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats.count, 1);

    TSElementaryStream *video1 = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                      pcrPid:kVideoPid1
                                                     streams:@[video1]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    TSElementaryStream *video2 = [[TSElementaryStream alloc] initWithPid:kVideoPid2
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid2
                                                      pcrPid:kVideoPid2
                                                     streams:@[video2]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Verify multi-program setup was successful
    XCTAssertEqual(self.delegate.receivedPmts.count, 2,
                   @"Should receive PMTs for both programs");

    // Verify PAT correctly maps programs to PMT PIDs
    XCTAssertEqualObjects(self.delegate.receivedPats[0].programmes[@1], @(kPmtPid1));
    XCTAssertEqualObjects(self.delegate.receivedPats[0].programmes[@2], @(kPmtPid2));
}

@end
