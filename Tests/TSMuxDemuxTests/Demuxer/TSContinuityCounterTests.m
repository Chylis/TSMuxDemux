//
//  TSContinuityCounterTests.m
//  TSMuxDemuxTests
//
//  Tests for continuity counter error handling in demuxer.
//

#import <XCTest/XCTest.h>
#import "../TSTestUtils.h"
@import TSMuxDemux;

static const uint16_t kTestPmtPid = 0x100;
static const uint16_t kTestVideoPid = 0x101;

#pragma mark - Test Delegate

@interface TSContinuityCounterTestDelegate : NSObject <TSDemuxerDelegate>
@property (nonatomic, strong) NSMutableArray<TSAccessUnit *> *receivedAccessUnits;
@end

@implementation TSContinuityCounterTestDelegate

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

@interface TSContinuityCounterTests : XCTestCase
@property (nonatomic, strong) TSContinuityCounterTestDelegate *delegate;
@property (nonatomic, strong) TSDemuxer *demuxer;
@end

@implementation TSContinuityCounterTests

- (void)setUp {
    [super setUp];
    self.delegate = [[TSContinuityCounterTestDelegate alloc] init];
    self.demuxer = [[TSDemuxer alloc] initWithDelegate:self.delegate mode:TSDemuxerModeDVB];

    // Setup PAT and PMT
    [self.demuxer demux:[TSTestUtils createPatDataWithPmtPid:kTestPmtPid] dataArrivalHostTimeNanos:0];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kTestPmtPid
                                                      pcrPid:kTestVideoPid
                                          elementaryStreamPid:kTestVideoPid
                                                   streamType:kRawStreamTypeH264]
             dataArrivalHostTimeNanos:0];
}

#pragma mark - CC Gap Detection Tests

- (void)test_ccGap_discardsInProgressAccessUnit {
    // Create a track that we'll manually control CC for
    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    uint8_t payload1[] = {0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1E};
    NSData *videoPayload = [NSData dataWithBytes:payload1 length:sizeof(payload1)];

    // Feed first PES with CC=0 (valid start)
    track.continuityCounter = 0;
    NSData *pesData1 = [TSTestUtils createPesDataWithTrack:track
                                                   payload:videoPayload
                                                       pts:CMTimeMake(90000, 90000)];
    [self.demuxer demux:pesData1 dataArrivalHostTimeNanos:0];

    // Now simulate a CC gap by jumping CC (instead of natural increment)
    uint8_t currentCC = track.continuityCounter;
    track.continuityCounter = (currentCC + 5) & 0x0F;  // Skip 5 values

    // Feed second PES with gap - its first packet (with PUSI) will be discarded
    NSData *pesData2 = [TSTestUtils createPesDataWithTrack:track
                                                   payload:videoPayload
                                                       pts:CMTimeMake(93000, 90000)];
    [self.demuxer demux:pesData2 dataArrivalHostTimeNanos:0];

    // Feed third PES - continuous CC, should be collected
    NSData *pesData3 = [TSTestUtils createPesDataWithTrack:track
                                                   payload:videoPayload
                                                       pts:CMTimeMake(96000, 90000)];
    [self.demuxer demux:pesData3 dataArrivalHostTimeNanos:0];

    // Feed fourth PES to trigger delivery of third
    NSData *pesData4 = [TSTestUtils createPesDataWithTrack:track
                                                   payload:videoPayload
                                                       pts:CMTimeMake(99000, 90000)];
    [self.demuxer demux:pesData4 dataArrivalHostTimeNanos:0];

    // First AU: discarded due to CC gap (was in-progress when gap detected)
    // Second AU: its PUSI packet was discarded (the gap-causing packet)
    // Third AU: collected normally, delivered by fourth
    // Fourth AU: in-progress
    XCTAssertEqual(self.delegate.receivedAccessUnits.count, 1,
                   @"Should receive only the access unit that started after gap recovery");
}

