//
//  TSDvbSdtTests.m
//  TSMuxDemuxTests
//
//  Tests for DVB Service Description Table (SDT) parsing.
//

#import <XCTest/XCTest.h>
#import "../TSTestUtils.h"
@import TSMuxDemux;

@interface TSDemuxer (PsiTableBuilderTesting)
- (void)tableBuilder:(TSPsiTableBuilder *)builder
        didBuildTable:(TSProgramSpecificInformationTable *)table;
@end

#pragma mark - Test Delegate

@interface TSDvbSdtTestDelegate : NSObject <TSDemuxerDelegate>
@property (nonatomic, strong) NSMutableArray *receivedPats;
@property (nonatomic, strong) NSMutableArray<TSDvbServiceDescriptionTable *> *receivedSdts;
@property (nonatomic, strong) NSMutableArray *receivedPreviousSdts;
@property (nonatomic) NSUInteger nilSdtCallbackCount;
@end

@implementation TSDvbSdtTestDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _receivedPats = [NSMutableArray array];
        _receivedSdts = [NSMutableArray array];
        _receivedPreviousSdts = [NSMutableArray array];
    }
    return self;
}

- (void)demuxer:(TSDemuxer *)demuxer didReceivePat:(TSProgramAssociationTable *)pat previousPat:(TSProgramAssociationTable *)previousPat {
    [self.receivedPats addObject:(id)(pat ?: [NSNull null])];
}
- (void)demuxer:(TSDemuxer *)demuxer didReceivePmt:(TSProgramMapTable *)pmt previousPmt:(TSProgramMapTable *)previousPmt {}
- (void)demuxer:(TSDemuxer *)demuxer didReceiveAccessUnit:(TSAccessUnit *)accessUnit {}

- (void)demuxer:(TSDemuxer *)demuxer didReceiveSdt:(TSDvbServiceDescriptionTable *)sdt previousSdt:(TSDvbServiceDescriptionTable *)previousSdt {
    if (!sdt) {
        self.nilSdtCallbackCount++;
        return;
    }
    [self.receivedSdts addObject:sdt];
    [self.receivedPreviousSdts addObject:(id)(previousSdt ?: [NSNull null])];
}

@end

#pragma mark - Tests

@interface TSDvbSdtTests : XCTestCase
@property (nonatomic, strong) TSDvbSdtTestDelegate *delegate;
@property (nonatomic, strong) TSDemuxer *demuxer;
@end

@implementation TSDvbSdtTests

- (void)setUp {
    [super setUp];
    self.delegate = [[TSDvbSdtTestDelegate alloc] init];
    // Must use DVB mode for SDT parsing
    self.demuxer = [[TSDemuxer alloc] initWithDelegate:self.delegate mode:TSDemuxerModeDVB];
}

#pragma mark - Basic SDT Tests

- (void)test_sdtReceived_triggersCallback {
    NSData *sdt = [TSTestUtils createSdtDataWithTransportStreamId:1
                                                originalNetworkId:0x1234
                                                        serviceId:100
                                                    versionNumber:0
                                                continuityCounter:0];
    [self.demuxer demux:sdt dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedSdts.count, 1, @"Should receive SDT callback");
}

- (void)test_sdtParsing_transportStreamId {
    NSData *sdt = [TSTestUtils createSdtDataWithTransportStreamId:0x5678
                                                originalNetworkId:0x1234
                                                        serviceId:100
                                                    versionNumber:0
                                                continuityCounter:0];
    [self.demuxer demux:sdt dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedSdts.count, 1);
    XCTAssertEqual(self.delegate.receivedSdts[0].transportStreamId, 0x5678);
}

- (void)test_sdtParsing_originalNetworkId {
    NSData *sdt = [TSTestUtils createSdtDataWithTransportStreamId:1
                                                originalNetworkId:0xABCD
                                                        serviceId:100
                                                    versionNumber:0
                                                continuityCounter:0];
    [self.demuxer demux:sdt dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedSdts.count, 1);
    XCTAssertEqual(self.delegate.receivedSdts[0].originalNetworkId, 0xABCD);
}

- (void)test_sdtParsing_serviceEntry {
    NSData *sdt = [TSTestUtils createSdtDataWithTransportStreamId:1
                                                originalNetworkId:0x1234
                                                        serviceId:500
                                                    versionNumber:0
                                                continuityCounter:0];
    [self.demuxer demux:sdt dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedSdts.count, 1);
    NSArray<TSDvbServiceDescriptionEntry *> *entries = self.delegate.receivedSdts[0].entries;
    XCTAssertEqual(entries.count, 1);
    XCTAssertEqual(entries[0].serviceId, 500);
}

#pragma mark - SDT Update Tests

