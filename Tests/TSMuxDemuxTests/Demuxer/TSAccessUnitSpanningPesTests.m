//
//  TSAccessUnitSpanningPesTests.m
//  TSMuxDemuxTests
//
//  An access unit may span several PES packets (H.222.0 2.4.3.7): the PTS travels in the
//  PES packet in which the access unit begins, and continuation PES packets carry none.
//  Muxers with a bounded PES length split every large picture this way, and some put the
//  parameter sets in a PES of their own. TSElementaryStreamBuilder must hand the decoder
//  the whole access unit under that one PTS — never a picture-less "access unit" made of
//  parameter sets, nor a picture without its timestamp.
//
//  For H.264/HEVC the access unit boundary is the access unit delimiter (required at the
//  start of every access unit in a transport stream as we read H.222.0 2.14.1 / 2.17.1);
//  without one, a PES continues the current unit unless it carries a PTS the unit does not
//  already have. Same-PTS aggregation of PES packets without a delimiter is kept.
//
#import <XCTest/XCTest.h>
#import "../TSTestUtils.h"
@import TSMuxDemux;

static const uint16_t kPmtPid = 0x100;
static const uint16_t kVideoPid = 0x101;
static const uint8_t kRawStreamTypeMPEG2VideoLocal = 0x02;

static NSData *NAL(const uint8_t *body, size_t n) {
    static const uint8_t startCode[] = {0x00, 0x00, 0x00, 0x01};
    NSMutableData *d = [NSMutableData dataWithBytes:startCode length:4];
    [d appendBytes:body length:n];
    return d;
}
static NSData *Cat(NSArray<NSData *> *parts) {
    NSMutableData *d = [NSMutableData data];
    for (NSData *p in parts) [d appendData:p];
    return d;
}
#define BYTES(...) ((const uint8_t[]){__VA_ARGS__}), sizeof((const uint8_t[]){__VA_ARGS__})

// H.264 NAL units (header byte + a few payload bytes; content is irrelevant to the builder)
static NSData *H264Aud(void)  { return NAL(BYTES(0x09, 0xF0)); }
static NSData *H264Sps(void)  { return NAL(BYTES(0x67, 0x42, 0x00, 0x0A, 0xF8, 0x41, 0xA2)); }
static NSData *H264Pps(void)  { return NAL(BYTES(0x68, 0xCE, 0x38, 0x80)); }
static NSData *H264Sei(void)  { return NAL(BYTES(0x06, 0x05, 0x01, 0x80)); }
static NSData *H264Idr(void)  { return NAL(BYTES(0x65, 0x88, 0x84, 0x00, 0x21)); }
static NSData *H264P(uint8_t tag) { return NAL(BYTES(0x41, 0x9A, tag, 0x03)); }
// HEVC NAL units (2-byte header)
static NSData *HevcAud(void)  { return NAL(BYTES(0x46, 0x01, 0x50)); }
static NSData *HevcVps(void)  { return NAL(BYTES(0x40, 0x01, 0x0C, 0x01)); }
static NSData *HevcSps(void)  { return NAL(BYTES(0x42, 0x01, 0x01, 0x01)); }
static NSData *HevcPps(void)  { return NAL(BYTES(0x44, 0x01, 0xC1, 0x72)); }
static NSData *HevcIdr(void)  { return NAL(BYTES(0x26, 0x01, 0xAF, 0x08)); }
static NSData *HevcP(uint8_t tag) { return NAL(BYTES(0x02, 0x01, 0xD0, tag)); }

@interface TSSpanningPesDelegate : NSObject <TSDemuxerDelegate>
@property(nonatomic, strong) NSMutableArray<TSAccessUnit *> *aus;
@end
@implementation TSSpanningPesDelegate
- (instancetype)init { if ((self = [super init])) _aus = [NSMutableArray array]; return self; }
- (void)demuxer:(TSDemuxer *)d didReceivePat:(TSProgramAssociationTable *)p previousPat:(TSProgramAssociationTable *)q {}
- (void)demuxer:(TSDemuxer *)d didReceivePmt:(TSProgramMapTable *)p previousPmt:(TSProgramMapTable *)q {}
- (void)demuxer:(TSDemuxer *)d didReceiveAccessUnit:(TSAccessUnit *)au { [self.aus addObject:au]; }
@end