- (void)test_ccGap_recoversWithNextValidPes {
    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    uint8_t payload[] = {0x00, 0x00, 0x00, 0x01, 0x09, 0x10};
    NSData *videoPayload = [NSData dataWithBytes:payload length:sizeof(payload)];

    // Feed first PES normally (CC=0)
    track.continuityCounter = 0;
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:0];

    // Create CC gap
    track.continuityCounter = (track.continuityCounter + 3) & 0x0F;

    // Feed PES after gap - its first packet (PUSI=1) will be discarded due to gap
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(3000, 90000)]
             dataArrivalHostTimeNanos:0];

    // Continue with valid CC sequence - this establishes recovery
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(6000, 90000)]
             dataArrivalHostTimeNanos:0];

    // Feed more PES to build up post-recovery access units
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(9000, 90000)]
             dataArrivalHostTimeNanos:0];

    // Trigger final delivery
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(12000, 90000)]
             dataArrivalHostTimeNanos:0];

    // After CC gap recovery:
    // - First AU (before gap) was in-progress, discarded
    // - Gap-causing packet discarded
    // - Subsequent PES packets recover and deliver access units
    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 2,
                                @"Should recover and deliver access units after CC gap");
}

- (void)test_continuousCC_deliversAllAccessUnits {
    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    uint8_t payload[] = {0x00, 0x00, 0x00, 0x01, 0x65, 0x88};
    NSData *videoPayload = [NSData dataWithBytes:payload length:sizeof(payload)];

    // Feed 4 PES packets with continuous CC (no gaps)
    for (int i = 0; i < 4; i++) {
        [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                        payload:videoPayload
                                                            pts:CMTimeMake(i * 3000, 90000)]
                 dataArrivalHostTimeNanos:0];
    }

    // Trigger delivery of last one
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(12000, 90000)]
             dataArrivalHostTimeNanos:0];

    // All 4 access units should be delivered (the 5th triggers delivery of 4th)
    XCTAssertEqual(self.delegate.receivedAccessUnits.count, 4,
                   @"Should deliver all access units with continuous CC");
}

#pragma mark - CC Wrap Tests

- (void)test_ccWrapAround_handledCorrectly {
    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    uint8_t payload[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0x9A};
    NSData *videoPayload = [NSData dataWithBytes:payload length:sizeof(payload)];

    // Start near CC wrap point (CC=14)
    track.continuityCounter = 14;

    // Feed packets that will wrap around 15->0
    for (int i = 0; i < 4; i++) {
        [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                        payload:videoPayload
                                                            pts:CMTimeMake(i * 3000, 90000)]
                 dataArrivalHostTimeNanos:0];
    }

    // Trigger final delivery
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(12000, 90000)]
             dataArrivalHostTimeNanos:0];

    // CC wrap (15->0) should be handled correctly, all AUs delivered
    XCTAssertEqual(self.delegate.receivedAccessUnits.count, 4,
                   @"Should handle CC wrap around correctly");
}

#pragma mark - Duplicate Packet Tests

- (void)test_duplicatePacket_isSkipped {
    // Per ITU-T H.222.0 §2.4.3.3: duplicate packets (same CC) are allowed for retransmission
    // The demuxer should skip them without reporting an error

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    uint8_t payload[] = {0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x00};
    NSData *videoPayload = [NSData dataWithBytes:payload length:sizeof(payload)];

    // Send first PES
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:0];

    // Simulate duplicate by resending with same CC
    // We need to manually create a duplicate packet with the same CC value
    uint8_t currentCC = track.continuityCounter;
    track.continuityCounter = (currentCC - 1) & 0x0F;  // Back up so next packet has same CC

    // This PES will have the same starting CC as the previous one's last packet
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(3000, 90000)]
             dataArrivalHostTimeNanos:0];

    // Continue normally
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(6000, 90000)]
             dataArrivalHostTimeNanos:0];

    // Trigger delivery
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(9000, 90000)]
             dataArrivalHostTimeNanos:0];

    // Duplicate packets should be skipped, not cause errors
    // We should still receive access units (exact count depends on duplicate handling)
    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 2,
                                @"Should continue processing after duplicate packets");
}

#pragma mark - Discontinuity Flag Tests

