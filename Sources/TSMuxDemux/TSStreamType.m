//
//  TSStreamType.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSStreamType.h"
#import "TSConstants.h"
#import "Descriptor/TSDescriptor.h"
#import "Descriptor/TSRegistrationDescriptor.h"

#pragma mark - Raw stream type constants

// Public (for muxing)
const uint8_t kRawStreamTypeH264    = 0x1B; // ITU-T H.264 / AVC
const uint8_t kRawStreamTypeADTSAAC = 0x0F; // ISO/IEC 13818-7 AAC with ADTS

// ISO/IEC 13818-1 / ITU-T H.222.0 stream types (shared by DVB and ATSC)
static const uint8_t kRawStreamTypeMPEG2Video   = 0x02; // ISO/IEC 13818-2
static const uint8_t kRawStreamTypeMPEG1Audio   = 0x03; // ISO/IEC 11172-3
static const uint8_t kRawStreamTypeMPEG2Audio   = 0x04; // ISO/IEC 13818-3
static const uint8_t kRawStreamTypePrivateData  = 0x06; // PES private data
static const uint8_t kRawStreamTypeLATMAAC      = 0x11; // ISO/IEC 14496-3
static const uint8_t kRawStreamTypeH265         = 0x24; // ITU-T H.265

// ATSC A/53 stream types (user private range 0x80-0xFF)
static const uint8_t kRawStreamTypeATSC_AC3     = 0x81; // ATSC A/52 Dolby Digital
static const uint8_t kRawStreamTypeATSC_EAC3    = 0x87; // ATSC A/52 Dolby Digital Plus

// SCTE-35 stream types (user private range)
static const uint8_t kRawStreamTypeSCTE35       = 0x86; // Splice info

// Registration descriptor format identifiers (SMPTE RA registered)
static const uint32_t kFormatIdentifierBSSD     = 0x42535344; // ASCII: "BSSD" (AES3/SMPTE 302M)

#pragma mark - TSStreamType

@implementation TSStreamType

+(TSResolvedStreamType)resolveStreamType:(uint8_t)streamType
                             descriptors:(NSArray<TSDescriptor*>*)descriptors
{
    // Direct stream type mappings
    switch (streamType) {
        case kRawStreamTypeMPEG2Video:   return TSResolvedStreamTypeMPEG2Video;
        case kRawStreamTypeMPEG1Audio:   return TSResolvedStreamTypeMPEG1Audio;
        case kRawStreamTypeMPEG2Audio:   return TSResolvedStreamTypeMPEG2Audio;
        case kRawStreamTypeADTSAAC:      return TSResolvedStreamTypeAAC_ADTS;
        case kRawStreamTypeLATMAAC:      return TSResolvedStreamTypeAAC_LATM;
        case kRawStreamTypeH264:         return TSResolvedStreamTypeH264;
        case kRawStreamTypeH265:         return TSResolvedStreamTypeH265;
        case kRawStreamTypeATSC_AC3:     return TSResolvedStreamTypeAC3;
        case kRawStreamTypeATSC_EAC3:    return TSResolvedStreamTypeEAC3;
        case kRawStreamTypeSCTE35:       return TSResolvedStreamTypeSCTE35;
        default:
            break;
    }

    // DVB uses PrivateData (0x06) with descriptors to signal codec type
    if (streamType == kRawStreamTypePrivateData) {
        for (TSDescriptor *d in descriptors) {
            // Check Registration descriptor for known format identifiers
            if ([d isKindOfClass:[TSRegistrationDescriptor class]]) {
                TSRegistrationDescriptor *reg = (TSRegistrationDescriptor *)d;
                if (reg.formatIdentifier == kFormatIdentifierBSSD) {
                    return TSResolvedStreamTypeSMPTE302M;
                }
            }
            // Check DVB AC-3 descriptor (tag 0x6A)
            if (d.descriptorTag == TSDvbDescriptorTagAC3) {
                return TSResolvedStreamTypeAC3;
            }
            // Check DVB Enhanced AC-3 descriptor (tag 0x7A)
            if (d.descriptorTag == TSDvbDescriptorTagEnhancedAC3) {
                return TSResolvedStreamTypeEAC3;
            }
            // Check DVB Teletext descriptor (tag 0x56) or VBI Teletext (tag 0x46)
            if (d.descriptorTag == TSDvbDescriptorTagTeletext ||
                d.descriptorTag == TSDvbDescriptorTagVBITeletext) {
                return TSResolvedStreamTypeTeletext;
            }
            // Check DVB Subtitling descriptor (tag 0x59)
            if (d.descriptorTag == TSDvbDescriptorTagSubtitling) {
                return TSResolvedStreamTypeSubtitles;
            }
        }
    }

    return TSResolvedStreamTypeUnknown;
}

+(NSString*)descriptionForResolvedStreamType:(TSResolvedStreamType)resolvedStreamType
{
    switch (resolvedStreamType) {
        case TSResolvedStreamTypeUnknown:       return @"?";
        case TSResolvedStreamTypeMPEG1Audio:    return @"MPEG-1 A";
        case TSResolvedStreamTypeMPEG2Audio:    return @"MPEG-2 A";
        case TSResolvedStreamTypeAAC_ADTS:      return @"AAC (ADTS)";
        case TSResolvedStreamTypeAAC_LATM:      return @"AAC (LATM)";
        case TSResolvedStreamTypeAC3:           return @"AC-3";
        case TSResolvedStreamTypeEAC3:          return @"E-AC-3";
        case TSResolvedStreamTypeSMPTE302M:     return @"SMPTE 302M";
        case TSResolvedStreamTypeMPEG2Video:    return @"MPEG-2 V";
        case TSResolvedStreamTypeH264:          return @"H.264";
        case TSResolvedStreamTypeH265:          return @"H.265";
        case TSResolvedStreamTypeSCTE35:        return @"SCTE-35";
        case TSResolvedStreamTypeTeletext:      return @"Teletext";
        case TSResolvedStreamTypeSubtitles:     return @"Subtitles";
    }
    return @"?";
}

+(BOOL)isAudio:(TSResolvedStreamType)resolvedStreamType
{
    switch (resolvedStreamType) {
        case TSResolvedStreamTypeMPEG1Audio:
        case TSResolvedStreamTypeMPEG2Audio:
        case TSResolvedStreamTypeAAC_ADTS:
        case TSResolvedStreamTypeAAC_LATM:
        case TSResolvedStreamTypeAC3:
        case TSResolvedStreamTypeEAC3:
        case TSResolvedStreamTypeSMPTE302M:
            return YES;
        default:
            return NO;
    }
}

+(BOOL)isVideo:(TSResolvedStreamType)resolvedStreamType
{
    switch (resolvedStreamType) {
        case TSResolvedStreamTypeMPEG2Video:
        case TSResolvedStreamTypeH264:
        case TSResolvedStreamTypeH265:
            return YES;
        default:
            return NO;
    }
}

+(uint8_t)streamIdFromStreamType:(uint8_t)streamType
{
    // See ITU-T H.222.0 Table 2-22 "Stream_id assignments"
    switch (streamType) {
        case kRawStreamTypeMPEG1Audio:
        case kRawStreamTypeMPEG2Audio:
        case kRawStreamTypeADTSAAC:
        case kRawStreamTypeLATMAAC:
            // ISO audio stream: 110x xxxx = 0xC0
            return 0xC0;

        case kRawStreamTypeH264:
        case kRawStreamTypeH265:
            // Video stream: 1110 xxxx = 0xE0
            return 0xE0;

        default:
            // Private stream 1: 0xBD
            return 0xBD;
    }
}

@end
