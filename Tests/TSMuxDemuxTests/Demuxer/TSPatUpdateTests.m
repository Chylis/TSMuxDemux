//
//  TSPatUpdateTests.m
//  TSMuxDemuxTests
//
//  Tests for dynamic PAT updates - version changes, program addition/removal.
//

#import <XCTest/XCTest.h>
#import "../TSTestUtils.h"
@import TSMuxDemux;

static const uint16_t kPmtPid1 = 0x100;
static const uint16_t kPmtPid2 = 0x200;
static const uint16_t kPmtPid3 = 0x300;
static const uint16_t kVideoPid1 = 0x101;
static const uint16_t kVideoPid2 = 0x201;

#pragma mark - Test Delegate

@interface TSPatUpdateTestDelegate : NSObject <TSDemuxerDelegate>
@property (nonatomic, strong) NSMutableArray<TSProgramAssociationTable *> *receivedPats;
@property (nonatomic, strong) NSMutableArray *receivedPreviousPats;  // TSProgramAssociationTable or NSNull
@property (nonatomic, strong) NSMutableArray<TSProgramMapTable *> *receivedPmts;
@property (nonatomic, strong) NSMutableArray<TSAccessUnit *> *receivedAccessUnits;
@end

@implementation TSPatUpdateTestDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _receivedPats = [NSMutableArray array];
        _receivedPreviousPats = [NSMutableArray array];
        _receivedPmts = [NSMutableArray array];
        _receivedAccessUnits = [NSMutableArray array];
    }
    return self;
}

- (void)demuxer:(TSDemuxer *)demuxer didReceivePat:(TSProgramAssociationTable *)pat previousPat:(TSProgramAssociationTable *)previousPat {
    [self.receivedPats addObject:pat];
    [self.receivedPreviousPats addObject:(id)(previousPat ?: [NSNull null])];
}

- (void)demuxer:(TSDemuxer *)demuxer didReceivePmt:(TSProgramMapTable *)pmt previousPmt:(TSProgramMapTable *)previousPmt {
    [self.receivedPmts addObject:pmt];
}

- (void)demuxer:(TSDemuxer *)demuxer didReceiveAccessUnit:(TSAccessUnit *)accessUnit {
    [self.receivedAccessUnits addObject:accessUnit];
}

@end

#pragma mark - Tests

@interface TSPatUpdateTests : XCTestCase
@property (nonatomic, strong) TSPatUpdateTestDelegate *delegate;
@property (nonatomic, strong) TSDemuxer *demuxer;
@end

@implementation TSPatUpdateTests

- (void)setUp {
    [super setUp];
    self.delegate = [[TSPatUpdateTestDelegate alloc] init];
    self.demuxer = [[TSDemuxer alloc] initWithDelegate:self.delegate mode:TSDemuxerModeDVB];
}

#pragma mark - First PAT Tests

- (void)test_firstPat_previousPatIsNil {
    NSDictionary *programmes = @{@1: @(kPmtPid1)};
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes
                                                   versionNumber:0
                                               continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats.count, 1);
    XCTAssertEqual(self.delegate.receivedPreviousPats[0], [NSNull null],
                   @"First PAT should have nil previousPat");
}

#pragma mark - Version Change Tests

- (void)test_patUpdate_sameContent_noCallback {
    // Note: PAT equality is based on programme content, not version number.
    // A version change alone does not trigger a callback if programmes are unchanged.
    NSDictionary *programmes = @{@1: @(kPmtPid1)};

    // Initial PAT v0
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes
                                                   versionNumber:0
                                               continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats.count, 1);

    // Same programmes with new version - should NOT trigger callback
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes
                                                   versionNumber:1
                                               continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats.count, 1,
                   @"Same programme content should not trigger callback even with version change");
}

- (void)test_patUpdate_identicalPat_noCallback {
    NSDictionary *programmes = @{@1: @(kPmtPid1)};

    // Initial PAT
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes
                                                   versionNumber:0
                                               continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats.count, 1);

    // Identical PAT (same version, same programs)
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes
                                                   versionNumber:0
                                               continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats.count, 1,
                   @"Identical PAT should not trigger delegate callback");
}

#pragma mark - Program Addition Tests

