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

#pragma mark - Settings Helper

static TSMuxerSettings *makeSettings(void) {
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    settings.pmtPid = 4096;
    settings.pcrPid = 256;
    settings.videoPid = 256;
    settings.audioPid = 257;
    settings.psiIntervalMs = 250;
    settings.pcrIntervalMs = 30;
    return settings;
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

- (void)test_init_rejectsInvalidPcrPid {
    TSMuxerSettings *settings = makeSettings();
    settings.pcrPid = 0; // Invalid (reserved PID)
    XCTAssertThrows(([[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return (uint64_t)0; } delegate:nil]),
                    @"pcrPid == 0 should throw");
}

- (void)test_init_rejectsPsiIntervalZero {
    TSMuxerSettings *settings = makeSettings();
    settings.psiIntervalMs = 0;
    XCTAssertThrows(([[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return (uint64_t)0; } delegate:nil]),
                    @"psiIntervalMs == 0 should throw");
}

- (void)test_init_rejectsBitrateOver60000Kbps {
    TSMuxerSettings *settings = makeSettings();
    settings.targetBitrateKbps = 60001;
    XCTAssertThrows(([[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return (uint64_t)0; } delegate:nil]),
                    @"targetBitrateKbps > 60000 should throw");
}

- (void)test_init_accepts60000Kbps {
    TSMuxerSettings *settings = makeSettings();
    settings.targetBitrateKbps = 60000;
    XCTAssertNoThrow(([[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return (uint64_t)0; } delegate:nil]),
                     @"targetBitrateKbps == 60000 should be accepted");
}

- (void)test_init_rejectsPcrIntervalZero {
    TSMuxerSettings *settings = makeSettings();
    settings.pcrIntervalMs = 0;
    XCTAssertThrows(([[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return (uint64_t)0; } delegate:nil]),
                    @"pcrIntervalMs == 0 should throw");
}

- (void)test_init_rejectsInvalidVideoPid {
    TSMuxerSettings *settings = makeSettings();
    settings.videoPid = 0;
    settings.pcrPid = 257; // Can't match videoPid=0 which is invalid
    XCTAssertThrows(([[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return (uint64_t)0; } delegate:nil]),
                    @"videoPid == 0 should throw");
}

- (void)test_init_rejectsInvalidAudioPid {
    TSMuxerSettings *settings = makeSettings();
    settings.audioPid = 0;
    XCTAssertThrows(([[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return (uint64_t)0; } delegate:nil]),
                    @"audioPid == 0 should throw");
}

- (void)test_init_rejectsDuplicateAudioVideoPid {
    TSMuxerSettings *settings = makeSettings();
    settings.audioPid = 256;
    settings.videoPid = 256;
    XCTAssertThrows(([[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return (uint64_t)0; } delegate:nil]),
                    @"audioPid == videoPid should throw");
}

- (void)test_settings_copyPreservesAllFields {
    TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
    settings.pmtPid = 4096;
    settings.pcrPid = 256;
    settings.videoPid = 256;
    settings.audioPid = 257;
    settings.psiIntervalMs = 500;
    settings.pcrIntervalMs = 25;
    settings.targetBitrateKbps = 5000;
    settings.maxNumQueuedAccessUnits = 100;

    TSMuxerSettings *copy = [settings copy];
    XCTAssertEqual(copy.pmtPid, (uint16_t)4096);
    XCTAssertEqual(copy.pcrPid, (uint16_t)256);
    XCTAssertEqual(copy.videoPid, (uint16_t)256);
    XCTAssertEqual(copy.audioPid, (uint16_t)257);
    XCTAssertEqual(copy.psiIntervalMs, (NSUInteger)500);
    XCTAssertEqual(copy.pcrIntervalMs, (NSUInteger)25);
    XCTAssertEqual(copy.targetBitrateKbps, (NSUInteger)5000);
    XCTAssertEqual(copy.maxNumQueuedAccessUnits, (NSUInteger)100);
}

#pragma mark - VBR Baseline (sanity)

- (void)test_vbr_emitsPackets {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    [muxer enqueueAccessUnit:makeVideoAU(256, 1.0, 100)];
    [muxer tick];

    XCTAssertGreaterThan(delegate.packets.count, (NSUInteger)0, @"VBR muxer should emit packets");
    for (NSData *packet in delegate.packets) {
        XCTAssertEqual(packet.length, (NSUInteger)TS_PACKET_SIZE_188);
    }
}

- (void)test_vbr_enqueueDoesNotEmit {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    [muxer enqueueAccessUnit:makeVideoAU(256, 1.0, 100)];

    XCTAssertEqual(delegate.packets.count, (NSUInteger)0,
                   @"enqueueAccessUnit should not emit packets without tick");
}

#pragma mark - CBR Packet Emission

- (void)test_cbr_emitsPacketsAfterDelay {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    settings.targetBitrateKbps = 1000; // 1 Mbps
    __block uint64_t mockTimeNanos = 1000000000ULL; // 1s
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    // First tick — sets firstOutputTimeNanos, emits 0 packets (elapsed = 0)
    [muxer enqueueAccessUnit:makeVideoAU(256, 1.0, 100)];
    [muxer tick];
    NSUInteger countAfterFirst = delegate.packets.count;
    XCTAssertEqual(countAfterFirst, (NSUInteger)0, @"No packets on first CBR tick");

    // Advance 50ms
    mockTimeNanos += 50000000ULL;
    [muxer enqueueAccessUnit:makeVideoAU(256, 1.04, 100)];
    [muxer tick];

    XCTAssertGreaterThan(delegate.packets.count, countAfterFirst,
                         @"CBR muxer should emit packets after time passes");

    for (NSData *packet in delegate.packets) {
        XCTAssertEqual(packet.length, (NSUInteger)TS_PACKET_SIZE_188);
    }
}

- (void)test_cbr_containsNullPackets {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    settings.targetBitrateKbps = 10000; // 10 Mbps
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    // Feed one small AU
    [muxer enqueueAccessUnit:makeVideoAU(256, 1.0, 10)];
    [muxer tick];

    // Advance 50ms
    mockTimeNanos += 50000000ULL;
    [muxer enqueueAccessUnit:makeVideoAU(256, 1.04, 10)];
    [muxer tick];

    NSUInteger nullCount = countNullPackets(delegate.packets);
    XCTAssertGreaterThan(nullCount, (NSUInteger)0,
                         @"CBR muxer should emit null packets to fill bitrate");
}

- (void)test_cbr_emitsPsiTables {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    settings.targetBitrateKbps = 5000;
    settings.psiIntervalMs = 50;
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    [muxer enqueueAccessUnit:makeVideoAU(256, 1.0, 100)];
    [muxer tick];

    // Advance 100ms (2x PSI interval)
    mockTimeNanos += 100000000ULL;
    [muxer enqueueAccessUnit:makeVideoAU(256, 1.1, 100)];
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
    TSMuxerSettings *settings = makeSettings();
    settings.targetBitrateKbps = 1; // Very low bitrate — almost nothing is drained
    settings.maxNumQueuedAccessUnits = 5;
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    // Feed 10 AUs rapidly. With 1 kbps, almost no packets are drained between calls.
    for (int i = 0; i < 10; i++) {
        [muxer enqueueAccessUnit:makeVideoAU(256, 1.0 + i * 0.04, 10)];
        [muxer tick];
    }

    // Advance a bit and verify muxer still functions (both enqueue and emit)
    mockTimeNanos += 10000000ULL;
    XCTAssertNoThrow([muxer enqueueAccessUnit:makeVideoAU(256, 1.5, 10)],
                     @"Muxer should still accept AUs after queue overflow");
    XCTAssertNoThrow([muxer tick],
                     @"Muxer should still emit packets after queue overflow");
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

                       pcrBase:kNoPcr
                        pcrExt:0
             discontinuityFlag:YES
              randomAccessFlag:NO
                onTsPacketData:^(NSData * _Nonnull tsPacketData, uint16_t pid, uint8_t cc) {
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

                       pcrBase:kNoPcr
                        pcrExt:0
             discontinuityFlag:NO
              randomAccessFlag:NO
                onTsPacketData:^(NSData * _Nonnull tsPacketData, uint16_t pid, uint8_t cc) {
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
    TSMuxerSettings *settings = makeSettings();
    settings.maxNumQueuedAccessUnits = 3;
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    for (int i = 0; i < 10; i++) {
        [muxer enqueueAccessUnit:makeVideoAU(256, 1.0 + i * 0.04, 50)];
    }
    [muxer tick];

    XCTAssertGreaterThan(delegate.packets.count, (NSUInteger)0,
                         @"VBR muxer should emit packets even with small queue limit");
}

#pragma mark - CBR Bitrate Accuracy

- (void)test_cbr_bitrateExact {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    settings.targetBitrateKbps = 5000; // 5 Mbps
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    [muxer enqueueAccessUnit:makeVideoAU(256, 1.0, 100)];
    [muxer tick];
    XCTAssertEqual(delegate.packets.count, (NSUInteger)0, @"No packets on first CBR tick");

    // Advance exactly 100ms
    mockTimeNanos += 100000000ULL;
    [muxer enqueueAccessUnit:makeVideoAU(256, 1.1, 100)];
    [muxer tick];

    NSUInteger expected = expectedPacketCount(5000, 0.1);
    XCTAssertEqual(delegate.packets.count, expected,
                   @"Packet count should exactly match expected for 5 Mbps over 100ms (expected %lu, got %lu)",
                   (unsigned long)expected, (unsigned long)delegate.packets.count);
}

#pragma mark - Tick-only Emission

- (void)test_cbr_tickWithoutEnqueue_emitsNullPackets {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    settings.targetBitrateKbps = 5000;
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

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
    TSMuxerSettings *settings = makeSettings();
    settings.targetBitrateKbps = 5000;
    const uint16_t videoPid = 256;
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    // Enqueue one video AU to establish pcrPid and emit a first PCR
    [muxer enqueueAccessUnit:makeVideoAU(videoPid, 1.0, 100)];
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

#pragma mark - Transport-Clock PCR Tests

/// Helper: extract all full 27 MHz PCR values (base * 300 + ext) from packets on a given PID.
static NSArray<NSNumber*> *extractPcrValues(NSArray<NSData*> *packets, uint16_t targetPid) {
    NSMutableArray<NSNumber*> *pcrValues = [NSMutableArray array];
    for (NSData *packet in packets) {
        const uint8_t *bytes = packet.bytes;
        uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
        if (pid != targetPid) continue;

        uint8_t adaptationControl = (bytes[3] & 0x30) >> 4;
        if (adaptationControl != 0x02 && adaptationControl != 0x03) continue;

        uint8_t adaptationFlags = bytes[5];
        BOOL pcrFlag = (adaptationFlags & 0x10) != 0;
        if (!pcrFlag) continue;

        // Parse 33-bit PCR base from bytes 6-10
        uint64_t pcrBase = ((uint64_t)bytes[6] << 25)
                         | ((uint64_t)bytes[7] << 17)
                         | ((uint64_t)bytes[8] << 9)
                         | ((uint64_t)bytes[9] << 1)
                         | ((bytes[10] >> 7) & 0x01);
        // Parse 9-bit PCR extension from bytes 10-11
        uint16_t pcrExt = ((bytes[10] & 0x01) << 8) | bytes[11];
        [pcrValues addObject:@(pcrBase * 300 + pcrExt)];
    }
    return pcrValues;
}

- (void)test_pcr_firstPacketCarriesPcr {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    [muxer enqueueAccessUnit:makeVideoAU(256, 1.0, 100)];
    [muxer tick];

    NSArray<NSNumber*> *pcrValues = extractPcrValues(delegate.packets, 256);
    XCTAssertGreaterThan(pcrValues.count, (NSUInteger)0,
                         @"First video AU packet should carry a PCR");
    XCTAssertEqual(pcrValues[0].unsignedLongLongValue, (uint64_t)0,
                   @"First PCR should be 0");
}

- (void)test_pcr_monotonicallyIncreasing_cbr {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    settings.targetBitrateKbps = 5000;
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    // Use 20ms steps (< 30ms PCR interval) so at most 1 PCR per tick.
    for (int i = 0; i < 20; i++) {
        [muxer enqueueAccessUnit:makeVideoAU(256, 1.0 + i * 0.02, 100)];
        mockTimeNanos += 20000000ULL; // 20ms
        [muxer tick];
    }

    NSArray<NSNumber*> *pcrValues = extractPcrValues(delegate.packets, 256);
    XCTAssertGreaterThan(pcrValues.count, (NSUInteger)1, @"Should have multiple PCRs");

    for (NSUInteger i = 1; i < pcrValues.count; i++) {
        XCTAssertGreaterThan(pcrValues[i].unsignedLongLongValue,
                             pcrValues[i-1].unsignedLongLongValue,
                             @"PCR values must be monotonically increasing (index %lu)", (unsigned long)i);
    }
}

- (void)test_pcr_independentOfPts {
    // Simulate B-frame reordering: PTS is non-monotonic but PCR must stay monotonic
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    settings.targetBitrateKbps = 5000;
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    // Non-monotonic PTS order (B-frame pattern): I=1.0, P=1.12, B=1.04, B=1.08
    // Use 20ms steps (< 30ms PCR interval) so at most 1 PCR per tick.
    double ptsOrder[] = {1.0, 1.12, 1.04, 1.08, 1.24, 1.16, 1.20};
    for (int i = 0; i < 7; i++) {
        [muxer enqueueAccessUnit:makeVideoAU(256, ptsOrder[i], 100)];
        mockTimeNanos += 20000000ULL; // 20ms
        [muxer tick];
    }

    NSArray<NSNumber*> *pcrValues = extractPcrValues(delegate.packets, 256);
    XCTAssertGreaterThan(pcrValues.count, (NSUInteger)1, @"Should have multiple PCRs");

    for (NSUInteger i = 1; i < pcrValues.count; i++) {
        XCTAssertGreaterThan(pcrValues[i].unsignedLongLongValue,
                             pcrValues[i-1].unsignedLongLongValue,
                             @"PCR must be monotonic even with non-monotonic PTS (index %lu)", (unsigned long)i);
    }
}

- (void)test_pcr_intervalRespected_cbr {
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    settings.targetBitrateKbps = 5000;
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    // Feed AUs over 500ms
    for (int i = 0; i < 50; i++) {
        [muxer enqueueAccessUnit:makeVideoAU(256, 1.0 + i * 0.01, 50)];
        mockTimeNanos += 10000000ULL; // 10ms
        [muxer tick];
    }

    NSArray<NSNumber*> *pcrValues = extractPcrValues(delegate.packets, 256);
    // Over 500ms at 40ms interval, expect at least 12 PCRs (500/40 = 12.5)
    XCTAssertGreaterThanOrEqual(pcrValues.count, (NSUInteger)12,
                                @"PCR should be emitted at least every 40ms");
}

- (void)test_cbr_pcrUsesTransportTime_notWallClock {
    // A single tick that emits a large burst of packets. If PCR were derived from the
    // wall clock (which doesn't move during the burst), all PCRs would be nearly identical.
    // With transport-time-driven PCR, consecutive values should be ~30ms apart (the PCR interval).
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    settings.targetBitrateKbps = 5000; // 5 Mbps
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    // Seed enough AUs to fill 200ms of stream time at 5 Mbps.
    for (int i = 0; i < 20; i++) {
        [muxer enqueueAccessUnit:makeVideoAU(256, 1.0 + i * 0.01, 500)];
    }

    // First tick — sets firstOutputTimeNanos, emits nothing.
    [muxer tick];

    // Advance wall clock by 200ms and tick ONCE — a single burst emitting ~664 packets.
    // Wall clock stays frozen at this value for the entire burst.
    mockTimeNanos += 200000000ULL;
    [muxer tick];

    NSArray<NSNumber*> *pcrValues = extractPcrValues(delegate.packets, 256);
    XCTAssertGreaterThanOrEqual(pcrValues.count, (NSUInteger)3,
                                 @"200ms burst should contain at least 3 PCRs (one every 30ms)");

    // Consecutive PCR values must be separated by at least 20ms worth of 27 MHz ticks (540,000).
    // With wall-clock PCR, the delta would be near zero (microseconds of loop time).
    const uint64_t minDelta27MHz = 20ULL * 27000; // 20ms in 27 MHz ticks
    for (NSUInteger i = 1; i < pcrValues.count; i++) {
        uint64_t delta = pcrValues[i].unsignedLongLongValue - pcrValues[i-1].unsignedLongLongValue;
        XCTAssertGreaterThanOrEqual(delta, minDelta27MHz,
                                     @"PCR[%lu]-PCR[%lu] delta %llu < %llu (20ms): "
                                     @"PCR must track transport time, not wall clock",
                                     (unsigned long)(i-1), (unsigned long)i, delta, minDelta27MHz);
    }
}

- (void)test_cbr_psiEmittedOnceAtStartup {
    // Regression: psiSendTimeNanos was stored as cbrNanosElapsed which is 0 on the
    // first CBR iteration.  isIntervalElapsed treats 0 as "never sent", so PSI was
    // emitted twice at startup instead of once.
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    settings.targetBitrateKbps = 5000;
    settings.psiIntervalMs = 500; // long interval — only one PSI pair expected in this window
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    [muxer enqueueAccessUnit:makeVideoAU(256, 1.0, 100)];
    [muxer tick];

    // Advance 50ms — well within PSI interval, so only the initial PSI pair should exist.
    mockTimeNanos += 50000000ULL;
    [muxer enqueueAccessUnit:makeVideoAU(256, 1.05, 100)];
    [muxer tick];

    NSUInteger patCount = 0;
    NSUInteger pmtCount = 0;
    for (NSData *packet in delegate.packets) {
        const uint8_t *bytes = packet.bytes;
        uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
        if (pid == 0) patCount++;
        if (pid == settings.pmtPid) pmtCount++;
    }
    XCTAssertEqual(patCount, (NSUInteger)1,
                   @"PSI should be emitted exactly once at startup (got %lu PATs)", (unsigned long)patCount);
    XCTAssertEqual(pmtCount, (NSUInteger)1,
                   @"PSI should be emitted exactly once at startup (got %lu PMTs)", (unsigned long)pmtCount);
}

- (void)test_pcr_pcrBaseZeroEmitted {
    // Regression test: pcrBase=0 should produce a packet WITH pcr flag set
    TSMuxerTestDelegate *delegate = [[TSMuxerTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    [muxer enqueueAccessUnit:makeVideoAU(256, 1.0, 100)];
    [muxer tick];

    // The first PCR should be base=0, and it should actually be present in the packet
    BOOL foundPcrFlagOnFirstVideo = NO;
    for (NSData *packet in delegate.packets) {
        const uint8_t *bytes = packet.bytes;
        uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
        if (pid != 256) continue;

        uint8_t adaptationControl = (bytes[3] & 0x30) >> 4;
        if (adaptationControl == 0x02 || adaptationControl == 0x03) {
            uint8_t adaptationFlags = bytes[5];
            if (adaptationFlags & 0x10) {
                foundPcrFlagOnFirstVideo = YES;
                break;
            }
        }
    }
    XCTAssertTrue(foundPcrFlagOnFirstVideo,
                  @"pcrBase=0 should emit a packet with the PCR flag set (sentinel fix)");
}

@end
