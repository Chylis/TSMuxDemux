//
//  TSDemuxerTests.m
//  TSMuxDemuxTests
//
//  Tests for TSDemuxer public API: packet size detection, pmtForPid, statistics.
//

#import <XCTest/XCTest.h>
#import "../TSTestUtils.h"
@import TSMuxDemux;

static const uint16_t kPmtPid1 = 0x100;
static const uint16_t kPmtPid2 = 0x200;
static const uint16_t kVideoPid1 = 0x101;
static const uint16_t kAudioPid1 = 0x102;
static const uint16_t kVideoPid2 = 0x201;
static const uint16_t kAudioPid2 = 0x202;

@interface TSDemuxerTests : XCTestCase
@end

@implementation TSDemuxerTests

#pragma mark - Packet Size Detection Tests

- (void)test_detectPacketSize_188 {
    // 2 * 188 = 376 (divisible by 188 only, not by 204)
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];
    NSData *chunk = [TSTestUtils createNullPackets:2 packetSize:TS_PACKET_SIZE_188];
    [demuxer demux:chunk dataArrivalHostTimeNanos:0];
    XCTAssertEqual(demuxer.packetSize, (NSUInteger)TS_PACKET_SIZE_188);
}

- (void)test_detectPacketSize_204 {
    // 2 * 204 = 408 (divisible by 204 only, not by 188)
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];
    NSData *chunk = [TSTestUtils createNullPackets:2 packetSize:TS_PACKET_SIZE_204];
    [demuxer demux:chunk dataArrivalHostTimeNanos:0];
    XCTAssertEqual(demuxer.packetSize, (NSUInteger)TS_PACKET_SIZE_204);
}

- (void)test_detectPacketSize_ambiguous_defaults188 {
    // 9588 bytes is divisible by both 188 (51 packets) and 204 (47 packets)
    // LCM(188, 204) = 9588
    // Should default to 188-byte packets
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];
    NSData *chunk = [TSTestUtils createNullPackets:51 packetSize:TS_PACKET_SIZE_188];
    [demuxer demux:chunk dataArrivalHostTimeNanos:0];
    XCTAssertEqual(demuxer.packetSize, (NSUInteger)TS_PACKET_SIZE_188);
}

- (void)test_detectPacketSize_singlePacket188 {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];
    NSData *chunk = [TSTestUtils createNullPackets:1 packetSize:TS_PACKET_SIZE_188];
    [demuxer demux:chunk dataArrivalHostTimeNanos:0];
    XCTAssertEqual(demuxer.packetSize, (NSUInteger)TS_PACKET_SIZE_188);
}

- (void)test_detectPacketSize_singlePacket204 {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];
    NSData *chunk = [TSTestUtils createNullPackets:1 packetSize:TS_PACKET_SIZE_204];
    [demuxer demux:chunk dataArrivalHostTimeNanos:0];
    XCTAssertEqual(demuxer.packetSize, (NSUInteger)TS_PACKET_SIZE_204);
}

- (void)test_detectPacketSize_persistsAfterFirstCall {
    // Once detected, packet size should persist for subsequent calls
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // First call with 204-byte data
    NSData *chunk204 = [TSTestUtils createNullPackets:1 packetSize:TS_PACKET_SIZE_204];
    [demuxer demux:chunk204 dataArrivalHostTimeNanos:0];
    XCTAssertEqual(demuxer.packetSize, (NSUInteger)TS_PACKET_SIZE_204);

    // Second call with different data should NOT change the detected size
    NSData *chunk2 = [TSTestUtils createNullPackets:2 packetSize:TS_PACKET_SIZE_204];
    [demuxer demux:chunk2 dataArrivalHostTimeNanos:0];
    XCTAssertEqual(demuxer.packetSize, (NSUInteger)TS_PACKET_SIZE_204);
}

#pragma mark - pmtForPid Tests

- (void)test_pmtForPid_returnsNilBeforePmtReceived {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // No PAT/PMT received yet
    TSProgramMapTable *pmt = [demuxer pmtForPid:kVideoPid1];
    XCTAssertNil(pmt, @"Should return nil when no PMT has been received");
}

- (void)test_pmtForPid_returnsNilForUnknownPid {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Setup PAT
    [demuxer demux:[TSTestUtils createPatDataWithPmtPid:kPmtPid1] dataArrivalHostTimeNanos:0];

    // Setup PMT with video and audio
    TSElementaryStream *video = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];
    TSElementaryStream *audio = [[TSElementaryStream alloc] initWithPid:kAudioPid1
                                                             streamType:kRawStreamTypeADTSAAC
                                                            descriptors:nil];
    [demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                  pcrPid:kVideoPid1
                                                 streams:@[video, audio]
                                           versionNumber:0
                                       continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Query for a PID that doesn't exist
    TSProgramMapTable *pmt = [demuxer pmtForPid:0x999];
    XCTAssertNil(pmt, @"Should return nil for unknown PID");
}

- (void)test_pmtForPid_findsPmtForVideoPid {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Setup PAT and PMT
    [demuxer demux:[TSTestUtils createPatDataWithPmtPid:kPmtPid1] dataArrivalHostTimeNanos:0];

    TSElementaryStream *video = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];
    TSElementaryStream *audio = [[TSElementaryStream alloc] initWithPid:kAudioPid1
                                                             streamType:kRawStreamTypeADTSAAC
                                                            descriptors:nil];
    [demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                  pcrPid:kVideoPid1
                                                 streams:@[video, audio]
                                           versionNumber:0
                                       continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Query for video PID
    TSProgramMapTable *pmt = [demuxer pmtForPid:kVideoPid1];
    XCTAssertNotNil(pmt, @"Should find PMT containing video PID");
    XCTAssertNotNil([pmt elementaryStreamWithPid:kVideoPid1], @"PMT should contain the video stream");
}