- (void)test_discontinuityFlag_allowsCCJump {
    // Per ITU-T H.222.0: discontinuity_indicator flag allows CC to be discontinuous
    // This is used after stream switching, splicing, or packet insertion

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    uint8_t payload[] = {0x00, 0x00, 0x00, 0x01, 0x09, 0x10, 0x00};
    NSData *videoPayload = [NSData dataWithBytes:payload length:sizeof(payload)];

    // Send first PES (CC will be 0,1,2...)
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:0];

    uint8_t lastCC = track.continuityCounter;

    // Send discontinuity packet (signals that CC can jump)
    NSData *discontinuityPacket = [TSTestUtils createPacketWithAdaptationFieldPid:kTestVideoPid
                                                                discontinuityFlag:YES
                                                                       hasPayload:YES
                                                                continuityCounter:10];  // Jump to CC=10
    [self.demuxer demux:discontinuityPacket dataArrivalHostTimeNanos:0];

    // Continue from CC=11 (should not be an error due to discontinuity flag)
    track.continuityCounter = 10;  // Set track to continue from 10
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(3000, 90000)]
             dataArrivalHostTimeNanos:0];

    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(6000, 90000)]
             dataArrivalHostTimeNanos:0];

    // Trigger delivery
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(9000, 90000)]
             dataArrivalHostTimeNanos:0];

    // Should receive access units before and after discontinuity
    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 2,
                                @"Should handle discontinuity flag and continue processing");
}

#pragma mark - Independent PID Tracking Tests

- (void)test_ccErrorOnOnePid_doesNotAffectOtherPid {
    // Each PID has independent CC tracking per ITU-T H.222.0

    // Setup second stream (audio) - use helper to create proper PMT
    static const uint16_t kTestAudioPid = 0x102;

    // Create PMT with both video and audio streams
    TSElementaryStream *videoEs = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                               streamType:kRawStreamTypeH264
                                                              descriptors:nil];
    TSElementaryStream *audioEs = [[TSElementaryStream alloc] initWithPid:kTestAudioPid
                                                               streamType:kRawStreamTypeADTSAAC
                                                              descriptors:nil];
    TSProgramMapTable *pmt = [[TSProgramMapTable alloc] initWithProgramNumber:1
                                                                versionNumber:1
                                                                       pcrPid:kTestVideoPid
                                                            elementaryStreams:[NSSet setWithObjects:videoEs, audioEs, nil]];
    NSData *pmtPayload = [pmt toTsPacketPayload];

    // Create and send updated PMT packet
    NSMutableData *pmtPacket = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *pmtBytes = pmtPacket.mutableBytes;
    pmtBytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    pmtBytes[1] = 0x40 | ((kTestPmtPid >> 8) & 0x1F);
    pmtBytes[2] = kTestPmtPid & 0xFF;
    pmtBytes[3] = 0x11;  // CC=1 (different from initial PMT)
    memcpy(pmtBytes + 4, pmtPayload.bytes, MIN(pmtPayload.length, TS_PACKET_SIZE_188 - 4));
    // Fill rest with stuffing
    for (NSUInteger i = 4 + MIN(pmtPayload.length, TS_PACKET_SIZE_188 - 4); i < TS_PACKET_SIZE_188; i++) {
        pmtBytes[i] = 0xFF;
    }
    [self.demuxer demux:pmtPacket dataArrivalHostTimeNanos:0];

    // Create separate track instances for sending PES
    TSElementaryStream *videoTrack = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                                  streamType:kRawStreamTypeH264
                                                                 descriptors:nil];
    TSElementaryStream *audioTrack = [[TSElementaryStream alloc] initWithPid:kTestAudioPid
                                                                  streamType:kRawStreamTypeADTSAAC
                                                                 descriptors:nil];

    uint8_t videoPayload[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0x9A};
    NSData *videoData = [NSData dataWithBytes:videoPayload length:sizeof(videoPayload)];

    uint8_t audioPayload[] = {0xFF, 0xF1, 0x50, 0x80, 0x02, 0x1F, 0xFC};
    NSData *audioData = [NSData dataWithBytes:audioPayload length:sizeof(audioPayload)];

    // Send video PES (CC 0,1)
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:videoTrack
                                                    payload:videoData
                                                        pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:0];

    // Send audio PES (CC 0,1)
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:audioTrack
                                                    payload:audioData
                                                        pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:0];

    // Introduce CC gap on video (jump from 1 to 8)
    videoTrack.continuityCounter = 7;

    // Send video with gap (should discard)
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:videoTrack
                                                    payload:videoData
                                                        pts:CMTimeMake(3000, 90000)]
             dataArrivalHostTimeNanos:0];

    // Send audio continuously (CC 2,3 - no gap)
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:audioTrack
                                                    payload:audioData
                                                        pts:CMTimeMake(3000, 90000)]
             dataArrivalHostTimeNanos:0];

    // Trigger delivery
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:audioTrack
                                                    payload:audioData
                                                        pts:CMTimeMake(6000, 90000)]
             dataArrivalHostTimeNanos:0];

    // Audio should be unaffected by video CC error
    NSUInteger audioCount = 0;
    for (TSAccessUnit *au in self.delegate.receivedAccessUnits) {
        if (au.pid == kTestAudioPid) {
            audioCount++;
        }
    }
    XCTAssertGreaterThanOrEqual(audioCount, 2,
                                @"Audio stream should be unaffected by video CC error");
}

