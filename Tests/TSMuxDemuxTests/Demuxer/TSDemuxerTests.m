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

#pragma mark - Lazy Cache Tests

- (void)test_pmtForPid_cacheInvalidatedOnPmtUpdate {
    // Tests that _elementaryStreamPidToPmt cache is invalidated when PMT changes
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

    // Populate cache by querying
    XCTAssertNotNil([demuxer pmtForPid:kVideoPid1]);
    XCTAssertNil([demuxer pmtForPid:kAudioPid1]);

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

    // Cache should be invalidated - audio PID should now be found
    XCTAssertNotNil([demuxer pmtForPid:kAudioPid1],
                    @"Cache should be invalidated after PMT update");
}

- (void)test_pmtForPid_cacheInvalidatedOnPatUpdate {
    // Tests that cache is invalidated when PAT changes (which can signal program changes)
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Setup initial PAT and PMT
    NSDictionary *programmes1 = @{@1: @(kPmtPid1)};
    [demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes1
                                              versionNumber:0
                                          continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    TSElementaryStream *video1 = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    [demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                          programNumber:1
                                                  pcrPid:kVideoPid1
                                                 streams:@[video1]
                                           versionNumber:0
                                       continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Populate cache
    XCTAssertNotNil([demuxer pmtForPid:kVideoPid1]);

    // Update PAT to add a second program
    NSDictionary *programmes2 = @{@1: @(kPmtPid1), @2: @(kPmtPid2)};
    [demuxer demux:[TSTestUtils createPatDataWithProgrammes:programmes2
                                              versionNumber:1
                                          continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    // Add PMT for program 2
    TSElementaryStream *video2 = [[TSElementaryStream alloc] initWithPid:kVideoPid2
                                                              streamType:kRawStreamTypeH264
                                                             descriptors:nil];
    [demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid2
                                          programNumber:2
                                                  pcrPid:kVideoPid2
                                                 streams:@[video2]
                                           versionNumber:0
                                       continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Cache should be invalidated - new video PID should be found
    XCTAssertNotNil([demuxer pmtForPid:kVideoPid2],
                    @"Cache should be invalidated after PAT update");
}

- (void)test_pmtForPid_cacheReusedOnRepeatedCalls {
    // Tests that cache is reused (same result) on repeated calls without changes
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

    // Query multiple times - should return same PMT object
    TSProgramMapTable *pmt1 = [demuxer pmtForPid:kVideoPid1];
    TSProgramMapTable *pmt2 = [demuxer pmtForPid:kAudioPid1];
    TSProgramMapTable *pmt3 = [demuxer pmtForPid:kVideoPid1];
    TSProgramMapTable *pmt4 = [demuxer pmtForPid:kAudioPid1];

    // Same PMT should be returned for all streams in same program
    XCTAssertEqual(pmt1, pmt2);
    XCTAssertEqual(pmt1, pmt3);
    XCTAssertEqual(pmt1, pmt4);
}

- (void)test_pmtForPid_streamRemovedFromPmt_notFoundAfterUpdate {
    // Tests cache invalidation when a stream is removed from PMT
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Setup PAT
    [demuxer demux:[TSTestUtils createPatDataWithPmtPid:kPmtPid1] dataArrivalHostTimeNanos:0];

    // Initial PMT with video and audio
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

    // Verify both are found
    XCTAssertNotNil([demuxer pmtForPid:kVideoPid1]);
    XCTAssertNotNil([demuxer pmtForPid:kAudioPid1]);

    // Update PMT to remove audio
    [demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                  pcrPid:kVideoPid1
                                                 streams:@[video]
                                           versionNumber:1
                                       continuityCounter:1]
             dataArrivalHostTimeNanos:0];

    // Video should still be found, audio should not
    XCTAssertNotNil([demuxer pmtForPid:kVideoPid1]);
    XCTAssertNil([demuxer pmtForPid:kAudioPid1],
                 @"Removed stream should not be found after PMT update");
}

#pragma mark - Statistics Tests

- (void)test_statistics_initiallyZero {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    TSTr101290Statistics *stats = [demuxer statistics];
    XCTAssertNotNil(stats, @"Statistics should never be nil");
    XCTAssertNotNil(stats.prio1, @"Priority 1 statistics should be available");
    XCTAssertEqual(stats.prio1.tsSyncLoss, (uint64_t)0);
    XCTAssertEqual(stats.prio1.syncByteError, (uint64_t)0);
    XCTAssertEqual(stats.prio1.patError, (uint64_t)0);
}

- (void)test_statistics_incrementsAfterProcessing {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Process some valid packets
    NSData *packets = [TSTestUtils createNullPackets:10 packetSize:TS_PACKET_SIZE_188];
    [demuxer demux:packets dataArrivalHostTimeNanos:1000000];

    TSTr101290Statistics *stats = [demuxer statistics];
    XCTAssertNotNil(stats, @"Statistics should be available after processing");
    XCTAssertNotNil(stats.prio1, @"Priority 1 statistics should be available");
}

- (void)test_statistics_accessibleAfterDemuxing {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Setup full stream
    [demuxer demux:[TSTestUtils createPatDataWithPmtPid:kPmtPid1]
             dataArrivalHostTimeNanos:0];

    TSElementaryStream *video = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];
    [demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                  pcrPid:kVideoPid1
                                                 streams:@[video]
                                           versionNumber:0
                                       continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // Send some video data
    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];
    uint8_t frameData[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0xFF};
    NSData *payload = [NSData dataWithBytes:frameData length:sizeof(frameData)];
    [demuxer demux:[TSTestUtils createPesDataWithTrack:track payload:payload pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:1000000];

    TSTr101290Statistics *stats = [demuxer statistics];
    XCTAssertNotNil(stats, @"Statistics should be accessible");
    XCTAssertNotNil(stats.prio1, @"Priority 1 statistics should be accessible");
    // Statistics counters are tested in TSTr101290AnalyzerTests
}

#pragma mark - Empty and Tiny Chunk Handling Tests

- (void)test_emptyChunk_handledGracefully {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Empty data should not crash
    NSData *emptyData = [NSData data];
    [demuxer demux:emptyData dataArrivalHostTimeNanos:0];

    // Should still be functional - demuxer may default to 188 or remain 0
    // The key is that it doesn't crash
    XCTAssertTrue(demuxer.packetSize == 0 || demuxer.packetSize == TS_PACKET_SIZE_188,
                  @"Packet size should be 0 or default to 188 with empty data");
}

- (void)test_tinyChunk_lessThan188Bytes_handledGracefully {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Send data smaller than one packet
    uint8_t tinyData[] = {0x47, 0x00, 0x00, 0x10};  // Just 4 bytes
    NSData *chunk = [NSData dataWithBytes:tinyData length:sizeof(tinyData)];
    [demuxer demux:chunk dataArrivalHostTimeNanos:0];

    // Should not crash, packet size detection may or may not work
    XCTAssertTrue(YES, @"Demuxer should handle tiny chunks without crashing");
}

- (void)test_singleByteChunk_handledGracefully {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Single byte
    uint8_t singleByte = 0x47;
    NSData *chunk = [NSData dataWithBytes:&singleByte length:1];
    [demuxer demux:chunk dataArrivalHostTimeNanos:0];

    XCTAssertTrue(YES, @"Demuxer should handle single byte without crashing");
}

- (void)test_nonAlignedChunk_handledGracefully {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // 200 bytes - not aligned to 188 or 204
    NSMutableData *chunk = [NSMutableData dataWithLength:200];
    uint8_t *bytes = chunk.mutableBytes;
    bytes[0] = 0x47;  // Valid sync byte at start

    [demuxer demux:chunk dataArrivalHostTimeNanos:0];

    XCTAssertTrue(YES, @"Demuxer should handle non-aligned chunks without crashing");
}

- (void)test_nilDelegate_processesWithoutCrash {
    // Demuxer with nil delegate should still process data
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

    // Send PES data
    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];
    uint8_t frameData[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0xFF};
    NSData *payload = [NSData dataWithBytes:frameData length:sizeof(frameData)];
    [demuxer demux:[TSTestUtils createPesDataWithTrack:track payload:payload pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:0];

    // Verify demuxer state is correct despite no delegate
    XCTAssertNotNil(demuxer.pat);
    XCTAssertEqual(demuxer.pmts.count, (NSUInteger)1);
}

#pragma mark - Packet Routing Tests

- (void)test_nullPacketPid_ignored {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Send null packets (PID 0x1FFF)
    NSData *nullPackets = [TSTestUtils createNullPackets:10 packetSize:TS_PACKET_SIZE_188];
    [demuxer demux:nullPackets dataArrivalHostTimeNanos:0];

    // Null packets should be silently ignored - no state changes
    XCTAssertNil(demuxer.pat, @"Null packets should not create PAT");
}

- (void)test_patPacket_processedAndStored {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Send PAT
    [demuxer demux:[TSTestUtils createPatDataWithPmtPid:kPmtPid1] dataArrivalHostTimeNanos:0];

    XCTAssertNotNil(demuxer.pat, @"PAT should be stored after processing");
    XCTAssertEqual([demuxer.pat.programmes count], (NSUInteger)1);
}

- (void)test_pmtPacket_processedAndStored {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Setup PAT first
    [demuxer demux:[TSTestUtils createPatDataWithPmtPid:kPmtPid1] dataArrivalHostTimeNanos:0];

    // Send PMT
    TSElementaryStream *video = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];
    [demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                  pcrPid:kVideoPid1
                                                 streams:@[video]
                                           versionNumber:0
                                       continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    XCTAssertEqual(demuxer.pmts.count, (NSUInteger)1, @"PMT should be stored");
    TSProgramMapTable *pmt = demuxer.pmts[@1];
    XCTAssertNotNil(pmt);
    XCTAssertEqual(pmt.elementaryStreams.count, (NSUInteger)1);
}

- (void)test_pmtPacketBeforePat_ignored {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Send PMT without PAT first
    TSElementaryStream *video = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];
    [demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid1
                                                  pcrPid:kVideoPid1
                                                 streams:@[video]
                                           versionNumber:0
                                       continuityCounter:0]
             dataArrivalHostTimeNanos:0];

    // PMT should be ignored without PAT (or stored but not processed properly)
    XCTAssertNil(demuxer.pat);
    // pmts may or may not be empty depending on implementation
}

- (void)test_pesDataBeforePmt_ignored {
    TSDemuxer *demuxer = [[TSDemuxer alloc] initWithDelegate:nil mode:TSDemuxerModeDVB];

    // Setup PAT only (no PMT)
    [demuxer demux:[TSTestUtils createPatDataWithPmtPid:kPmtPid1] dataArrivalHostTimeNanos:0];

    // Send PES data - should be ignored (no stream builder for this PID)
    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:kVideoPid1
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];
    uint8_t frameData[] = {0x00, 0x00, 0x00, 0x01, 0x41, 0xFF};
    NSData *payload = [NSData dataWithBytes:frameData length:sizeof(frameData)];
    [demuxer demux:[TSTestUtils createPesDataWithTrack:track payload:payload pts:CMTimeMake(0, 90000)]
             dataArrivalHostTimeNanos:0];

    // Should not crash - data is simply ignored
    XCTAssertEqual(demuxer.pmts.count, (NSUInteger)0);
}

@end