- (void)test_sdtUpdate_triggersCallback {
    // Send initial SDT
    [self.demuxer demux:[TSTestUtils createSdtDataWithTransportStreamId:1
                                                      originalNetworkId:0x1234
                                                              serviceId:100
                                                          versionNumber:0
                                                      continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedSdts.count, 1);

    // Send updated SDT (different version)
    [self.demuxer demux:[TSTestUtils createSdtDataWithTransportStreamId:1
                                                      originalNetworkId:0x1234
                                                              serviceId:100
                                                          versionNumber:1
                                                      continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedSdts.count, 2, @"SDT version change should trigger callback");
}

- (void)test_sdtUpdate_previousSdtProvided {
    // Send initial SDT
    [self.demuxer demux:[TSTestUtils createSdtDataWithTransportStreamId:1
                                                      originalNetworkId:0x1234
                                                              serviceId:100
                                                          versionNumber:0
                                                      continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // First SDT has no previous
    XCTAssertEqual(self.delegate.receivedPreviousSdts[0], [NSNull null]);

    // Send updated SDT
    [self.demuxer demux:[TSTestUtils createSdtDataWithTransportStreamId:1
                                                      originalNetworkId:0x1234
                                                              serviceId:200
                                                          versionNumber:1
                                                      continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    // Second SDT should have previous
    XCTAssertNotEqual(self.delegate.receivedPreviousSdts[1], [NSNull null]);
    TSDvbServiceDescriptionTable *prevSdt = self.delegate.receivedPreviousSdts[1];
    XCTAssertEqual(prevSdt.entries[0].serviceId, 100);
}

- (void)test_identicalSdt_noCallback {
    // Send initial SDT
    [self.demuxer demux:[TSTestUtils createSdtDataWithTransportStreamId:1
                                                      originalNetworkId:0x1234
                                                              serviceId:100
                                                          versionNumber:0
                                                      continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedSdts.count, 1);

    // Send identical SDT again
    [self.demuxer demux:[TSTestUtils createSdtDataWithTransportStreamId:1
                                                      originalNetworkId:0x1234
                                                              serviceId:100
                                                          versionNumber:0
                                                      continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedSdts.count, 1, @"Identical SDT should not trigger callback");
}

#pragma mark - Parse Failure Regression Tests

- (void)test_nilPsiTable_doesNotClearPat {
    [self.demuxer demux:[TSTestUtils createPatDataWithPmtPid:0x100]
             dataArrivalHostTimeNanos:0];
    TSProgramAssociationTable *validPat = self.demuxer.pat;
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:nil pid:0x11];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    [self.demuxer tableBuilder:builder didBuildTable:nil];
#pragma clang diagnostic pop

    XCTAssertEqual(self.demuxer.pat, validPat);
    XCTAssertEqual(self.delegate.receivedPats.count, 1,
                   @"A failed SI parse must not emit a second PAT callback");
}

- (void)test_malformedSdt_doesNotClearValidSdt {
    NSData *validSdtData = [TSTestUtils createSdtDataWithTransportStreamId:1
                                                         originalNetworkId:0x1234
                                                                 serviceId:100
                                                             versionNumber:0
                                                         continuityCounter:0];
    [self.demuxer demux:validSdtData dataArrivalHostTimeNanos:0];
    TSDvbServiceDescriptionTable *validSdt = self.demuxer.dvb.sdt;

    TSProgramSpecificInformationTable *malformed = [[TSProgramSpecificInformationTable alloc]
                                                     initWithTableId:TABLE_ID_DVB_SDT_ACTUAL_TS
                                                     sectionSyntaxIndicator:1
                                                     reservedBit1:0
                                                     reservedBits2:3
                                                     sectionLength:PSI_CRC_LEN
                                                     sectionDataExcludingCrc:nil
                                                     crc:0];
    TSPsiTableBuilder *builder = [[TSPsiTableBuilder alloc] initWithDelegate:nil pid:0x11];
    [self.demuxer tableBuilder:builder didBuildTable:malformed];

    XCTAssertEqual(self.demuxer.dvb.sdt, validSdt);
    XCTAssertEqual(self.delegate.receivedSdts.count, 1,
                   @"A malformed SDT must not replace valid state or emit a callback");
    XCTAssertEqual(self.delegate.nilSdtCallbackCount, 0);
}

#pragma mark - Mode Tests

- (void)test_sdtIgnored_inAtscMode {
    // Create demuxer in ATSC mode
    TSDvbSdtTestDelegate *atscDelegate = [[TSDvbSdtTestDelegate alloc] init];
    TSDemuxer *atscDemuxer = [[TSDemuxer alloc] initWithDelegate:atscDelegate mode:TSDemuxerModeATSC];

    NSData *sdt = [TSTestUtils createSdtDataWithTransportStreamId:1
                                                originalNetworkId:0x1234
                                                        serviceId:100
                                                    versionNumber:0
                                                continuityCounter:0];
    [atscDemuxer demux:sdt dataArrivalHostTimeNanos:0];

    XCTAssertEqual(atscDelegate.receivedSdts.count, 0, @"SDT should be ignored in ATSC mode");
}

@end