@interface TSAccessUnitSpanningPesTests : XCTestCase
@property(nonatomic, strong) TSSpanningPesDelegate *delegate;
@property(nonatomic, strong) TSDemuxer *demuxer;
@property(nonatomic, strong) TSElementaryStream *track;
@end

@implementation TSAccessUnitSpanningPesTests

- (void)setUpStreamType:(uint8_t)streamType {
    self.delegate = [TSSpanningPesDelegate new];
    self.demuxer = [[TSDemuxer alloc] initWithDelegate:self.delegate mode:TSDemuxerModeDVB];
    [self.demuxer demux:[TSTestUtils createPatDataWithPmtPid:kPmtPid] dataArrivalHostTimeNanos:0];
    TSElementaryStream *es = [[TSElementaryStream alloc] initWithPid:kVideoPid streamType:streamType descriptors:nil];
    [self.demuxer demux:[TSTestUtils createPmtDataWithPmtPid:kPmtPid pcrPid:kVideoPid streams:@[es] versionNumber:0 continuityCounter:0]
   dataArrivalHostTimeNanos:0];
    self.track = [[TSElementaryStream alloc] initWithPid:kVideoPid streamType:streamType descriptors:nil];
}

/// Sends one PES packet (whole payload, PTS or kCMTimeInvalid for none).
- (void)pes:(NSData *)payload pts:(CMTime)pts {
    [self.demuxer demux:[TSTestUtils createPesDataWithTrack:self.track payload:payload pts:pts] dataArrivalHostTimeNanos:0];
}

- (void)assertAccessUnit:(NSUInteger)index equals:(NSData *)expected pts:(CMTime)pts {
    XCTAssertGreaterThan(self.delegate.aus.count, index, @"access unit %lu was not delivered", (unsigned long)index);
    if (self.delegate.aus.count <= index) return;
    TSAccessUnit *au = self.delegate.aus[index];
    XCTAssertEqualObjects(au.compressedData, expected, @"access unit %lu bytes", (unsigned long)index);
    if (CMTIME_IS_VALID(pts)) {
        XCTAssertTrue(CMTIME_IS_VALID(au.pts) && CMTimeCompare(au.pts, pts) == 0,
                      @"access unit %lu PTS: got %lld, want %lld", (unsigned long)index, au.pts.value, pts.value);
    } else {
        XCTAssertFalse(CMTIME_IS_VALID(au.pts), @"access unit %lu should have no PTS", (unsigned long)index);
    }
}

#pragma mark - H.264

/// Conformant split: the PES in which the access unit begins carries the PTS and the
/// delimiter + parameter sets; the picture follows in a PES packet without a PTS.
- (void)test_h264_accessUnitSpanningTwoPes_isReassembledUnderThePtsOfItsFirstPes {
    [self setUpStreamType:kRawStreamTypeH264];
    CMTime p1 = CMTimeMake(90000, 90000), p2 = CMTimeMake(93600, 90000), p3 = CMTimeMake(97200, 90000);
    NSData *sets = Cat(@[H264Aud(), H264Sps(), H264Pps()]);
    NSData *pic  = Cat(@[H264Sei(), H264Idr()]);
    [self pes:sets pts:p1];
    [self pes:pic pts:kCMTimeInvalid];
    [self pes:Cat(@[H264Aud(), H264P(1)]) pts:p2];       // next picture flushes the first
    [self pes:Cat(@[H264Aud(), H264P(2)]) pts:p3];       // and the one after flushes that
    XCTAssertEqual(self.delegate.aus.count, 2u, @"two pictures delivered, none of them picture-less");
    [self assertAccessUnit:0 equals:Cat(@[sets, pic]) pts:p1];
    [self assertAccessUnit:1 equals:Cat(@[H264Aud(), H264P(1)]) pts:p2];
}

