//
//  TSAccessUnit.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
@class TSPacket;

// Descriptor tags defined in ISO/IEC 13818-1 / ITU-T H.222.0
// https://en.wikipedia.org/wiki/Program-specific_information#Elementary_stream_types
typedef NS_ENUM(uint8_t, TSStreamType) {
    // TSStreamTypePrivateData type of data is determined by descriptor tags (TSDescriptorTag)
    TSStreamTypePrivateData = 0x06,
    TSStreamTypeADTSAAC = 0x0f,
    TSStreamTypeH264 = 0x1b,
    TSStreamTypeH265 = 0x24,
};


// Descriptor tags defined in ISO/IEC 13818-1 / ITU-T H.222.0
typedef NS_ENUM(uint8_t, TSH2220DescriptorTag) {
    TSDescriptorTagReserved                             = 0,
    TSDescriptorTagForbidden                            = 1,
    TSDescriptorTagVideoStream                          = 2,
    TSDescriptorTagAudioStream                          = 3,
    TSDescriptorTagHierarchy                            = 4,
    TSDescriptorTagRegistration                         = 5,
    TSDescriptorTagDataStreamAlignment                  = 6,
    TSDescriptorTagTargetBackgroundGrid                 = 7,
    TSDescriptorTagVideoWindow                          = 8,
    TSDescriptorTagCA                                   = 9,
    TSDescriptorTagISO639Language                       = 10,
    TSDescriptorTagSystemClock                          = 11,
    TSDescriptorTagMultiplexBufferUtilization           = 12,
    TSDescriptorTagCopyright                            = 13,
    TSDescriptorTagMaximumBitrate                       = 14,
    TSDescriptorTagPrivateDataIndicator                 = 15,
    TSDescriptorTagSmoothingBuffer                      = 16,
    TSDescriptorTagSTD                                  = 17,
    TSDescriptorTagIBP                                  = 18,
                                                        // TODO: 19-26 (0x13-0x1A): Defined in ISO/IEC 13818-6
    TSDescriptorTagMPEG4Video                           = 27,
    TSDescriptorTagMPEG4Audio                           = 28,
    TSDescriptorTagIOD                                  = 29,
    TSDescriptorTagSL                                   = 30,
    TSDescriptorTagFMC                                  = 31,
    TSDescriptorTagExternalESId                         = 32,
    TSDescriptorTagMuxCode                              = 33,
    TSDescriptorTagFmxBufferSize                        = 34,
    TSDescriptorTagMultiplexBuffer                      = 35,
    TSDescriptorTagContentLabeling                      = 36,
    TSDescriptorTagMetadataPointer                      = 37,
    TSDescriptorTagMetadata                             = 38,
    TSDescriptorTagMetadataSTD                          = 39,
    TSDescriptorTagAVCVideo                             = 40,
    TSDescriptorTagIPMP                                 = 41, // Defined in ISO/IEC 13818-11, MPEG-2 IPMP
    TSDescriptorTagAVCTimingAndHRD                      = 42,
    TSDescriptorTagMPEG2AACAudio                        = 43,
    TSDescriptorTagFlexMuxTiming                        = 44,
    TSDescriptorTagMPEG4Text                            = 45,
    TSDescriptorTagMPEG4AudioExtension                  = 46,
    TSDescriptorTagAuxiliaryVideoStream                 = 47,
    TSDescriptorTagSVCExtension                         = 48,
    TSDescriptorTagMVCExtension                         = 49,
    TSDescriptorTagJ2KVideo                             = 50,
    TSDescriptorTagMVCOperationPoint                    = 51,
    TSDescriptorTagMPEG2StereoscopicVideoFormat         = 52,
    TSDescriptorTagStereoscopicProgramInfo              = 53,
    TSDescriptorTagStereoscopicVideoInfo                = 54,
    TSDescriptorTagTransportProfile                     = 55,
    TSDescriptorTagHEVCVideo                            = 56,
    TSDescriptorTagVVCVideo                             = 57,
    TSDescriptorTagEVCVideo                             = 58,
    TSDescriptorTagReserved59                           = 59,
    TSDescriptorTagReserved60                           = 60,
    TSDescriptorTagReserved61                           = 61,
    TSDescriptorTagReserved62                           = 62,
    TSDescriptorTagExtension                            = 63,
    // 64-255: User Private
};

