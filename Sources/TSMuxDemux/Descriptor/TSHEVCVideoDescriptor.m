//
//  TSHEVCVideoDescriptor.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2025-12-18.
//  Copyright © 2025 Magnus Makes Software. All rights reserved.
//

#import "TSHEVCVideoDescriptor.h"

@implementation TSHEVCVideoDescriptor

-(instancetype _Nonnull)initWithTag:(uint8_t)tag
                            payload:(NSData* _Nonnull)payload
                             length:(NSUInteger)length
{
    self = [super initWithTag:tag length:length];
    if (self) {
        if (!payload || payload.length < 13 || length < 13) {
            NSLog(@"HEVC video descriptor too short: %lu bytes", (unsigned long)length);
            return self;
        }

        if (length != payload.length) {
            NSLog(@"HEVC video descriptor length mismatch: declared %lu, payload %lu bytes",
                  (unsigned long)length, (unsigned long)payload.length);
        }

        const uint8_t *bytes = payload.bytes;
        NSUInteger offset = 0;

        // Byte 0: profile_space (2) + tier_flag (1) + profile_idc (5)
        uint8_t byte0 = bytes[offset++];
        _profileSpace = (byte0 >> 6) & 0x03;
        _tierFlag = (byte0 >> 5) & 0x01;
        _profileIDC = byte0 & 0x1F;

        // Bytes 1-4: profile_compatibility_indication (32 bits, big-endian)
        _profileCompatibilityIndication = ((uint32_t)bytes[offset] << 24)
                                        | ((uint32_t)bytes[offset + 1] << 16)
                                        | ((uint32_t)bytes[offset + 2] << 8)
                                        | (uint32_t)bytes[offset + 3];
        offset += 4;

        // Byte 5: progressive_source (1) + interlaced_source (1) + non_packed_constraint (1)
        //         + frame_only_constraint (1) + copied_44bits[43:40] (4)
        uint8_t byte5 = bytes[offset++];
        _progressiveSourceFlag = (byte5 >> 7) & 0x01;
        _interlacedSourceFlag = (byte5 >> 6) & 0x01;
        _nonPackedConstraintFlag = (byte5 >> 5) & 0x01;
        _frameOnlyConstraintFlag = (byte5 >> 4) & 0x01;
        // Skip copied_44bits[43:40] in lower 4 bits

        // Bytes 6-10: copied_44bits[39:0] - skip these 5 bytes (reserved/constraint bits)
        offset += 5;

        // Byte 11: level_idc (8 bits)
        _levelIDC = bytes[offset++];

        // Byte 12: temporal_layer_subset_flag (1) + HEVC_still_present (1)
        //          + HEVC_24hr_picture_present (1) + sub_pic_hrd_params_not_present (1)
        //          + reserved (2) + HDR_WCG_idc (2)
        uint8_t byte12 = bytes[offset++];
        _temporalLayerSubsetFlag = (byte12 >> 7) & 0x01;
        _HEVCStillPresentFlag = (byte12 >> 6) & 0x01;
        _HEVC24HrPicturePresentFlag = (byte12 >> 5) & 0x01;
        _subPicHrdParamsNotPresent = (byte12 >> 4) & 0x01;
        // bits [3:2] reserved
        _HDRWCGIdc = byte12 & 0x03;

        // Optional: temporal_id_min/max if temporal_layer_subset_flag is set
        // Per ITU-T H.222.0 (ISO/IEC 13818-1) Table 2-97 HEVC_video_descriptor:
        // https://www.itu.int/rec/T-REC-H.222.0
        if (_temporalLayerSubsetFlag && length >= 15 && payload.length >= 15) {
            // Byte 13: reserved (5) + temporal_id_min (3)
            _temporalIdMin = bytes[offset++] & 0x07;

            // Byte 14: reserved (5) + temporal_id_max (3)
            _temporalIdMax = bytes[offset++] & 0x07;
        }
    }

    return self;
}

-(BOOL)isEqual:(id)object
{
    if (self == object) return YES;
    if (![object isKindOfClass:[TSHEVCVideoDescriptor class]]) return NO;
    if (![super isEqual:object]) return NO;

    TSHEVCVideoDescriptor *other = (TSHEVCVideoDescriptor*)object;

    return self.profileSpace == other.profileSpace
        && self.tierFlag == other.tierFlag
        && self.profileIDC == other.profileIDC
        && self.profileCompatibilityIndication == other.profileCompatibilityIndication
        && self.progressiveSourceFlag == other.progressiveSourceFlag
        && self.interlacedSourceFlag == other.interlacedSourceFlag
        && self.nonPackedConstraintFlag == other.nonPackedConstraintFlag
        && self.frameOnlyConstraintFlag == other.frameOnlyConstraintFlag
        && self.levelIDC == other.levelIDC
        && self.temporalLayerSubsetFlag == other.temporalLayerSubsetFlag
        && self.HEVCStillPresentFlag == other.HEVCStillPresentFlag
        && self.HEVC24HrPicturePresentFlag == other.HEVC24HrPicturePresentFlag
        && self.subPicHrdParamsNotPresent == other.subPicHrdParamsNotPresent
        && self.HDRWCGIdc == other.HDRWCGIdc
        && self.temporalIdMin == other.temporalIdMin
        && self.temporalIdMax == other.temporalIdMax;
}

-(NSUInteger)hash
{
    return [super hash]
        ^ self.profileSpace
        ^ self.profileIDC
        ^ self.profileCompatibilityIndication
        ^ self.levelIDC
        ^ self.HDRWCGIdc;
}

-(NSString*)description
{
    return [self tagDescription];
}

-(NSString*)tagDescription
{
    NSString *scanType = @"unknown";
    if (self.progressiveSourceFlag && !self.interlacedSourceFlag) {
        scanType = @"progressive";
    } else if (!self.progressiveSourceFlag && self.interlacedSourceFlag) {
        scanType = @"interlaced";
    } else if (self.progressiveSourceFlag && self.interlacedSourceFlag) {
        scanType = @"mixed";
    }

    NSString *hdrWcg;
    switch (self.HDRWCGIdc) {
        case 0: hdrWcg = @"SDR"; break;
        case 1: hdrWcg = @"SDR+WCG"; break;
        case 2: hdrWcg = @"HDR+WCG"; break;
        case 3: hdrWcg = @"no indication"; break;
        default: hdrWcg = @"reserved"; break;
    }

    NSString *tier = self.tierFlag ? @"High" : @"Main";

    return [NSString stringWithFormat:@"HEVC: profile=%u tier=%@ level=%u scan=%@ hdr=%@",
            self.profileIDC, tier, self.levelIDC, scanType, hdrWcg];
}

@end