/// Sloppy split: the delimiter + parameter sets travel in a PES without a PTS and the PTS
/// arrives on the PES that carries the picture. The builder does not guess: the sets are
/// delivered as a unit of their own, without timestamp (the sample handlers hold such a
/// unit and prepend it to the picture), and the picture keeps its PTS. Welding a
/// timestamped PES onto an untimed unit would also weld a clean picture onto a fragment
/// left over from a continuity gap.
- (void)test_h264_ptsOnlyOnThePicturePes_setsAndPictureAreSeparateUnits {
    [self setUpStreamType:kRawStreamTypeH264];
    CMTime p0 = CMTimeMake(86400, 90000), p1 = CMTimeMake(90000, 90000), p2 = CMTimeMake(93600, 90000);
    NSData *prev = Cat(@[H264Aud(), H264P(9)]);
    NSData *sets = Cat(@[H264Aud(), H264Sps(), H264Pps()]);
    NSData *pic  = Cat(@[H264Sei(), H264Idr()]);
    [self pes:prev pts:p0];
    [self pes:sets pts:kCMTimeInvalid];
    [self pes:pic pts:p1];
    [self pes:Cat(@[H264Aud(), H264P(1)]) pts:p2];
    XCTAssertEqual(self.delegate.aus.count, 3u);
    [self assertAccessUnit:0 equals:prev pts:p0];
    [self assertAccessUnit:1 equals:sets pts:kCMTimeInvalid];
    [self assertAccessUnit:2 equals:pic pts:p1];
}

/// Parameter sets spread over several PES packets accumulate into the one access unit.
- (void)test_h264_parameterSetsSpreadOverThreePes_formOneAccessUnit {
    [self setUpStreamType:kRawStreamTypeH264];
    CMTime p1 = CMTimeMake(90000, 90000), p2 = CMTimeMake(93600, 90000);
    NSData *a = Cat(@[H264Aud(), H264Sps()]), *b = H264Pps(), *c = Cat(@[H264Sei(), H264Idr()]);
    [self pes:a pts:p1];
    [self pes:b pts:kCMTimeInvalid];
    [self pes:c pts:kCMTimeInvalid];
    [self pes:Cat(@[H264Aud(), H264P(1)]) pts:p2];
    XCTAssertEqual(self.delegate.aus.count, 1u);
    [self assertAccessUnit:0 equals:Cat(@[a, b, c]) pts:p1];
}

/// Two delimited units sharing one PTS — an encoder stamping both fields of a frame with the
/// frame's time — are two access units: the delimiter wins over the PTS. The H.264 handler
/// pairs the fields downstream. (Slices of one picture sharing a PTS have no delimiter on the
/// later PES packets and are still aggregated, see the same-PTS tests.)
- (void)test_h264_twoDelimitedUnitsWithTheSamePts_areSeparateUnits {
    [self setUpStreamType:kRawStreamTypeH264];
    CMTime p1 = CMTimeMake(90000, 90000), p2 = CMTimeMake(93600, 90000);
    NSData *top = Cat(@[H264Aud(), H264P(1)]), *bottom = Cat(@[H264Aud(), H264P(2)]);
    [self pes:top pts:p1];
    [self pes:bottom pts:p1];
    [self pes:Cat(@[H264Aud(), H264P(3)]) pts:p2];
    XCTAssertEqual(self.delegate.aus.count, 2u);
    [self assertAccessUnit:0 equals:top pts:p1];
    [self assertAccessUnit:1 equals:bottom pts:p1];
}

/// A delimiter with a new PTS starts a new unit even when the previous one is still open.
- (void)test_h264_delimiterWithNewPts_startsNewUnit {
    [self setUpStreamType:kRawStreamTypeH264];
    CMTime p1 = CMTimeMake(90000, 90000), p2 = CMTimeMake(93600, 90000), p3 = CMTimeMake(97200, 90000);
    [self pes:Cat(@[H264Aud(), H264P(1)]) pts:p1];
    [self pes:Cat(@[H264Aud(), H264P(2)]) pts:p2];
    [self pes:Cat(@[H264Aud(), H264P(3)]) pts:p3];
    XCTAssertEqual(self.delegate.aus.count, 2u);
    [self assertAccessUnit:0 equals:Cat(@[H264Aud(), H264P(1)]) pts:p1];
    [self assertAccessUnit:1 equals:Cat(@[H264Aud(), H264P(2)]) pts:p2];
}

#pragma mark - HEVC

- (void)test_hevc_accessUnitSpanningTwoPes_isReassembledUnderThePtsOfItsFirstPes {
    [self setUpStreamType:kRawStreamTypeH265];
    CMTime p1 = CMTimeMake(90000, 90000), p2 = CMTimeMake(93600, 90000);
    NSData *sets = Cat(@[HevcAud(), HevcVps(), HevcSps(), HevcPps()]);
    NSData *pic  = HevcIdr();
    [self pes:sets pts:p1];
    [self pes:pic pts:kCMTimeInvalid];
    [self pes:Cat(@[HevcAud(), HevcP(1)]) pts:p2];
    XCTAssertEqual(self.delegate.aus.count, 1u);
    [self assertAccessUnit:0 equals:Cat(@[sets, pic]) pts:p1];
}