// Descriptor tags defined in ETSI EN 300 468
typedef NS_ENUM(uint8_t, TSDvbDescriptorTag) {
    TSDvbDescriptorTagNetworkName                       = 0x40, // 64
    TSDvbDescriptorTagServiceList                       = 0x41,
    TSDvbDescriptorTagStuffing                          = 0x42,
    TSDvbDescriptorTagSatelliteDeliverySystem           = 0x43,
    TSDvbDescriptorTagCableDeliverySystem               = 0x44,
    TSDvbDescriptorTagVBIData                           = 0x45,
    TSDvbDescriptorTagVBITeletext                       = 0x46,
    TSDvbDescriptorTagBouquetName                       = 0x47,
    TSDvbDescriptorTagService                           = 0x48,
    TSDvbDescriptorTagCountryAvailability               = 0x49,
    TSDvbDescriptorTagLinkage                           = 0x4A,
    TSDvbDescriptorTagNVODReference                     = 0x4B,
    TSDvbDescriptorTagTimeShiftedService                = 0x4C,
    TSDvbDescriptorTagShortEvent                        = 0x4D,
    TSDvbDescriptorTagExtendedEvent                     = 0x4E,
    TSDvbDescriptorTagTimeShiftedEvent                  = 0x4F,
    TSDvbDescriptorTagComponent                         = 0x50,
    TSDvbDescriptorTagMosaic                            = 0x51,
    TSDvbDescriptorTagStreamIdentifier                  = 0x52,
    TSDvbDescriptorTagCAIdentifier                      = 0x53,
    TSDvbDescriptorTagContent                           = 0x54,
    TSDvbDescriptorTagParentalRating                    = 0x55,
    TSDvbDescriptorTagTeletext                          = 0x56,
    TSDvbDescriptorTagTelephone                         = 0x57,
    TSDvbDescriptorTagLocalTimeOffset                   = 0x58,
    TSDvbDescriptorTagSubtitling                        = 0x59,
    TSDvbDescriptorTagTerrestrialDeliverySystem         = 0x5A,
    TSDvbDescriptorTagMultilingualNetworkName           = 0x5B,
    TSDvbDescriptorTagMultilingualBouquetName           = 0x5C,
    TSDvbDescriptorTagMultilingualServiceName           = 0x5D,
    TSDvbDescriptorTagMultilingualComponent             = 0x5E,
    TSDvbDescriptorTagPrivateDataSpecifier              = 0x5F,
    TSDvbDescriptorTagServiceMove                       = 0x60,
    TSDvbDescriptorTagShortSmoothingBuffer              = 0x61,
    TSDvbDescriptorTagFrequencyList                     = 0x62,
    TSDvbDescriptorTagPartialTransportStream            = 0x63,
    TSDvbDescriptorTagDataBroadcast                     = 0x64,
    TSDvbDescriptorTagScrambling                        = 0x65,
    TSDvbDescriptorTagDataBroadcastId                   = 0x66,
    TSDvbDescriptorTagTransportStream                   = 0x67,
    TSDvbDescriptorTagDSNG                              = 0x68,
    TSDvbDescriptorTagPDC                               = 0x69,
    TSDvbDescriptorTagAC3                               = 0x6A,
    TSDvbDescriptorTagAncillaryData                     = 0x6B,
    TSDvbDescriptorTagCellList                          = 0x6C,
    TSDvbDescriptorTagCellFrequencyLink                 = 0x6D,
    TSDvbDescriptorTagAnnouncementSupport               = 0x6E,
    TSDvbDescriptorTagApplicationSignalling             = 0x6F,
    TSDvbDescriptorTagAdaptationFieldData               = 0x70,
    TSDvbDescriptorTagServiceIdentifier                 = 0x71,
    TSDvbDescriptorTagServiceAvailability               = 0x72,
    TSDvbDescriptorTagDefaultAuthority                  = 0x73,
    TSDvbDescriptorTagRelatedContent                    = 0x74,
    TSDvbDescriptorTagTVAId                             = 0x75,
    TSDvbDescriptorTagContentIdentifier                 = 0x76,
    TSDvbDescriptorTagTimeSliceFecIdentifier            = 0x77,
    TSDvbDescriptorTagECMRepetitionRate                 = 0x78,
    TSDvbDescriptorTagS2SatelliteDeliverySystem         = 0x79,
    TSDvbDescriptorTagEnhancedAC3                       = 0x7A,
    TSDvbDescriptorTagDTS                               = 0x7B,
    TSDvbDescriptorTagAAC                               = 0x7C,
    TSDvbDescriptorTagXAITLocation                      = 0x7D,
    TSDvbDescriptorTagFTAContentManagement              = 0x7E,
    TSDvbDescriptorTagExtension                         = 0x7F, // Need to check the next byte (descriptor_tag_extension)
                                                        // User defined 0x80 - 0xFE (128 - 254)
                                                        // 0xFF Reserved for future use
};

typedef NS_ENUM(uint8_t, TSExtensionDescriptorTag) {
    TSExtensionDescriptorTagAc4 = 0x15,
};


/// See "Rec. ITU-T H.222.0 (03/2017)"
/// section "2.4.3.6 PES packet" page 37
@interface TSAccessUnit: NSObject

@property(nonatomic, readonly) uint16_t pid;

/// Set to kCMTimeInvalid to represent "No PTS".
@property(nonatomic, readonly) CMTime pts;

/// Set to kCMTimeInvalid to represent "No DTS".
@property(nonatomic, readonly) CMTime dts;

/// Set to true if the ts packet is flagged as discontinuous. Should be used as a hint to e.g. reset PTS-anchors etc.
@property(nonatomic, readonly) BOOL isDiscontinuous;

@property(nonatomic, readonly) TSStreamType streamType;
@property(nonatomic, readonly) uint8_t descriptorTag;

@property(nonatomic, readonly, nonnull) NSData *compressedData;

-(instancetype _Nonnull)initWithPid:(uint16_t)pid
                                pts:(CMTime)pts
                                dts:(CMTime)dts
                    isDiscontinuous:(BOOL)isDiscontinuous
                         streamType:(TSStreamType)streamType
                         descriptorTag:(uint8_t)descriptorTag
                     compressedData:(NSData* _Nonnull)compressedData;

/// Creates a PES-packet from the received ts packet.
+(instancetype _Nullable)initWithTsPacket:(TSPacket* _Nonnull)packet
                                      pid:(uint16_t)pid
                               streamType:(TSStreamType)streamType
                            descriptorTag:(uint8_t)descriptorTag;


/// Creates a PES-packet from the access unit.
/// Converts the pts and dts to the MPEG-TS timescale.
-(NSData* _Nonnull)toTsPacketPayload;

-(BOOL)isAudioStreamType;
+(BOOL)isAudioStreamType:(TSStreamType)streamType descriptorTag:(uint8_t)descriptorTag;

-(BOOL)isVideoStreamType;
+(BOOL)isVideoStreamType:(TSStreamType)streamType;

-(NSString* _Nonnull)streamTypeDescription;
+(NSString* _Nonnull)streamTypeDescription:(TSStreamType)streamType descriptorTag:(uint8_t)descriptorTag;

@end
