//
//  TSMuxerCBRTests.m
//  TSMuxDemuxTests
//
//  Tests for CBR muxing, queue overflow, discontinuity signaling, and settings validation.
//

#import <XCTest/XCTest.h>
@import TSMuxDemux;

#pragma mark - Mock Delegate

@interface TSMuxerTestDelegate : NSObject <TSMuxerDelegate>
@property(nonatomic, readonly, nonnull) NSMutableArray<NSData*> *packets;
@end

@implementation TSMuxerTestDelegate

-(instancetype)init
{
    self = [super init];
    if (self) {
        _packets = [NSMutableArray array];
    }
    return self;
}

-(void)muxer:(TSMuxer *)muxer didMuxTSPacketData:(NSData *)tsPacketData
{
    [self.packets addObject:tsPacketData];
}

@end

#pragma mark - Helper

static TSAccessUnit *makeVideoAU(uint16_t pid, double ptsSeconds, NSUInteger payloadSize) {
    NSMutableData *data = [NSMutableData dataWithLength:payloadSize];
    memset(data.mutableBytes, 0xAA, payloadSize);
    return [[TSAccessUnit alloc] initWithPid:pid
                                         pts:CMTimeMakeWithSeconds(ptsSeconds, 90000)
                                         dts:kCMTimeInvalid
                             isDiscontinuous:NO
                          isRandomAccessPoint:NO
                                  streamType:kRawStreamTypeH264
                                  descriptors:nil
                              compressedData:data];
}

static TSAccessUnit *makeAudioAU(uint16_t pid, double ptsSeconds, NSUInteger payloadSize) {
    NSMutableData *data = [NSMutableData dataWithLength:payloadSize];
    memset(data.mutableBytes, 0xBB, payloadSize);
    return [[TSAccessUnit alloc] initWithPid:pid
                                         pts:CMTimeMakeWithSeconds(ptsSeconds, 90000)
                                         dts:kCMTimeInvalid
                             isDiscontinuous:NO
                          isRandomAccessPoint:NO
                                  streamType:kRawStreamTypeADTSAAC
                                  descriptors:nil
                              compressedData:data];
}

/// Returns the number of TS packets expected for a given bitrate and duration.
static NSUInteger expectedPacketCount(NSUInteger bitrateKbps, double durationSeconds) {
    double bytesPerSecond = (double)bitrateKbps * 1e3 / 8.0;
    return (NSUInteger)(bytesPerSecond * durationSeconds / (double)TS_PACKET_SIZE_188);
}

/// Counts null packets (PID 0x1FFF) in an array of TS packet data.
static NSUInteger countNullPackets(NSArray<NSData*> *packets) {
    NSUInteger count = 0;
    for (NSData *packet in packets) {
        const uint8_t *bytes = packet.bytes;
        uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
        if (pid == 0x1FFF) count++;
    }
    return count;
}

#pragma mark - Tests

@interface TSMuxerCBRTests : XCTestCase
@end

@implementation TSMuxerCBRTests

#pragma mark - Null Packet Format

- (void)test_nullPacketData_format {
    NSData *nullPacket = [TSPacket nullPacketData];

    XCTAssertEqual(nullPacket.length, (NSUInteger)TS_PACKET_SIZE_188);

    const uint8_t *bytes = nullPacket.bytes;
    XCTAssertEqual(bytes[0], TS_PACKET_HEADER_SYNC_BYTE, @"Sync byte should be 0x47");

    uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
    XCTAssertEqual(pid, (uint16_t)0x1FFF, @"Null packet PID should be 0x1FFF");

    uint8_t adaptationControl = (bytes[3] & 0x30) >> 4;
    XCTAssertEqual(adaptationControl, (uint8_t)1, @"Null packet should be payload-only (01)");

    // Payload should be all 0xFF
    for (NSUInteger i = 4; i < TS_PACKET_SIZE_188; i++) {
        XCTAssertEqual(bytes[i], (uint8_t)0xFF, @"Null packet payload byte %lu should be 0xFF", (unsigned long)i);
    }
}

- (void)test_nullPacketData_isSingleton {
    NSData *a = [TSPacket nullPacketData];
    NSData *b = [TSPacket nullPacketData];
    XCTAssertEqual(a, b, @"nullPacketData should return the same instance");
}

#pragma mark - Settings Validation

- (void)test_init_rejectsPsiIntervalZero {
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    settings.psiIntervalMs = 0;
    XCTAssertThrows(([[TSMuxer alloc] initWithSettings:settings delegate:nil]),
                    @"psiIntervalMs == 0 should throw");
}