- (void)test_hevc_ptsOnlyOnThePicturePes_setsAndPictureAreSeparateUnits {
    [self setUpStreamType:kRawStreamTypeH265];
    CMTime p0 = CMTimeMake(86400, 90000), p1 = CMTimeMake(90000, 90000), p2 = CMTimeMake(93600, 90000);
    NSData *prev = Cat(@[HevcAud(), HevcP(9)]);
    NSData *sets = Cat(@[HevcAud(), HevcVps(), HevcSps(), HevcPps()]);
    [self pes:prev pts:p0];
    [self pes:sets pts:kCMTimeInvalid];
    [self pes:HevcIdr() pts:p1];
    [self pes:Cat(@[HevcAud(), HevcP(1)]) pts:p2];
    XCTAssertEqual(self.delegate.aus.count, 3u);
    [self assertAccessUnit:0 equals:prev pts:p0];
    [self assertAccessUnit:1 equals:sets pts:kCMTimeInvalid];
    [self assertAccessUnit:2 equals:HevcIdr() pts:p1];
}

#pragma mark - Video without delimiters (MPEG-2)

/// After a continuity gap the first PES of a picture may be lost, leaving a fragment that
/// starts a unit without a PTS. The next timestamped PES is a new picture and must not be
/// welded onto that fragment.
- (void)test_mpeg2video_untimedFragmentThenTimestampedPicture_areSeparateUnits {
    [self setUpStreamType:kRawStreamTypeMPEG2VideoLocal];
    CMTime p1 = CMTimeMake(90000, 90000), p2 = CMTimeMake(93600, 90000);
    uint8_t frag[] = {0x00, 0x00, 0x01, 0x05, 0x9A, 0x7B, 0x6C};                                   // tail slices of a lost picture
    uint8_t pict[] = {0x00, 0x00, 0x01, 0x00, 0x00, 0x1F, 0xFF, 0xF8, 0x00, 0x00, 0x01, 0x01, 0x4D};
    NSData *f = [NSData dataWithBytes:frag length:sizeof(frag)], *pic = [NSData dataWithBytes:pict length:sizeof(pict)];
    [self pes:f pts:kCMTimeInvalid];
    [self pes:pic pts:p1];
    [self pes:pic pts:p2];
    XCTAssertEqual(self.delegate.aus.count, 2u);
    [self assertAccessUnit:0 equals:f pts:kCMTimeInvalid];
    [self assertAccessUnit:1 equals:pic pts:p1];
}

/// MPEG-2 video has no delimiter NAL: a PES without a PTS simply continues the picture
/// being collected (a bounded-PES mux splits every large picture this way).
- (void)test_mpeg2video_ptsLessPes_continuesTheCurrentAccessUnit {
    [self setUpStreamType:kRawStreamTypeMPEG2VideoLocal];
    CMTime p1 = CMTimeMake(90000, 90000), p2 = CMTimeMake(93600, 90000);
    uint8_t head[] = {0x00, 0x00, 0x01, 0xB3, 0x2D, 0x02, 0x40, 0x00, 0x00, 0x01, 0x00, 0x00, 0x0F, 0xFF, 0xF8};
    uint8_t tail[] = {0x00, 0x00, 0x01, 0x01, 0x1A, 0x2B, 0x3C};
    uint8_t next[] = {0x00, 0x00, 0x01, 0x00, 0x00, 0x1F, 0xFF, 0xF8, 0x00, 0x00, 0x01, 0x01, 0x4D};
    NSData *h = [NSData dataWithBytes:head length:sizeof(head)], *t = [NSData dataWithBytes:tail length:sizeof(tail)];
    [self pes:h pts:p1];
    [self pes:t pts:kCMTimeInvalid];
    [self pes:[NSData dataWithBytes:next length:sizeof(next)] pts:p2];
    XCTAssertEqual(self.delegate.aus.count, 1u);
    [self assertAccessUnit:0 equals:Cat(@[h, t]) pts:p1];
}

@end