#pragma mark - Multi-Packet PES Gap Tests

- (void)test_ccGapInMultiPacketPes_discardsPartialData {
    // When CC gap occurs in the middle of a multi-packet PES,
    // all collected data should be discarded

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    // Create large payload that spans multiple TS packets
    NSMutableData *largePayload = [NSMutableData dataWithCapacity:1024];
    uint8_t startCode[] = {0x00, 0x00, 0x00, 0x01, 0x65};
    [largePayload appendBytes:startCode length:sizeof(startCode)];
    for (int i = 0; i < 500; i++) {
        uint8_t byte = (uint8_t)(i & 0xFF);
        [largePayload appendBytes:&byte length:1];
    }

    // Send first large PES (multiple TS packets)
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:largePayload
                                                        pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:0];

    // Record CC after first PES
    uint8_t ccAfterFirst = track.continuityCounter;

    // Simulate packet loss in middle of next PES
    // First, create partial PES (PUSI packet only)
    track.continuityCounter = ccAfterFirst;
    NSData *secondPesStart = [TSTestUtils createPesDataWithTrack:track
                                                         payload:largePayload
                                                             pts:CMTimeMake(3000, 90000)];
    // Only send first packet of this PES
    NSData *firstPacketOnly = [secondPesStart subdataWithRange:NSMakeRange(0, TS_PACKET_SIZE_188)];
    [self.demuxer demux:firstPacketOnly dataArrivalHostTimeNanos:0];

    // Now introduce CC gap (simulate lost continuation packets)
    track.continuityCounter = (track.continuityCounter + 5) & 0x0F;

    // Send next PES with gap
    NSData *thirdPes = [TSTestUtils createPesDataWithTrack:track
                                                   payload:largePayload
                                                       pts:CMTimeMake(6000, 90000)];
    [self.demuxer demux:thirdPes dataArrivalHostTimeNanos:0];

    // Continue normally
    NSData *fourthPes = [TSTestUtils createPesDataWithTrack:track
                                                   payload:largePayload
                                                       pts:CMTimeMake(9000, 90000)];
    [self.demuxer demux:fourthPes dataArrivalHostTimeNanos:0];

    // Trigger delivery
    NSData *fifthPes = [TSTestUtils createPesDataWithTrack:track
                                                  payload:largePayload
                                                      pts:CMTimeMake(12000, 90000)];
    [self.demuxer demux:fifthPes dataArrivalHostTimeNanos:0];

    // Should have: first AU delivered, second discarded (incomplete + gap),
    // third's PUSI discarded (gap-causing), fourth delivered, fifth in-progress
    // Exact count depends on implementation, but partial data should be discarded
    for (TSAccessUnit *au in self.delegate.receivedAccessUnits) {
        XCTAssertGreaterThanOrEqual(au.compressedData.length, largePayload.length,
                                    @"Delivered access units should not contain partial data");
    }
}

#pragma mark - First Packet Tests

- (void)test_firstPacketAccepted_regardlessOfCC {
    // The first packet on a PID should always be accepted (no prior CC to compare)

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kTestVideoPid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    uint8_t payload[] = {0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1E};
    NSData *videoPayload = [NSData dataWithBytes:payload length:sizeof(payload)];

    // Start with arbitrary CC value (not 0)
    track.continuityCounter = 7;

    // First packet should be accepted regardless of CC value
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:0];

    // Continue normally
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(3000, 90000)]
             dataArrivalHostTimeNanos:0];

    // Trigger delivery
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:track
                                                    payload:videoPayload
                                                        pts:CMTimeMake(6000, 90000)]
             dataArrivalHostTimeNanos:0];

    XCTAssertGreaterThanOrEqual(self.delegate.receivedAccessUnits.count, 2,
                                @"First packet should be accepted regardless of CC");
}

@end
