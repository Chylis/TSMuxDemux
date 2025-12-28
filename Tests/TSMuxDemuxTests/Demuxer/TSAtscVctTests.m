//
//  TSAtscVctTests.m
//  TSMuxDemuxTests
//
//  Tests for ATSC Virtual Channel Table (VCT) parsing.
//

#import <XCTest/XCTest.h>
#import "../TSTestUtils.h"
@import TSMuxDemux;

#pragma mark - Test Delegate

@interface TSAtscVctTestDelegate : NSObject <TSDemuxerDelegate>
@property (nonatomic, strong) NSMutableArray<TSAtscVirtualChannelTable *> *receivedVcts;
@property (nonatomic, strong) NSMutableArray *receivedPreviousVcts;
@end

@implementation TSAtscVctTestDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _receivedVcts = [NSMutableArray array];
        _receivedPreviousVcts = [NSMutableArray array];
    }
    return self;
}

- (void)demuxer:(TSDemuxer *)demuxer didReceivePat:(TSProgramAssociationTable *)pat previousPat:(TSProgramAssociationTable *)previousPat {}
- (void)demuxer:(TSDemuxer *)demuxer didReceivePmt:(TSProgramMapTable *)pmt previousPmt:(TSProgramMapTable *)previousPmt {}
- (void)demuxer:(TSDemuxer *)demuxer didReceiveAccessUnit:(TSAccessUnit *)accessUnit {}

- (void)demuxer:(TSDemuxer *)demuxer didReceiveVct:(TSAtscVirtualChannelTable *)vct previousVct:(TSAtscVirtualChannelTable *)previousVct {
    [self.receivedVcts addObject:vct];
    [self.receivedPreviousVcts addObject:(id)(previousVct ?: [NSNull null])];
}

@end

#pragma mark - Tests

@interface TSAtscVctTests : XCTestCase
@property (nonatomic, strong) TSAtscVctTestDelegate *delegate;
@property (nonatomic, strong) TSDemuxer *demuxer;
@end

@implementation TSAtscVctTests

- (void)setUp {
    [super setUp];
    self.delegate = [[TSAtscVctTestDelegate alloc] init];
    // Must use ATSC mode for VCT parsing
    self.demuxer = [[TSDemuxer alloc] initWithDelegate:self.delegate mode:TSDemuxerModeATSC];
}

#pragma mark - Basic VCT Tests

- (void)test_vctReceived_triggersCallback {
    NSData *vct = [TSTestUtils createTvctDataWithTransportStreamId:1
                                                       channelName:@"KABC"
                                                      majorChannel:7
                                                      minorChannel:1
                                                     programNumber:1
                                                     versionNumber:0
                                                 continuityCounter:0];
    [self.demuxer demux:vct dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedVcts.count, 1, @"Should receive VCT callback");
}

- (void)test_vctParsing_channelName {
    NSData *vct = [TSTestUtils createTvctDataWithTransportStreamId:1
                                                       channelName:@"WNBC"
                                                      majorChannel:4
                                                      minorChannel:1
                                                     programNumber:1
                                                     versionNumber:0
                                                 continuityCounter:0];
    [self.demuxer demux:vct dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedVcts.count, 1);
    XCTAssertEqual(self.delegate.receivedVcts[0].channels.count, 1);
    XCTAssertEqualObjects(self.delegate.receivedVcts[0].channels[0].shortName, @"WNBC");
}

- (void)test_vctParsing_channelNumbers {
    NSData *vct = [TSTestUtils createTvctDataWithTransportStreamId:1
                                                       channelName:@"CBS"
                                                      majorChannel:2
                                                      minorChannel:3
                                                     programNumber:1
                                                     versionNumber:0
                                                 continuityCounter:0];
    [self.demuxer demux:vct dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedVcts.count, 1);
    TSAtscVirtualChannel *channel = self.delegate.receivedVcts[0].channels[0];
    XCTAssertEqual(channel.majorChannelNumber, 2);
    XCTAssertEqual(channel.minorChannelNumber, 3);
    XCTAssertEqualObjects([channel channelNumberString], @"2.3");
}

- (void)test_vctParsing_programNumber {
    NSData *vct = [TSTestUtils createTvctDataWithTransportStreamId:1
                                                       channelName:@"FOX"
                                                      majorChannel:5
                                                      minorChannel:1
                                                     programNumber:42
                                                     versionNumber:0
                                                 continuityCounter:0];
    [self.demuxer demux:vct dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedVcts.count, 1);
    XCTAssertEqual(self.delegate.receivedVcts[0].channels[0].programNumber, 42);
}

- (void)test_vctParsing_transportStreamId {
    NSData *vct = [TSTestUtils createTvctDataWithTransportStreamId:0x1234
                                                       channelName:@"ABC"
                                                      majorChannel:7
                                                      minorChannel:1
                                                     programNumber:1
                                                     versionNumber:0
                                                 continuityCounter:0];
    [self.demuxer demux:vct dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedVcts.count, 1);
    XCTAssertEqual(self.delegate.receivedVcts[0].transportStreamId, 0x1234);
}