- (void)test_init_rejectsBitrateOver60000Kbps {
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    settings.targetBitrateKbps = 60001;
    XCTAssertThrows(([[TSMuxer alloc] initWithSettings:settings delegate:nil]),
                    @"targetBitrateKbps > 60000 should throw");
}

- (void)test_init_accepts60000Kbps {
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    settings.targetBitrateKbps = 60000;
    XCTAssertNoThrow(([[TSMuxer alloc] initWithSettings:settings delegate:nil]),
                     @"targetBitrateKbps == 60000 should be accepted");
}

- (void)test_settings_defaults {
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    XCTAssertEqual(settings.psiIntervalMs, (NSUInteger)250);
    XCTAssertEqual(settings.targetBitrateKbps, (NSUInteger)0);
    XCTAssertEqual(settings.maxNumQueuedAccessUnits, (NSUInteger)300);
}

- (void)test_settings_copyPreservesAllFields {
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    settings.targetBitrateKbps = 5000;
    settings.maxNumQueuedAccessUnits = 100;
    settings.psiIntervalMs = 500;

    TSMuxerSettings *copy = [settings copy];
    XCTAssertEqual(copy.targetBitrateKbps, (NSUInteger)5000);
    XCTAssertEqual(copy.maxNumQueuedAccessUnits, (NSUInteger)100);
    XCTAssertEqual(copy.psiIntervalMs, (NSUInteger)500);
}

#pragma mark - VBR Baseline (sanity)

- (void)test_vbr_emitsPackets {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings delegate:delegate];

    [muxer enqueueAccessUnit:makeVideoAU(256, 0.0, 100)];
    [muxer tick];

    XCTAssertGreaterThan(delegate.packets.count, (NSUInteger)0, @"VBR muxer should emit packets");
    for (NSData *packet in delegate.packets) {
        XCTAssertEqual(packet.length, (NSUInteger)TS_PACKET_SIZE_188);
    }
}

- (void)test_vbr_enqueueDoesNotEmit {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings delegate:delegate];

    [muxer enqueueAccessUnit:makeVideoAU(256, 0.0, 100)];

    XCTAssertEqual(delegate.packets.count, (NSUInteger)0,
                   @"enqueueAccessUnit should not emit packets without tick");
}

#pragma mark - CBR Packet Emission

- (void)test_cbr_emitsPacketsAfterDelay {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    settings.targetBitrateKbps = 1000; // 1 Mbps
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings delegate:delegate];

    __block uint64_t mockTimeNanos = 1000000000ULL; // 1s
    muxer.nowNanosProvider = ^{ return mockTimeNanos; };

    // First tick — sets firstOutputTimeNanos, emits 0 packets (elapsed = 0)
    [muxer enqueueAccessUnit:makeVideoAU(256, 0.0, 100)];
    [muxer tick];
    NSUInteger countAfterFirst = delegate.packets.count;
    XCTAssertEqual(countAfterFirst, (NSUInteger)0, @"No packets on first CBR tick");

    // Advance 50ms
    mockTimeNanos += 50000000ULL;
    [muxer enqueueAccessUnit:makeVideoAU(256, 0.04, 100)];
    [muxer tick];

    XCTAssertGreaterThan(delegate.packets.count, countAfterFirst,
                         @"CBR muxer should emit packets after time passes");

    for (NSData *packet in delegate.packets) {
        XCTAssertEqual(packet.length, (NSUInteger)TS_PACKET_SIZE_188);
    }
}

- (void)test_cbr_containsNullPackets {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    settings.targetBitrateKbps = 10000; // 10 Mbps
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings delegate:delegate];

    __block uint64_t mockTimeNanos = 1000000000ULL;
    muxer.nowNanosProvider = ^{ return mockTimeNanos; };

    // Feed one small AU
    [muxer enqueueAccessUnit:makeVideoAU(256, 0.0, 10)];
    [muxer tick];

    // Advance 50ms
    mockTimeNanos += 50000000ULL;
    [muxer enqueueAccessUnit:makeVideoAU(256, 0.04, 10)];
    [muxer tick];

    NSUInteger nullCount = countNullPackets(delegate.packets);
    XCTAssertGreaterThan(nullCount, (NSUInteger)0,
                         @"CBR muxer should emit null packets to fill bitrate");
}

