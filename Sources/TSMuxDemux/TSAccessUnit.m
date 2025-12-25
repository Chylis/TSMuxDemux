//
//  TSAccessUnit.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSAccessUnit.h"
#import "TSConstants.h"
#import "TSTimeUtil.h"

#pragma mark - TSAccessUnit

static const uint8_t TIMESTAMP_LENGTH = 5; // A timestamp (pts/dts) is a 33-bit field contained in a 5-byte container

@implementation TSAccessUnit

-(instancetype _Nonnull)initWithPid:(uint16_t)pid
                                pts:(CMTime)pts
                                dts:(CMTime)dts
                    isDiscontinuous:(BOOL)isDiscontinuous
                         streamType:(uint8_t)streamType
                        descriptors:(NSArray<TSDescriptor *> * _Nullable)descriptors
                     compressedData:(NSData * _Nonnull)compressedData
{
    self = [super init];
    if (self) {
        _pid = pid;
        _pts = pts;
        _dts = dts;
        _isDiscontinuous = isDiscontinuous;
        _streamType = streamType;
        _descriptors = descriptors;
        _compressedData = compressedData;
    }
    return self;
}

-(NSData* _Nonnull)toTsPacketPayload
{
    const BOOL hasPTS = !CMTIME_IS_INVALID(self.pts);
    const BOOL hasDTS = !CMTIME_IS_INVALID(self.dts);

    NSMutableData *header = [NSMutableData data];

    // Start code (4 bytes)
    uint8_t startCode[4];
    startCode[0] = 0x00;
    startCode[1] = 0x00;
    startCode[2] = 0x01;
    startCode[3] = self.streamId;
    [header appendBytes:startCode length:4];

    // PES-packet length (2 bytes):
    // Specifies the number of bytes remaining in the packet after this field.
    // Can be zero for video access units.
    uint16_t pesPacketLength = 1 + 1 + 1 + self.compressedData.length; // flags-1 length + flags-2 length + PES-header-data-length + payload
    uint8_t ptsDtsIndicator = 0x00; // 0x00 equals no timetamps available
    if (hasPTS) {
        ptsDtsIndicator = 0x02; // 0x02 equals only PTS available
        pesPacketLength += TIMESTAMP_LENGTH;

        if (hasDTS) {
            ptsDtsIndicator = 0x03; // 0x03 equals both PTS and DTS available
            pesPacketLength += TIMESTAMP_LENGTH;
        }
    }

    pesPacketLength = CFSwapInt16HostToBig(pesPacketLength);
    [header appendBytes:&pesPacketLength length:2];

    // Flags-1 (1 byte)
    // bits 1-2:    10 (marker bits)
    // bits 3-4:    00 (not scrambled)
    // bit 5:       0 (priority)
    // bit 6:       0 (data alignment)
    // bit 7:       0 (copyright)
    // bit 8:       0 (original or copy)
    const uint8_t flags1 = 0b10000000;
    [header appendBytes:&flags1 length:1];

    // Flags-2 (1 byte)
    // bits 1-2:    11 or 10 or 00 (pts+dts indicator)
    // bit 3:       0 (ESCR)
    // bit 4:       0 (ES rate)
    // bit 5:       0 (dsm trick mode)
    // bit 6:       0 (additional copy info)
    // bit 7:       0 (PES crc)
    // bit 8:       0 (PES extension)
    const uint8_t flags2 = ptsDtsIndicator << 6;
    [header appendBytes:&flags2 length:1];

    // PES header data length:
    // The number of bytes of optional header data present in the header before the first byte of the PES-packet payload is reached.
    uint8_t pesHeaderDataLength = (hasPTS && hasDTS ? 2 : hasPTS ? 1 : 0) * TIMESTAMP_LENGTH;
    [header appendBytes:&pesHeaderDataLength length:1];

    if (hasPTS) {
        uint64_t pts = [TSTimeUtil convertTimeToUIntTime:self.pts withNewTimescale:TS_TIMESTAMP_TIMESCALE];
        // PTS (5 bytes)
        uint8_t ptsSection[TIMESTAMP_LENGTH];
        // bits 1-4:    0011 or 0010 (i.e. the four last bits of indicator)
        // bits 5-7:    Bits 32-30 of the PTS
        // bit 8:       0x1 (marker bit)
        ptsSection[0] = (pts >> 29) | 0x01 | (ptsDtsIndicator << 4);
        // bits 9-16:   Bits 29-22 of the PTS
        ptsSection[1] = pts >> 22;
        // bits 17-23:  Bits 21-15 of the PTS
        // bit 24:      0x1 (marker bit)
        ptsSection[2] = (pts >> 14) | 0x01;
        // bit 25-32:   Bits 14-7 of the PTS
        ptsSection[3] = pts >> 7;
        // bit 33-39:   Bits 6-0 of the PTS
        // bit 40:      0x1 (marker bit)
        ptsSection[4] = (pts << 1) | 0x01;

        [header appendBytes:ptsSection length:TIMESTAMP_LENGTH];

        if (hasDTS) {
            uint64_t dts = [TSTimeUtil convertTimeToUIntTime:self.dts withNewTimescale:TS_TIMESTAMP_TIMESCALE];
            // DTS (5 bytes)
            uint8_t dtsSection[TIMESTAMP_LENGTH];
            // bits 1-4:    0001 (dts marker)
            // bits 5-7:    Bits 32-30 of the DTS
            // bit 8:       0x1 (marker bit)
            dtsSection[0] = (dts >> 29) | 0x01 | (0x01 << 4);
            // bits 9-16:   Bits 29-22 of the DTS
            dtsSection[1] = dts >> 22;
            // bits 17-23:  Bits 21-15 of the DTS
            // bit 24:      0x1 (marker bit)
            dtsSection[2] = (dts >> 14) | 0x01;
            // bit 25-32:   Bits 14-7 of the DTS
            dtsSection[3] = dts >> 7;
            // bit 33-39:   Bits 6-0 of the DTS
            // bit 40:      0x1 (marker bit)
            dtsSection[4] = (dts << 1) | 0x01;

            [header appendBytes:dtsSection length:TIMESTAMP_LENGTH];
        }
    }

    // Construct packet (i.e. header + payload)
    NSMutableData *packet = [NSMutableData dataWithData:header];
    [packet appendData:self.compressedData];
    //NSAssert(packet.length <= 65536, @"PES packet exceeds max size"); //FIXME MG: <-- This was triggered on iPad
    return packet;
}

-(TSResolvedStreamType)resolvedStreamType
{
    return [TSStreamType resolveStreamType:self.streamType descriptors:self.descriptors];
}

-(BOOL)isAudio
{
    return [TSStreamType isAudio:[self resolvedStreamType]];
}

-(BOOL)isVideo
{
    return [TSStreamType isVideo:[self resolvedStreamType]];
}

-(NSString*)resolvedStreamTypeDescription
{
    return [TSStreamType descriptionForResolvedStreamType:[self resolvedStreamType]];
}

-(uint8_t)streamId
{
    return [TSStreamType streamIdFromStreamType:self.streamType];
}

@end
