//
//  TSAccessUnit.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSAccessUnit.h"
#import "TSPacket.h"
#import "TSConstants.h"
#import "TSTimeUtil.h"

#pragma mark - TSAccessUnit

static const uint8_t TIMESTAMP_LENGTH = 5; // A timestamp (pts/dts) is a 33-bit field contained in a 5-byte container

@implementation TSAccessUnit

-(instancetype _Nonnull)initWithPid:(uint16_t)pid
                                pts:(CMTime)pts
                                dts:(CMTime)dts
                    isDiscontinuous:(BOOL)isDiscontinuous
                         streamType:(TSStreamType)streamType
                      descriptorTag:(TSDescriptorTag)descriptorTag
                     compressedData:(NSData * _Nonnull)compressedData
{
    self = [super init];
    if (self) {
        _pid = pid;
        _pts = pts;
        _dts = dts;
        _isDiscontinuous = isDiscontinuous;
        _streamType = streamType;
        _descriptorTag = descriptorTag;
        _compressedData = compressedData;
    }
    return self;
}

+(instancetype _Nullable)initWithTsPacket:(TSPacket* _Nonnull)packet
                                      pid:(uint16_t)pid
                               streamType:(TSStreamType)streamType
                            descriptorTag:(TSDescriptorTag)descriptorTag
{
    
    uint32_t bytes1To4 = 0x00;
    [packet.payload getBytes:&bytes1To4 range:NSMakeRange(0, 4)];
    const uint8_t streamId = CFSwapInt32BigToHost(bytes1To4) & (uint32_t)0xFF;
    const uint32_t startCode = (CFSwapInt32BigToHost(bytes1To4) & 0xFFFFFF00) >> 8;
    // FIXME MG: NSAssert(startCode == 0x01, @"Invalid PES header startcode");
    
    //    uint16_t bytes5And6 = 0x00;
    //    [packet.payload getBytes:&bytes5And6 range:NSMakeRange(4, 2)];
    //    const uint16_t pesPacketLength = CFSwapInt16BigToHost(bytes5And6);
    
    // TODO: Parse byte7/flags1 and add properties accordingly
    
    uint8_t byte8 = 0x00;
    [packet.payload getBytes:&byte8 range:NSMakeRange(7, 1)];
    const BOOL hasPts = (byte8 & 0x80) != 0x00;
    const BOOL hasDts = (byte8 & 0x40) != 0x00;
    
    uint8_t byte9 = 0x00;
    [packet.payload getBytes:&byte9 range:NSMakeRange(8, 1)];
    // The number of bytes of optional header data present in the header before the first byte of the PES-packet payload is reached.
    const uint8_t pesHeaderDataLength = byte9;
    
    uint64_t pts = 0x0;
    uint64_t dts = 0x0;
    if (hasPts) {
        uint8_t ptsBytes[5];
        [packet.payload getBytes:ptsBytes range:NSMakeRange(9, TIMESTAMP_LENGTH)];
        uint64_t ptsBits32To30 = (ptsBytes[0] >> 1) & 0x7;
        uint64_t ptsBits29To22 = ptsBytes[1];
        uint64_t ptsBits22To15 = (ptsBytes[2] >> 1) & 0x7F;
        uint64_t ptsBits14To7 = ptsBytes[3];
        uint64_t ptsBits7To0 = (ptsBytes[4] >> 1) & 0x7F;
        pts = (ptsBits32To30 << 30) | (ptsBits29To22 << 22) | (ptsBits22To15 << 15) | (ptsBits14To7 << 7) | ptsBits7To0;
        
        if (hasDts) {
            uint8_t dtsBytes[5];
            [packet.payload getBytes:dtsBytes range:NSMakeRange(9+TIMESTAMP_LENGTH, TIMESTAMP_LENGTH)];
            uint64_t dtsBits32To30 = (dtsBytes[0] >> 1) & 0x7;
            uint64_t dtsBits29To22 = dtsBytes[1];
            uint64_t dtsBits22To15 = (dtsBytes[2] >> 1) & 0x7f;
            uint64_t dtsBits14To7 = dtsBytes[3];
            uint64_t dtsBits7To0 = (dtsBytes[4] >> 1) & 0x7f;
            dts = (dtsBits32To30 << 30) | (dtsBits29To22 << 22) | (dtsBits22To15 << 15) | (dtsBits14To7 << 7) | dtsBits7To0;
        }
    }
    
    const NSUInteger payloadOffset = 9 + pesHeaderDataLength;
    const NSUInteger payloadSize = packet.payload.length - payloadOffset;
    NSData *data = [packet.payload subdataWithRange:NSMakeRange(payloadOffset, payloadSize)];
    
    return [[TSAccessUnit alloc] initWithPid:pid
                                         pts:pts == 0 ? kCMTimeInvalid : CMTimeMake(pts, TS_TIMESTAMP_TIMESCALE)
                                         dts:dts == 0 ? kCMTimeInvalid : CMTimeMake(dts, TS_TIMESTAMP_TIMESCALE)
                             isDiscontinuous:packet.adaptationField.discontinuityFlag
                                  streamType:streamType
                               descriptorTag:descriptorTag
                              compressedData:data];
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


-(BOOL)isAudioStreamType
{
    return [TSAccessUnit isAudioStreamType:self.streamType descriptorTag:self.descriptorTag];
}
+(BOOL)isAudioStreamType:(TSStreamType)streamType descriptorTag:(TSDescriptorTag)descriptorTag
{
    switch (streamType) {
        case TSStreamTypeH264:      return NO;
        case TSStreamTypeH265:      return NO;
        case TSStreamTypeADTSAAC:   return YES;
        case TSStreamTypePrivateData: return [TSAccessUnit isAudioDescriptorTag:descriptorTag];
    }
    return NO;
}

+(BOOL)isAudioDescriptorTag:(TSDescriptorTag)descriptorTag
{
    switch (descriptorTag) {
        case TSDescriptorTagUnknown: return NO;
        case TSDescriptorTagVideoStream: return NO;
        case TSDescriptorTagAudioStream: return YES;
        case TSDescriptorTagRegistration: return NO; // FIXME MG: Parse and read format_identifier
        case TSDescriptorTagISO639Language: return NO;
        case TSDescriptorTagMaximumBitrate: return NO;
        case TSDescriptorTagStreamIdentifier: return NO;
        case TSDescriptorTagTeletext: return NO;
        case TSDescriptorTagAc3: return YES;
        case TSDescriptorTagEnhancedAc3: return YES;
        case TSDescriptorTagAac: return YES;
            // FIXME MG: 0x7F indicates an extension_descriptor, i.e you need to check the next byte (descriptor_tag_extension). Could be AC4
        case TSDescriptorTagExtension: return NO;
    }
    return NO;
}


-(BOOL)isVideoStreamType
{
    return [TSAccessUnit isVideoStreamType:self.streamType];
}
+(BOOL)isVideoStreamType:(TSStreamType)streamType
{
    switch (streamType) {
        case TSStreamTypeH264:      return YES;
        case TSStreamTypeH265:      return YES;
        case TSStreamTypeADTSAAC:   return NO;
        case TSStreamTypePrivateData: return NO;
    }
    return NO;
}


-(NSString*)streamTypeDescription
{
    return [TSAccessUnit streamTypeDescription:self.streamType descriptorTag:self.descriptorTag];
}
+(NSString*)streamTypeDescription:(TSStreamType)streamType descriptorTag:(TSDescriptorTag)descriptorTag
{
    switch (streamType) {
        case TSStreamTypeADTSAAC:
            return @"ADTS AAC";
        case TSStreamTypeH264:
            return @"H264";
        case TSStreamTypeH265:
            return @"H265";
        case TSStreamTypePrivateData:
            return [NSString stringWithFormat:@"Private: '%@'", [TSAccessUnit descriptorTagDescription:descriptorTag]];
    }
    
    return [NSString stringWithFormat:@"Unknown '0x%02x'", streamType];
}

+(NSString*)descriptorTagDescription:(TSDescriptorTag)descriptorTag
{
    switch (descriptorTag) {
        case TSDescriptorTagUnknown: return @"Unknown";
        case TSDescriptorTagVideoStream: return @"Video";
        case TSDescriptorTagAudioStream: return @"Audio";
            // FIXME MG: Parse and read format_identifier
        case TSDescriptorTagRegistration: return @"Registration";
        case TSDescriptorTagISO639Language: return @"ISO639Language";
        case TSDescriptorTagMaximumBitrate: return @"Maximum bitrate";
        case TSDescriptorTagStreamIdentifier: return @"Stream Identifier";
        case TSDescriptorTagTeletext: return @"Telextext";
        case TSDescriptorTagAc3: return @"AC3";
        case TSDescriptorTagEnhancedAc3: return @"EAC3";
        case TSDescriptorTagAac: return @"AAC";
            // FIXME MG: 0x7F indicate an extension_descriptor, i.e you need to check the next byte (descriptor_tag_extension). Could be AC4
        case TSDescriptorTagExtension: return @"Extension";
    }
    return [NSString stringWithFormat:@"Unknown '0x%02x'", descriptorTag];
}

/// The stream_id may be set to any valid value which correctly describes the elementary stream type as defined in Table 2-22.
/// See "Rec. ITU-T H.222.0 (03/2017)"
/// section "Table 2-22 – Stream_id assignments"      page 40
+(uint8_t)streamIdFromStreamType:(TSStreamType)streamType
{
    switch (streamType) {
        case TSStreamTypeADTSAAC:
            // ISO/IEC 13818-3 or ISO/IEC 11172-3 or ISO/IEC 13818-7 or ISO/IEC 14496-3 audio stream number x xxxx
            // 110X XXXX, where X can be 0 or 1 (doesn't matter) = 0xC0
            return 0xC0;
            
        case TSStreamTypeH264:
            // Rec. ITU-T H.262 | ISO/IEC 13818-2, ISO/IEC 11172-2, ISO/IEC 14496-2 or Rec. ITU-T H.264 | ISO/IEC 14496-10 video stream number xxxx
            // 1110 XXXX, where X can be 0 or 1 (doesn't matter) = 0xE0
            return 0xE0;
            
        case TSStreamTypeH265:
            // FIXME: What stream type to use for HEVC?
            return 0xE0;
            
        case TSStreamTypePrivateData:
            // FIXME MG: Return correct streamId when muxing stream type PrivateData here... 
            return 0x00;
    }
}

-(uint8_t)streamId
{
    [TSAccessUnit streamIdFromStreamType:self.streamType];
}

@end
