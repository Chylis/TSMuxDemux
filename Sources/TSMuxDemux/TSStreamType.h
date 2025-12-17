//
//  TSStreamType.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TSDescriptor;


/// Raw stream_type values for muxing. Use TSResolvedStreamType for demuxing/codec identification.
extern const uint8_t kRawStreamTypeH264;      // 0x1B - ITU-T H.264 / AVC
extern const uint8_t kRawStreamTypeADTSAAC;   // 0x0F - ISO/IEC 13818-7 AAC with ADTS

/// Resolved elementary stream content format, derived from raw PMT stream_type and descriptors.
/// Identifies what format/codec the stream contains, regardless of signaling method
/// (e.g. AC-3 can be signaled via ATSC stream_type 0x81 or DVB privateData + descriptor).
typedef NS_ENUM(NSUInteger, TSResolvedStreamType) {
    TSResolvedStreamTypeUnknown,
    // Audio codecs
    TSResolvedStreamTypeMPEG1Audio,    // MPEG-1 Audio Layer I, II, III
    TSResolvedStreamTypeMPEG2Audio,    // MPEG-2 Audio
    TSResolvedStreamTypeAAC_ADTS,      // AAC with ADTS transport
    TSResolvedStreamTypeAAC_LATM,      // AAC with LATM transport
    TSResolvedStreamTypeAC3,           // Dolby Digital (ATSC 0x81 or DVB 0x06+descriptor)
    TSResolvedStreamTypeEAC3,          // Dolby Digital Plus (ATSC 0x87 or DVB 0x06+descriptor)
    TSResolvedStreamTypeSMPTE302M,     // AES3/BSSD audio
    // Video codecs
    TSResolvedStreamTypeMPEG2Video,    // MPEG-2 Video (ISO/IEC 13818-2)
    TSResolvedStreamTypeH264,          // AVC / H.264
    TSResolvedStreamTypeH265,          // HEVC / H.265
    // Data formats
    TSResolvedStreamTypeSCTE35,        // SCTE-35 splice info
    TSResolvedStreamTypeTeletext,      // DVB Teletext (0x06+descriptor 0x56 or 0x46)
    TSResolvedStreamTypeSubtitles,     // DVB Subtitles (0x06+descriptor 0x59)
};

/// Utility class for resolving elementary stream content format from MPEG-TS stream_type and descriptors.
@interface TSStreamType : NSObject

/// Derives the resolved stream type from a raw stream_type value and optional descriptors.
/// For example, privateData (0x06) with an AC-3 descriptor returns TSResolvedStreamTypeAC3.
+(TSResolvedStreamType)resolveStreamType:(uint8_t)streamType
                             descriptors:(NSArray<TSDescriptor*>* _Nullable)descriptors;

/// Returns a human-readable description of the resolved stream type.
+(NSString* _Nonnull)descriptionForResolvedStreamType:(TSResolvedStreamType)resolvedStreamType;

/// Returns YES if the resolved stream type represents an audio codec.
+(BOOL)isAudio:(TSResolvedStreamType)resolvedStreamType;

/// Returns YES if the resolved stream type represents a video codec.
+(BOOL)isVideo:(TSResolvedStreamType)resolvedStreamType;

/// Returns the PES stream_id for a given raw stream type.
/// See ITU-T H.222.0 Table 2-22 "Stream_id assignments"
+(uint8_t)streamIdFromStreamType:(uint8_t)streamType;

@end
