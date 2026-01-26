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
#import "TSLog.h"
#import "TSBitReader.h"

static const uint8_t TIMESTAMP_LENGTH = 5;

/// Returns YES for stream_ids that have no optional PES header (payload starts at byte 6).
/// See ITU-T H.222.0 Table 2-18 "Stream_id assignments".
static inline BOOL streamIdHasNoOptionalHeader(uint8_t streamId) {
    switch (streamId) {
        case 0xBC: // program_stream_map
        case 0xBE: // padding_stream
        case 0xBF: // private_stream_2
        case 0xF0: // ECM_stream
        case 0xF1: // EMM_stream
        case 0xF2: // DSMCC_stream
        case 0xF8: // ITU-T Rec. H.222.1 type E stream
        case 0xFF: // program_stream_directory
            return YES;
        default:
            return NO;
    }
}

/// Parses a 33-bit PTS/DTS timestamp from 5 bytes.
/// Format: 4-bit prefix | 3 bits (32-30) | marker | 15 bits (29-15) | marker | 15 bits (14-0) | marker
/// @param reader Bit reader positioned at start of timestamp bytes.
/// @param expectedPrefix Expected 4-bit prefix (0x2 for PTS-only, 0x3 for PTS with DTS, 0x1 for DTS)
/// @param outTimestamp Output for the 33-bit timestamp value.
/// @return YES if parsing succeeded with valid markers and prefix.
static inline BOOL parseTimestamp(TSBitReader *reader, uint8_t expectedPrefix, uint64_t *outTimestamp) {
    if (!TSBitReaderHasBits(reader, 40)) {  // 5 bytes = 40 bits
        return NO;
    }

    uint8_t prefix = TSBitReaderReadBits(reader, 4);
    uint64_t bits32_30 = TSBitReaderReadBits(reader, 3);
    uint8_t marker1 = TSBitReaderReadBits(reader, 1);
    uint64_t bits29_15 = TSBitReaderReadBits(reader, 15);
    uint8_t marker2 = TSBitReaderReadBits(reader, 1);
    uint64_t bits14_0 = TSBitReaderReadBits(reader, 15);
    uint8_t marker3 = TSBitReaderReadBits(reader, 1);

    if (reader->error) {
        return NO;
    }

    if (prefix != expectedPrefix || marker1 != 1 || marker2 != 1 || marker3 != 1) {
        TSLogWarnC(@"Invalid timestamp: prefix=0x%X (expected 0x%X), markers=%d%d%d",
                   prefix, expectedPrefix, marker1, marker2, marker3);
        return NO;
    }

    *outTimestamp = (bits32_30 << 30) | (bits29_15 << 15) | bits14_0;
    return YES;
}

@implementation TSPesHeader

+ (instancetype _Nullable)parseFromPacket:(TSPacket * _Nonnull)packet
{
    NSData *payload = packet.payload;

    // Minimum PES header: start code (3) + stream_id (1) + length (2) = 6 bytes
    if (payload.length < 6) {
        return nil;
    }

    TSBitReader reader = TSBitReaderMake(payload);

    // Validate PES start code (0x00 0x00 0x01)
    if (TSBitReaderReadUInt8(&reader) != 0x00 ||
        TSBitReaderReadUInt8(&reader) != 0x00 ||
        TSBitReaderReadUInt8(&reader) != 0x01) {
        return nil;
    }

    // Byte 4: stream_id
    const uint8_t streamId = TSBitReaderReadUInt8(&reader);

    // Bytes 5-6: PES packet length (0 = unbounded, common for video)
    const uint16_t pesPacketLength = TSBitReaderReadUInt16BE(&reader);

    // Check stream_id for alternate PES format (no optional header, payload at byte 6)
    if (streamIdHasNoOptionalHeader(streamId)) {
        TSPesHeader *header = [[TSPesHeader alloc] init];
        header->_pts = kCMTimeInvalid;
        header->_dts = kCMTimeInvalid;
        header->_isDiscontinuous = packet.adaptationField.discontinuityFlag;
        header->_payloadOffset = 6;
        header->_pesPacketLength = pesPacketLength;
        return header;
    }

    // Normal PES format requires at least 9 bytes (6 + flags1 + flags2 + header_data_length)
    if (payload.length < 9) {
        return nil;
    }

    // Byte 7: flags1 (skip - contains marker bits and scrambling control)
    TSBitReaderSkip(&reader, 1);

    // Byte 8: flags2 - PTS/DTS flags are the top 2 bits
    const BOOL hasPts = TSBitReaderReadBits(&reader, 1) != 0;
    const BOOL hasDts = TSBitReaderReadBits(&reader, 1) != 0;
    TSBitReaderSkipBits(&reader, 6);  // Skip remaining flags

    // Byte 9: PES header data length
    const uint8_t pesHeaderDataLength = TSBitReaderReadUInt8(&reader);

    if (reader.error) {
        TSLogWarn(@"PES header truncated while reading header fields");
        return nil;
    }

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

    BOOL ptsValid = NO;
    BOOL dtsValid = NO;
    uint64_t pts = 0;
    uint64_t dts = 0;

    if (hasPts) {
        // PTS prefix: 0010 for PTS-only, 0011 for PTS+DTS
        uint8_t expectedPtsPrefix = hasDts ? 0x3 : 0x2;
        ptsValid = parseTimestamp(&reader, expectedPtsPrefix, &pts);

        if (hasDts) {
            // DTS prefix: 0001
            dtsValid = parseTimestamp(&reader, 0x1, &dts);
        }
    }

    TSPesHeader *header = [[TSPesHeader alloc] init];
    header->_pts = ptsValid ? CMTimeMake(pts, TS_TIMESTAMP_TIMESCALE) : kCMTimeInvalid;
    header->_dts = dtsValid ? CMTimeMake(dts, TS_TIMESTAMP_TIMESCALE) : kCMTimeInvalid;
    header->_isDiscontinuous = packet.adaptationField.discontinuityFlag;
    header->_payloadOffset = payloadOffset;
    header->_pesPacketLength = pesPacketLength;

    return header;
}

@end