- (void)test_vctParsing_isTerrestrial {
    NSData *vct = [TSTestUtils createTvctDataWithTransportStreamId:1
                                                       channelName:@"NBC"
                                                      majorChannel:4
                                                      minorChannel:1
                                                     programNumber:1
                                                     versionNumber:0
                                                 continuityCounter:0];
    [self.demuxer demux:vct dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedVcts.count, 1);
    XCTAssertTrue(self.delegate.receivedVcts[0].isTerrestrial, @"Should be TVCT (terrestrial)");
}

#pragma mark - Channel Lookup Tests

- (void)test_channelForProgramNumber_found {
    NSData *vct = [TSTestUtils createTvctDataWithTransportStreamId:1
                                                       channelName:@"PBS"
                                                      majorChannel:13
                                                      minorChannel:1
                                                     programNumber:99
                                                     versionNumber:0
                                                 continuityCounter:0];
    [self.demuxer demux:vct dataArrivalHostTimeNanos:0];

    TSAtscVirtualChannel *channel = [self.delegate.receivedVcts[0] channelForProgramNumber:99];
    XCTAssertNotNil(channel);
    XCTAssertEqualObjects(channel.shortName, @"PBS");
}

- (void)test_channelForProgramNumber_notFound {
    NSData *vct = [TSTestUtils createTvctDataWithTransportStreamId:1
                                                       channelName:@"CW"
                                                      majorChannel:11
                                                      minorChannel:1
                                                     programNumber:50
                                                     versionNumber:0
                                                 continuityCounter:0];
    [self.demuxer demux:vct dataArrivalHostTimeNanos:0];

    TSAtscVirtualChannel *channel = [self.delegate.receivedVcts[0] channelForProgramNumber:999];
    XCTAssertNil(channel, @"Should return nil for non-existent program number");
}

#pragma mark - VCT Update Tests

- (void)test_vctUpdate_triggersCallback {
    // Send initial VCT
    [self.demuxer demux:[TSTestUtils createTvctDataWithTransportStreamId:1
                                                             channelName:@"ABC"
                                                            majorChannel:7
                                                            minorChannel:1
                                                           programNumber:1
                                                           versionNumber:0
                                                       continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedVcts.count, 1);

    // Send updated VCT (different version)
    [self.demuxer demux:[TSTestUtils createTvctDataWithTransportStreamId:1
                                                             channelName:@"ABC"
                                                            majorChannel:7
                                                            minorChannel:1
                                                           programNumber:1
                                                           versionNumber:1
                                                       continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedVcts.count, 2, @"VCT version change should trigger callback");
}

- (void)test_vctUpdate_previousVctProvided {
    // Send initial VCT
    [self.demuxer demux:[TSTestUtils createTvctDataWithTransportStreamId:1
                                                             channelName:@"NBC"
                                                            majorChannel:4
                                                            minorChannel:1
                                                           programNumber:1
                                                           versionNumber:0
                                                       continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // First VCT has no previous
    XCTAssertEqual(self.delegate.receivedPreviousVcts[0], [NSNull null]);

    // Send updated VCT
    [self.demuxer demux:[TSTestUtils createTvctDataWithTransportStreamId:1
                                                             channelName:@"NBC-HD"
                                                            majorChannel:4
                                                            minorChannel:1
                                                           programNumber:1
                                                           versionNumber:1
                                                       continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    // Second VCT should have previous
    XCTAssertNotEqual(self.delegate.receivedPreviousVcts[1], [NSNull null]);
    TSAtscVirtualChannelTable *prevVct = self.delegate.receivedPreviousVcts[1];
    XCTAssertEqualObjects(prevVct.channels[0].shortName, @"NBC");
}

- (void)test_identicalVct_noCallback {
    // Send initial VCT
    [self.demuxer demux:[TSTestUtils createTvctDataWithTransportStreamId:1
                                                             channelName:@"FOX"
                                                            majorChannel:5
                                                            minorChannel:1
                                                           programNumber:1
                                                           versionNumber:0
                                                       continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedVcts.count, 1);

    // Send identical VCT again
    [self.demuxer demux:[TSTestUtils createTvctDataWithTransportStreamId:1
                                                             channelName:@"FOX"
                                                            majorChannel:5
                                                            minorChannel:1
                                                           programNumber:1
                                                           versionNumber:0
                                                       continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(self.delegate.receivedVcts.count, 1, @"Identical VCT should not trigger callback");
}

#pragma mark - Mode Tests

- (void)test_vctIgnored_inDvbMode {
    // Create demuxer in DVB mode
    TSAtscVctTestDelegate *dvbDelegate = [[TSAtscVctTestDelegate alloc] init];
    TSDemuxer *dvbDemuxer = [[TSDemuxer alloc] initWithDelegate:dvbDelegate mode:TSDemuxerModeDVB];

    NSData *vct = [TSTestUtils createTvctDataWithTransportStreamId:1
                                                       channelName:@"ABC"
                                                      majorChannel:7
                                                      minorChannel:1
                                                     programNumber:1
                                                     versionNumber:0
                                                 continuityCounter:0];
    [dvbDemuxer demux:vct dataArrivalHostTimeNanos:0];

    XCTAssertEqual(dvbDelegate.receivedVcts.count, 0, @"VCT should be ignored in DVB mode");
}

@end
