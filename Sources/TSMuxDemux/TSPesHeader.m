//
//  TSPesHeader.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSPesHeader.h"
#import "TSPacket.h"
#import "TSConstants.h"

static const uint8_t TIMESTAMP_LENGTH = 5;

@implementation TSPesHeader

+ (instancetype _Nullable)parseFromPacket:(TSPacket * _Nonnull)packet
{
    NSData *payload = packet.payload;
    if (payload.length < 9) {
        return nil;
    }

    // Validate PES start code (0x00 0x00 0x01)
    uint8_t startCode[3];
    [payload getBytes:startCode range:NSMakeRange(0, 3)];
    if (startCode[0] != 0x00 || startCode[1] != 0x00 || startCode[2] != 0x01) {
        return nil;
    }

    // TODO: Certain stream_ids (byte 3) have no optional PES header - payload starts at byte 6:
    // 0xBC (program_stream_map), 0xBE (padding), 0xBF (private_stream_2),
    // 0xF0/0xF1 (ECM/EMM), 0xF2 (DSMCC), 0xF8 (H.222.1 type E), 0xFF (program_stream_directory).
    // These are rare in TS elementary streams so we parse as normal PES for now.

    // Bytes 4-5: PES packet length (0 = unbounded, common for video)
    uint16_t pesPacketLength = 0;
    [payload getBytes:&pesPacketLength range:NSMakeRange(4, 2)];
    pesPacketLength = CFSwapInt16BigToHost(pesPacketLength);

    uint8_t byte8 = 0x00;
    [payload getBytes:&byte8 range:NSMakeRange(7, 1)];
    const BOOL hasPts = (byte8 & 0x80) != 0x00;
    const BOOL hasDts = (byte8 & 0x40) != 0x00;

    uint8_t byte9 = 0x00;
    [payload getBytes:&byte9 range:NSMakeRange(8, 1)];
    const uint8_t pesHeaderDataLength = byte9;

    // Validate payload has enough bytes for header + declared header data
    const NSUInteger payloadOffset = 9 + pesHeaderDataLength;
    if (payloadOffset > payload.length) {
        return nil;
    }

    // Validate payload has enough bytes for timestamps if present
    if (hasPts && payload.length < 9 + TIMESTAMP_LENGTH) {
        return nil;
    }
    if (hasDts && payload.length < 9 + 2 * TIMESTAMP_LENGTH) {
        return nil;
    }

    uint64_t pts = 0x0;
    uint64_t dts = 0x0;
    if (hasPts) {
        uint8_t ptsBytes[5];
        [payload getBytes:ptsBytes range:NSMakeRange(9, TIMESTAMP_LENGTH)];
        uint64_t ptsBits32To30 = (ptsBytes[0] >> 1) & 0x7;
        uint64_t ptsBits29To22 = ptsBytes[1];
        uint64_t ptsBits21To15 = (ptsBytes[2] >> 1) & 0x7F;
        uint64_t ptsBits14To7 = ptsBytes[3];
        uint64_t ptsBits6To0 = (ptsBytes[4] >> 1) & 0x7F;
        pts = (ptsBits32To30 << 30) | (ptsBits29To22 << 22) | (ptsBits21To15 << 15) | (ptsBits14To7 << 7) | ptsBits6To0;

        if (hasDts) {
            uint8_t dtsBytes[5];
            [payload getBytes:dtsBytes range:NSMakeRange(9 + TIMESTAMP_LENGTH, TIMESTAMP_LENGTH)];
            uint64_t dtsBits32To30 = (dtsBytes[0] >> 1) & 0x7;
            uint64_t dtsBits29To22 = dtsBytes[1];
            uint64_t dtsBits21To15 = (dtsBytes[2] >> 1) & 0x7F;
            uint64_t dtsBits14To7 = dtsBytes[3];
            uint64_t dtsBits6To0 = (dtsBytes[4] >> 1) & 0x7F;
            dts = (dtsBits32To30 << 30) | (dtsBits29To22 << 22) | (dtsBits21To15 << 15) | (dtsBits14To7 << 7) | dtsBits6To0;
        }
    }

    TSPesHeader *header = [[TSPesHeader alloc] init];
    header->_pts = hasPts ? CMTimeMake(pts, TS_TIMESTAMP_TIMESCALE) : kCMTimeInvalid;
    header->_dts = hasDts ? CMTimeMake(dts, TS_TIMESTAMP_TIMESCALE) : kCMTimeInvalid;
    header->_isDiscontinuous = packet.adaptationField.discontinuityFlag;
    header->_payloadOffset = payloadOffset;
    header->_pesPacketLength = pesPacketLength;

    return header;
}

@end