- (void)test_patUpdate_addProgram {
    // Initial PAT with 1 program
    NSDictionary *programmes1 = @{@1: @(kPmtPid1)};
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes1
                                                   versionNumber:0
                                               continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats.count, 1);
    XCTAssertEqual(self.delegate.receivedPats[0].programmes.count, 1);

    // Updated PAT with 2 programs
    NSDictionary *programmes2 = @{@1: @(kPmtPid1), @2: @(kPmtPid2)};
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes2
                                                   versionNumber:1
                                               continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats.count, 2);
    XCTAssertEqual(self.delegate.receivedPats[1].programmes.count, 2);

    // Verify previous PAT had 1 program
    TSProgramAssociationTable *prevPat = self.delegate.receivedPreviousPats[1];
    XCTAssertEqual(prevPat.programmes.count, 1);
}

- (void)test_patUpdate_addedProgramReceivesPmt {
    // Initial PAT with program 1
    NSDictionary *programmes1 = @{@1: @(kPmtPid1)};
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes1
                                                   versionNumber:0
                                               continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Send PMT for program 1
    TSElementaryStream *video1 = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                      pcrPid:kVideoPid1
                                                     streams:@[video1]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPmts.count, 1);

    // Add program 2 to PAT
    NSDictionary *programmes2 = @{@1: @(kPmtPid1), @2: @(kPmtPid2)};
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes2
                                                   versionNumber:1
                                               continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    // Send PMT for program 2
    TSElementaryStream *video2 = [[TSElementaryStream alloc] initWithPid:kVideoPid2
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid2
                                                      pcrPid:kVideoPid2
                                                     streams:@[video2]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPmts.count, 2,
                   @"Should receive PMT for newly added program");
}

#pragma mark - Program Removal Tests

- (void)test_patUpdate_removeProgram {
    // Initial PAT with 2 programs
    NSDictionary *programmes2 = @{@1: @(kPmtPid1), @2: @(kPmtPid2)};
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes2
                                                   versionNumber:0
                                               continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats[0].programmes.count, 2);

    // Updated PAT with only program 1 (program 2 removed)
    NSDictionary *programmes1 = @{@1: @(kPmtPid1)};
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes1
                                                   versionNumber:1
                                               continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats.count, 2);
    XCTAssertEqual(self.delegate.receivedPats[1].programmes.count, 1);
    XCTAssertNil(self.delegate.receivedPats[1].programmes[@2],
                 @"Program 2 should be removed from PAT");
    XCTAssertNotNil(self.delegate.receivedPats[1].programmes[@1],
                    @"Program 1 should still be in PAT");
}

#pragma mark - Channel Switch Simulation

- (void)test_patUpdate_channelSwitch_replacesProgram {
    // Simulate tuning to channel 1
    NSDictionary *channel1 = @{@1: @(kPmtPid1)};
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:channel1
                                                   versionNumber:0
                                               continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    TSElementaryStream *video1 = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                      pcrPid:kVideoPid1
                                                     streams:@[video1]
                                               versionNumber:0
                                           continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Simulate tuning to channel 2 (different PMT PID)
    NSDictionary *channel2 = @{@2: @(kPmtPid2)};
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:channel2
                                                   versionNumber:1
                                               continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats.count, 2);
    XCTAssertNil(self.delegate.receivedPats[1].programmes[@1],
                 @"Old program should be removed after channel switch");
    XCTAssertNotNil(self.delegate.receivedPats[1].programmes[@2],
                    @"New program should be present after channel switch");
}

#pragma mark - Multiple Programs Tests

- (void)test_patUpdate_multiplePrograms_allTracked {
    // PAT with 3 programs
    NSDictionary *programmes = @{@1: @(kPmtPid1), @2: @(kPmtPid2), @3: @(kPmtPid3)};
    [self.demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes
                                                   versionNumber:0
                                               continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedPats.count, 1);
    XCTAssertEqual(self.delegate.receivedPats[0].programmes.count, 3);
    XCTAssertEqualObjects(self.delegate.receivedPats[0].programmes[@1], @(kPmtPid1));
    XCTAssertEqualObjects(self.delegate.receivedPats[0].programmes[@2], @(kPmtPid2));
    XCTAssertEqualObjects(self.delegate.receivedPats[0].programmes[@3], @(kPmtPid3));
}

@end