- (void)test_cbr_emitsPsiTables {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    settings.targetBitrateKbps = 5000;
    settings.psiIntervalMs = 50;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings delegate:delegate];

    __block uint64_t mockTimeNanos = 1000000000ULL;
    muxer.nowNanosProvider = ^{ return mockTimeNanos; };

    [muxer enqueueAccessUnit:makeVideoAU(256, 0.0, 100)];
    [muxer tick];

    // Advance 100ms (2x PSI interval)
    mockTimeNanos += 100000000ULL;
    [muxer enqueueAccessUnit:makeVideoAU(256, 0.1, 100)];
    [muxer tick];

    BOOL foundPat = NO;
    BOOL foundPmt = NO;
    for (NSData *packet in delegate.packets) {
        const uint8_t *bytes = packet.bytes;
        uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
        if (pid == 0) foundPat = YES;
        if (pid == 0x1000) foundPmt = YES;
    }
    XCTAssertTrue(foundPat, @"CBR output should contain PAT");
    XCTAssertTrue(foundPmt, @"CBR output should contain PMT");
}

#pragma mark - Queue Overflow

- (void)test_queueOverflow_dropsOldestAccessUnits {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    settings.targetBitrateKbps = 1; // Very low bitrate — almost nothing is drained
    settings.maxNumQueuedAccessUnits = 5;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings delegate:delegate];

    __block uint64_t mockTimeNanos = 1000000000ULL;
    muxer.nowNanosProvider = ^{ return mockTimeNanos; };

    // Feed 10 AUs rapidly. With 1 kbps, almost no packets are drained between calls.
    for (int i = 0; i < 10; i++) {
        [muxer enqueueAccessUnit:makeVideoAU(256, i * 0.04, 10)];
        [muxer tick];
    }

    // Advance a bit and verify muxer still functions
    mockTimeNanos += 10000000ULL;
    XCTAssertNoThrow([muxer enqueueAccessUnit:makeVideoAU(256, 0.5, 10)],
                     @"Muxer should still accept AUs after queue overflow");
}

#pragma mark - Discontinuity Flag

- (void)test_discontinuityFlag_setInAdaptationField {
    const uint16_t pid = 256;
    NSMutableData *payload = [NSMutableData dataWithLength:100];
    memset(payload.mutableBytes, 0xDD, 100);

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:pid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    NSMutableArray<NSData *> *packets = [NSMutableArray array];
    [TSPacket packetizePayload:payload
                         track:track
                     forcePusi:NO
                       pcrBase:0
                        pcrExt:0
             discontinuityFlag:YES
              randomAccessFlag:NO
                onTsPacketData:^(NSData * _Nonnull tsPacketData) {
        [packets addObject:tsPacketData];
    }];

    XCTAssertGreaterThan(packets.count, (NSUInteger)0);

    // First packet should have discontinuity flag in adaptation field
    NSData *firstPacket = packets[0];
    NSArray<TSPacket *> *parsed = [TSPacket packetsFromChunkedTsData:firstPacket
                                                         packetSize:TS_PACKET_SIZE_188];
    XCTAssertEqual(parsed.count, (NSUInteger)1);
    TSPacket *packet = parsed[0];
    XCTAssertNotNil(packet.adaptationField, @"First packet should have adaptation field when discontinuity is set");
    XCTAssertTrue(packet.adaptationField.discontinuityFlag, @"Discontinuity flag should be set on first packet");

    // Subsequent packets should NOT have discontinuity flag
    if (packets.count > 1) {
        NSData *secondPacket = packets[1];
        NSArray<TSPacket *> *parsed2 = [TSPacket packetsFromChunkedTsData:secondPacket
                                                             packetSize:TS_PACKET_SIZE_188];
        TSPacket *packet2 = parsed2[0];
        if (packet2.adaptationField) {
            XCTAssertFalse(packet2.adaptationField.discontinuityFlag,
                           @"Discontinuity flag should only be set on first packet");
        }
    }
}

- (void)test_discontinuityFlag_notSetWhenFalse {
    const uint16_t pid = 256;
    NSMutableData *payload = [NSMutableData dataWithLength:100];
    memset(payload.mutableBytes, 0xDD, 100);

    TSElementaryStream *track = [[TSElementaryStream alloc] initWithPid:pid
                                                             streamType:kRawStreamTypeH264
                                                            descriptors:nil];

    NSMutableArray<NSData *> *packets = [NSMutableArray array];
    [TSPacket packetizePayload:payload
                         track:track
                     forcePusi:NO
                       pcrBase:0
                        pcrExt:0
             discontinuityFlag:NO
              randomAccessFlag:NO
                onTsPacketData:^(NSData * _Nonnull tsPacketData) {
        [packets addObject:tsPacketData];
    }];

    XCTAssertGreaterThan(packets.count, (NSUInteger)0);

    for (NSData *packetData in packets) {
        NSArray<TSPacket *> *parsed = [TSPacket packetsFromChunkedTsData:packetData
                                                             packetSize:TS_PACKET_SIZE_188];
        TSPacket *packet = parsed[0];
        if (packet.adaptationField) {
            XCTAssertFalse(packet.adaptationField.discontinuityFlag,
                           @"Discontinuity flag should not be set");
        }
    }
}

