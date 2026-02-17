//
//  TSMuxerVBRTests.m
//  TSMuxDemuxTests
//
//  Tests for VBR muxing behavior.
//

#import <XCTest/XCTest.h>
@import TSMuxDemux;

#pragma mark - Mock Delegate

@interface TSMuxerVBRTestDelegate : NSObject <TSMuxerDelegate>
@property(nonatomic, readonly, nonnull) NSMutableArray<NSData*> *packets;
@end

@implementation TSMuxerVBRTestDelegate

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

#pragma mark - Helpers

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

@interface TSMuxerVBRTests : XCTestCase
@end

@implementation TSMuxerVBRTests

- (void)test_vbr_standalonePcrDuringGap {
    TSMuxerVBRTestDelegate *delegate = [[TSMuxerVBRTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    // Enqueue and emit one AU to establish the ES track
    [muxer enqueueAccessUnit:makeVideoAU(256, 1.0, 100)];
    [muxer tick];
    [delegate.packets removeAllObjects];

    // Advance 100ms with no AUs — should get standalone PCR
    mockTimeNanos += 100000000ULL;
    [muxer tick];

    NSArray<NSNumber*> *pcrValues = extractPcrValues(delegate.packets, 256);
    XCTAssertGreaterThan(pcrValues.count, (NSUInteger)0,
                         @"VBR should emit standalone PCR during content gaps");
}

- (void)test_vbr_standalonePcrCC_matchesLastPayloadCC {
    const uint16_t videoPid = 256;
    TSMuxerVBRTestDelegate *delegate = [[TSMuxerVBRTestDelegate alloc] init];
    TSMuxerSettings *settings = makeSettings();
    settings.pcrPid = videoPid;
    settings.videoPid = videoPid;
    __block uint64_t mockTimeNanos = 1000000000ULL;
    TSMuxer *muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:^{ return mockTimeNanos; } delegate:delegate];

    // Emit one video AU — track CC advances from 0 to some value
    [muxer enqueueAccessUnit:makeVideoAU(videoPid, 1.0, 100)];
    [muxer tick];

    // Find the last CC emitted on the video PID
    uint8_t lastVideoCC = 0;
    for (NSData *packet in delegate.packets) {
        const uint8_t *bytes = packet.bytes;
        uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
        if (pid == videoPid) {
            lastVideoCC = bytes[3] & 0x0F;
        }
    }
    [delegate.packets removeAllObjects];

    // Advance 100ms with no AUs — triggers standalone PCR
    mockTimeNanos += 100000000ULL;
    [muxer tick];

    // Find the standalone PCR packet on the video PID
    for (NSData *packet in delegate.packets) {
        const uint8_t *bytes = packet.bytes;
        uint16_t pid = ((bytes[1] & 0x1F) << 8) | bytes[2];
        if (pid != videoPid) continue;

        uint8_t adaptationControl = (bytes[3] & 0x30) >> 4;
        // Adaptation-only = 0x02
        if (adaptationControl == 0x02) {
            uint8_t pcrCC = bytes[3] & 0x0F;
            XCTAssertEqual(pcrCC, lastVideoCC,
                           @"Standalone PCR CC should equal last emitted video CC (%u), got %u",
                           lastVideoCC, pcrCC);
            return;
        }
    }
    XCTFail(@"No standalone PCR packet found on video PID");
}

@end