- (void)test_pmtForPid_findsPmtForAudioPid {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Setup PAT and PMT
    [demuxer demux:[TSTestUtils createPatDataWithPmtPid:kPmtPid1] dataArrivalHostTimeNanos:0];

    TSElementaryStream *video = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];
    TSElementaryStream *audio = [[TSElementaryStream alloc] initWithPid:kAudioPid1
                                                             streamType:kRawStreamTypeADTSAAC
                                                            descriptors:nil];
    [demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                  pcrPid:kVideoPid1
                                                 streams:@[video, audio]
                                           versionNumber:0
                                       continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Query for audio PID
    TSProgramMapTable *pmt = [demuxer pmtForPid:kAudioPid1];
    XCTAssertNotNil(pmt, @"Should find PMT containing audio PID");
    XCTAssertNotNil([pmt elementaryStreamWithPid:kAudioPid1], @"PMT should contain the audio stream");
}

- (void)test_pmtForPid_multiProgram_findsCorrectPmt {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Setup PAT with 2 programs
    NSDictionary *programmes = @{@1: @(kPmtPid1), @2: @(kPmtPid2)};
    [demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes
                                              versionNumber:0
                                          continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Setup PMT for program 1 (programNumber must match PAT entry)
    TSElementaryStream *video1 = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    TSElementaryStream *audio1 = [[TSElementaryStream alloc] initWithPid:kAudioPid1
                                                              streamType:kRawStreamTypeADTSAAC
                                                             descriptors:nil];
    [demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                          programNumber:1
                                                  pcrPid:kVideoPid1
                                                 streams:@[video1, audio1]
                                           versionNumber:0
                                       continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Setup PMT for program 2 (programNumber must match PAT entry)
    TSElementaryStream *video2 = [[TSElementaryStream alloc] initWithPid:kVideoPid2
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    TSElementaryStream *audio2 = [[TSElementaryStream alloc] initWithPid:kAudioPid2
                                                              streamType:kRawStreamTypeADTSAAC
                                                             descriptors:nil];
    [demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid2
                                          programNumber:2
                                                  pcrPid:kVideoPid2
                                                 streams:@[video2, audio2]
                                           versionNumber:0
                                       continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Query for video PID from program 1
    TSProgramMapTable *pmt1 = [demuxer pmtForPid:kVideoPid1];
    XCTAssertNotNil(pmt1, @"Should find PMT for program 1 video");
    XCTAssertNotNil([pmt1 elementaryStreamWithPid:kVideoPid1]);
    XCTAssertNil([pmt1 elementaryStreamWithPid:kVideoPid2], @"Program 1 PMT should not contain program 2 streams");

    // Query for video PID from program 2
    TSProgramMapTable *pmt2 = [demuxer pmtForPid:kVideoPid2];
    XCTAssertNotNil(pmt2, @"Should find PMT for program 2 video");
    XCTAssertNotNil([pmt2 elementaryStreamWithPid:kVideoPid2]);
    XCTAssertNil([pmt2 elementaryStreamWithPid:kVideoPid1], @"Program 2 PMT should not contain program 1 streams");

    // Query for audio PID from program 2
    TSProgramMapTable *pmt2Audio = [demuxer pmtForPid:kAudioPid2];
    XCTAssertNotNil(pmt2Audio, @"Should find PMT for program 2 audio");
    XCTAssertEqual(pmt2Audio, pmt2, @"Same PMT should be returned for streams in same program");
}

- (void)test_pmtForPid_afterPmtUpdate_findsNewStreams {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Setup PAT
    [demuxer demux:[TSTestUtils createPatDataWithPmtPid:kPmtPid1] dataArrivalHostTimeNanos:0];

    // Initial PMT with video only
    TSElementaryStream *video = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];
    [demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                  pcrPid:kVideoPid1
                                                 streams:@[video]
                                           versionNumber:0
                                       continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Audio PID should not be found yet
    XCTAssertNil([demuxer pmtForPid:kAudioPid1], @"Audio PID should not exist before PMT update");

    // Update PMT to add audio
    TSElementaryStream *audio = [[TSElementaryStream alloc] initWithPid:kAudioPid1
                                                             streamType:kRawStreamTypeADTSAAC
                                                            descriptors:nil];
    [demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                  pcrPid:kVideoPid1
                                                 streams:@[video, audio]
                                           versionNumber:1
                                       continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    // Now audio PID should be found
    TSProgramMapTable *pmt = [demuxer pmtForPid:kAudioPid1];
    XCTAssertNotNil(pmt, @"Audio PID should be found after PMT update");
    XCTAssertNotNil([pmt elementaryStreamWithPid:kAudioPid1]);
}

- (void)test_pmtForPid_doesNotFindPmtPid {
    // pmtForPid searches elementary streams, not the PMT PID itself
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Setup PAT and PMT
    [demuxer demux:[TSTestUtils createPatDataWithPmtPid:kPmtPid1] dataArrivalHostTimeNanos:0];

    TSElementaryStream *video = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];
    [demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                  pcrPid:kVideoPid1
                                                 streams:@[video]
                                           versionNumber:0
                                       continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Querying for PMT PID should return nil (it's not an elementary stream)
    TSProgramMapTable *pmt = [demuxer pmtForPid:kPmtPid1];
    XCTAssertNil(pmt, @"PMT PID is not an elementary stream, should return nil");
}

@end