#pragma mark - VBR Queue Overflow

- (void)test_vbr_queueOverflow_stillEmitsPackets {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    settings.maxNumQueuedAccessUnits = 3;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings delegate:delegate];

    for (int i = 0; i < 10; i++) {
        [muxer enqueueAccessUnit:makeVideoAU(256, i * 0.04, 50)];
    }
    [muxer tick];

    XCTAssertGreaterThan(delegate.packets.count, (NSUInteger)0,
                         @"VBR muxer should emit packets even with small queue limit");
}

#pragma mark - CBR Bitrate Accuracy

- (void)test_cbr_bitrateExact {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    settings.targetBitrateKbps = 5000; // 5 Mbps
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings delegate:delegate];

    __block uint64_t mockTimeNanos = 1000000000ULL;
    muxer.nowNanosProvider = ^{ return mockTimeNanos; };

    [muxer enqueueAccessUnit:makeVideoAU(256, 0.0, 100)];
    [muxer tick];
    XCTAssertEqual(delegate.packets.count, (NSUInteger)0, @"No packets on first CBR tick");

    // Advance exactly 100ms
    mockTimeNanos += 100000000ULL;
    [muxer enqueueAccessUnit:makeVideoAU(256, 0.1, 100)];
    [muxer tick];

    NSUInteger expected = expectedPacketCount(5000, 0.1);
    XCTAssertEqual(delegate.packets.count, expected,
                   @"Packet count should exactly match expected for 5 Mbps over 100ms (expected %lu, got %lu)",
                   (unsigned long)expected, (unsigned long)delegate.packets.count);
}

#pragma mark - Tick-only Emission

- (void)test_cbr_tickWithoutEnqueue_emitsNullPackets {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    settings.targetBitrateKbps = 5000;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings delegate:delegate];

    __block uint64_t mockTimeNanos = 1000000000ULL;
    muxer.nowNanosProvider = ^{ return mockTimeNanos; };

    // First tick — sets firstOutputTimeNanos
    [muxer tick];
    XCTAssertEqual(delegate.packets.count, (NSUInteger)0, @"No packets on first CBR tick");

    // Advance 100ms — tick without any enqueued AUs
    mockTimeNanos += 100000000ULL;
    [muxer tick];

    NSUInteger expected = expectedPacketCount(5000, 0.1);
    XCTAssertEqual(delegate.packets.count, expected,
                   @"tick without AUs should still emit packets to maintain CBR");

    NSUInteger nullCount = countNullPackets(delegate.packets);
    XCTAssertGreaterThan(nullCount, (NSUInteger)0,
                         @"tick without AUs should emit null packets");
}

#pragma mark - PCR During Null Stretches

- (void)test_cbr_pcrEmittedDuringNullStretches {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    settings.targetBitrateKbps = 5000;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings delegate:delegate];

    const uint16_t videoPid = 256;
    __block uint64_t mockTimeNanos = 1000000000ULL;
    muxer.nowNanosProvider = ^{ return mockTimeNanos; };

    // Enqueue one video AU to establish pcrPid and emit a first PCR
    [muxer enqueueAccessUnit:makeVideoAU(videoPid, 0.0, 100)];
    [muxer tick];

    // Advance 50ms to drain the AU and establish PCR baseline
    mockTimeNanos += 50000000ULL;
    [muxer tick];
    [delegate.packets removeAllObjects];

    // Advance another 100ms with NO enqueued AUs — should get PCR-only packets
    mockTimeNanos += 100000000ULL;
    [muxer tick];

    BOOL foundPcrOnVideoPid = NO;
    for (NSData *packet in delegate.packets) {
        const uint8_t *bytes = packet.bytes;
        uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
        if (pid != videoPid) continue;

        // Check adaptation field has PCR flag
        uint8_t adaptationControl = (bytes[3] & 0x30) >> 4;
        if (adaptationControl == 0x02 || adaptationControl == 0x03) {
            uint8_t adaptationFlags = bytes[5];
            BOOL pcrFlag = (adaptationFlags & 0x10) != 0;
            if (pcrFlag) {
                foundPcrOnVideoPid = YES;
                break;
            }
        }
    }
    XCTAssertTrue(foundPcrOnVideoPid,
                  @"PCR-only packets should be emitted on the video PID during null stretches");
}

@end
