//
//  TSDescriptor.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSDescriptor.h"

#import "TSRegistrationDescriptor.h"
#import "TSISO639LanguageDescriptor.h"
#import "DVB/TSDvbServiceDescriptor.h"
#import "SCTE35/TSScte35CueIdentifierDescriptor.h"
#import "ATSC/TSAtscServiceLocationDescriptor.h"

#pragma mark - TSDescriptor

@implementation TSDescriptor

+(instancetype _Nullable)makeWithTag:(uint8_t)tag
                              length:(uint8_t)length
                                data:(NSData * _Nullable)payload
{
    NSUInteger offset = 0;
    
    Class descriptorClass = nil;
    switch (tag) {
        case TSDescriptorTagRegistration:
            descriptorClass = [TSRegistrationDescriptor class];
            break;
        case TSDescriptorTagISO639Language:
            descriptorClass = [TSISO639LanguageDescriptor class];
            break;
        case TSDvbDescriptorTagService:
            descriptorClass = [TSDvbServiceDescriptor class];
            break;
        case TSScte35DescriptorTagCueIdentifier:
            descriptorClass = [TSScte35CueIdentifierDescriptor class];
            break;
        case TSAtscDescriptorTagServiceLocation:
            descriptorClass = [TSAtscServiceLocationDescriptor class];
            break;
    }
    if (descriptorClass) {
        return [[descriptorClass alloc] initWithTag:tag
                                            payload:payload
                                             length:length];
    }
    
    //NSLog(@"Received unimplemented descriptor tag %u - not parsing its payload", tag);
    return [[TSDescriptor alloc] initWithTag:tag length:length];
}

-(instancetype)initWithTag:(uint8_t)tag
                    length:(uint8_t)length
{
    self = [super init];
    if (self) {
        _descriptorTag = tag;
        _descriptorLength = length;
    }
    return self;
}

-(BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    if ([self class] != [object class]) {
        return NO;
    }
    TSDescriptor *other = (TSDescriptor*)object;
    return self.descriptorTag == other.descriptorTag
        && self.descriptorLength == other.descriptorLength;
}

-(NSUInteger)hash
{
    return self.descriptorTag ^ (self.descriptorLength << 8);
}

// FIXME MG: Remove this static func and delegate to subclass when all below descriptors are implemented
+(BOOL)isAudioDescriptor:(uint8_t)descriptorTag
{
    // FIXME MG: Could be AC4 - if TSDescriptorTagExtension: check the next byte (descriptor_tag_extension).
    return descriptorTag == TSDescriptorTagAudioStream
    || descriptorTag == TSDescriptorTagMPEG4Audio
    || descriptorTag == TSDescriptorTagMPEG2AACAudio
    || descriptorTag == TSDvbDescriptorTagAAC
    || descriptorTag == TSDvbDescriptorTagAC3
    || descriptorTag == TSDvbDescriptorTagEnhancedAC3;
}

-(NSString*)description
{
    return [self tagDescription];
}

-(NSString*)tagDescription
{
    return [TSDescriptor tagDescription:self.descriptorTag];
}

// FIXME MG: Remove this static func and delegate to subclass when all below descriptors are implemented
+(NSString*)tagDescription:(uint8_t)descriptorTag
{
    switch ((TSH2220DescriptorTag)descriptorTag) {
        case TSDescriptorTagReserved:
            return @"Reserved0";
        case TSDescriptorTagForbidden:
            return @"Forbidden";
        case TSDescriptorTagVideoStream:
            return @"Video stream";
        case TSDescriptorTagAudioStream:
            return @"Audio stream";
        case TSDescriptorTagHierarchy:
            return @"Hierarchy";
        case TSDescriptorTagRegistration:
            return @"Registration";
        case TSDescriptorTagDataStreamAlignment:
            return @"Data stream alignment";
        case TSDescriptorTagTargetBackgroundGrid:
            return @"Target background grid";
        case TSDescriptorTagVideoWindow:
            return @"video window";
        case TSDescriptorTagCA:
            return @"CA";
        case TSDescriptorTagISO639Language:
            return @"ISO639 language";
        case TSDescriptorTagSystemClock:
            return @"System clock";
        case TSDescriptorTagMultiplexBufferUtilization:
            return @"Multiplex buffer utilization";
        case TSDescriptorTagCopyright:
            return @"Copyright";
        case TSDescriptorTagMaximumBitrate:
            return @"Maximum bitrate";
        case TSDescriptorTagPrivateDataIndicator:
            return @"Private data indicator";
        case TSDescriptorTagSmoothingBuffer:
            return @"Smoothing buffer";
        case TSDescriptorTagSTD:
            return @"STD";
        case TSDescriptorTagIBP:
            return @"IBP";
        case TSDescriptorTagMPEG4Video:
            return @"MPEG-4 video";
        case TSDescriptorTagMPEG4Audio:
            return @"MPEG-4 audio";
        case TSDescriptorTagIOD:
            return @"IOD";
        case TSDescriptorTagSL:
            return @"SL";
        case TSDescriptorTagFMC:
            return @"FMC";
        case TSDescriptorTagExternalESId:
            return @"External ES id";
        case TSDescriptorTagMuxCode:
            return @"Mux code";
        case TSDescriptorTagFmxBufferSize:
            return @"Fmx buffer size";
        case TSDescriptorTagMultiplexBuffer:
            return @"Multiplex buffer";
        case TSDescriptorTagContentLabeling:
            return @"Content labeling";
        case TSDescriptorTagMetadataPointer:
            return @"Metadata pointer";
        case TSDescriptorTagMetadata:
            return @"Tag metadata";
        case TSDescriptorTagMetadataSTD:
            return @"Metadata STD";
        case TSDescriptorTagAVCVideo:
            return @"AVC video";
        case TSDescriptorTagIPMP:
            return @"IPMP";
        case TSDescriptorTagAVCTimingAndHRD:
            return @"AVC timing and HRD";
        case TSDescriptorTagMPEG2AACAudio:
            return @"MPEG-2 AAC audio";
        case TSDescriptorTagFlexMuxTiming:
            return @"Flex mux timing";
        case TSDescriptorTagMPEG4Text:
            return @"MPEG-4 text";
        case TSDescriptorTagMPEG4AudioExtension:
            return @"MPEG-4 audio extension";
        case TSDescriptorTagAuxiliaryVideoStream:
            return @"Auxiliary video stream";
        case TSDescriptorTagSVCExtension:
            return @"SVC extension";
        case TSDescriptorTagMVCExtension:
            return @"MVC extension";
        case TSDescriptorTagJ2KVideo:
            return @"J2K video";
        case TSDescriptorTagMVCOperationPoint:
            return @"MVC operation point";
        case TSDescriptorTagMPEG2StereoscopicVideoFormat:
            return @"MPEG-2 stereoscopic video format";
        case TSDescriptorTagStereoscopicProgramInfo:
            return @"Stereoscopic program info";
        case TSDescriptorTagStereoscopicVideoInfo:
            return @"Stereoscopic video info";
        case TSDescriptorTagTransportProfile:
            return @"Transport profile";
        case TSDescriptorTagHEVCVideo:
            return @"HEVC video";
        case TSDescriptorTagVVCVideo:
            return @"VVC video";
        case TSDescriptorTagEVCVideo:
            return @"EVC video";
        case TSDescriptorTagReserved59:
            return @"Reserved59";
        case TSDescriptorTagReserved60:
            return @"Reserved60";
        case TSDescriptorTagReserved61:
            return @"Reserved61";
        case TSDescriptorTagReserved62:
            return @"Reserved62";
        case TSDescriptorTagExtension:
            return @"Extension";
    }
    
    switch ((TSDvbDescriptorTag)descriptorTag) {
        case TSDvbDescriptorTagNetworkName:
            return @"Network name";
        case TSDvbDescriptorTagServiceList:
            return @"Service list";
        case TSDvbDescriptorTagStuffing:
            return @"Stuffing";
        case TSDvbDescriptorTagSatelliteDeliverySystem:
            return @"Satellite delivery system";
        case TSDvbDescriptorTagCableDeliverySystem:
            return @"Cable delivery system";
        case TSDvbDescriptorTagVBIData:
            return @"VBI data";
        case TSDvbDescriptorTagVBITeletext:
            return @"VBI teletext";
        case TSDvbDescriptorTagBouquetName:
            return @"Bouquet name";
        case TSDvbDescriptorTagService:
            return @"Service";
        case TSDvbDescriptorTagCountryAvailability:
            return @"Country availability";
        case TSDvbDescriptorTagLinkage:
            return @"Linkage";
        case TSDvbDescriptorTagNVODReference:
            return @"NVOD reference";
        case TSDvbDescriptorTagTimeShiftedService:
            return @"Time shifted service";
        case TSDvbDescriptorTagShortEvent:
            return @"Short event";
        case TSDvbDescriptorTagExtendedEvent:
            return @"Extended event";
        case TSDvbDescriptorTagTimeShiftedEvent:
            return @"Time shifted event";
        case TSDvbDescriptorTagComponent:
            return @"Component";
        case TSDvbDescriptorTagMosaic:
            return @"Mosaic";
        case TSDvbDescriptorTagStreamIdentifier:
            return @"Stream identifier";
        case TSDvbDescriptorTagCAIdentifier:
            return @"CA identifier";
        case TSDvbDescriptorTagContent:
            return @"Content";
        case TSDvbDescriptorTagParentalRating:
            return @"Parental rating";
        case TSDvbDescriptorTagTeletext:
            return @"Teletext";
        case TSDvbDescriptorTagTelephone:
            return @"Telephone";
        case TSDvbDescriptorTagLocalTimeOffset:
            return @"Local time offset";
        case TSDvbDescriptorTagSubtitling:
            return @"Subtitling";
        case TSDvbDescriptorTagTerrestrialDeliverySystem:
            return @"Terrestrial delivery system";
        case TSDvbDescriptorTagMultilingualNetworkName:
            return @"Multilingual network name";
        case TSDvbDescriptorTagMultilingualBouquetName:
            return @"Multilingual bouquet name";
        case TSDvbDescriptorTagMultilingualServiceName:
            return @"Multilingual service name";
        case TSDvbDescriptorTagMultilingualComponent:
            return @"Multilingual component";
        case TSDvbDescriptorTagPrivateDataSpecifier:
            return @"Private data specifier";
        case TSDvbDescriptorTagServiceMove:
            return @"Service move";
        case TSDvbDescriptorTagShortSmoothingBuffer:
            return @"Short smoothing buffer";
        case TSDvbDescriptorTagFrequencyList:
            return @"Frequency list";
        case TSDvbDescriptorTagPartialTransportStream:
            return @"Partial transport stream";
        case TSDvbDescriptorTagDataBroadcast:
            return @"Data broadcast";
        case TSDvbDescriptorTagScrambling:
            return @"Scrambling";
        case TSDvbDescriptorTagDataBroadcastId:
            return @"Data broadcast id";
        case TSDvbDescriptorTagTransportStream:
            return @"Transport stream";
        case TSDvbDescriptorTagDSNG:
            return @"DSNG";
        case TSDvbDescriptorTagPDC:
            return @"DPC";
        case TSDvbDescriptorTagAC3:
            return @"AC-3";
        case TSDvbDescriptorTagAncillaryData:
            return @"Ancillary data";
        case TSDvbDescriptorTagCellList:
            return @"Cell list";
        case TSDvbDescriptorTagCellFrequencyLink:
            return @"Cell frequency link";
        case TSDvbDescriptorTagAnnouncementSupport:
            return @"Announcement support";
        case TSDvbDescriptorTagApplicationSignalling:
            return @"Application signalling";
        case TSDvbDescriptorTagAdaptationFieldData:
            return @"Adaptation field data";
        case TSDvbDescriptorTagServiceIdentifier:
            return @"Service identifier";
        case TSDvbDescriptorTagServiceAvailability:
            return @"Service availability";
        case TSDvbDescriptorTagDefaultAuthority:
            return @"Default authority";
        case TSDvbDescriptorTagRelatedContent:
            return @"Related content";
        case TSDvbDescriptorTagTVAId:
            return @"TVA id";
        case TSDvbDescriptorTagContentIdentifier:
            return @"Content id";
        case TSDvbDescriptorTagTimeSliceFecIdentifier:
            return @"Time slice fec id";
        case TSDvbDescriptorTagECMRepetitionRate:
            return @"ECM repetition rate";
        case TSDvbDescriptorTagS2SatelliteDeliverySystem:
            return @"S2 satellite delivery system";
        case TSDvbDescriptorTagEnhancedAC3:
            return @"Enhanced AC-3";
        case TSDvbDescriptorTagDTS:
            return @"DTS";
        case TSDvbDescriptorTagAAC:
            return @"AAC";
        case TSDvbDescriptorTagXAITLocation:
            return @"XAIT location";
        case TSDvbDescriptorTagFTAContentManagement:
            return @"FTA content management";
        case TSDvbDescriptorTagExtension:
            return @"Extension";
    }
    
    switch ((TSScte35DescriptorTag)descriptorTag) {
        case TSScte35DescriptorTagCueIdentifier:
            return @"SCTE-35 Cue id";
    }
    
    switch ((TSST2038DescriptorTag)descriptorTag) {
        case TSST2038DescriptorTagAncData:
            return @"ST-2038 Anc data";
    }

    switch ((TSAtscDescriptorTag)descriptorTag) {
        case TSAtscDescriptorTagExtendedChannelName:
            return @"Extended channel name";
        case TSAtscDescriptorTagServiceLocation:
            return @"Service location";
        case TSAtscDescriptorTagTimeShiftedService:
            return @"Time-shifted service";
        case TSAtscDescriptorTagComponentName:
            return @"Component name";
        case TSAtscDescriptorTagContentAdvisory:
            return @"Content advisory";
    }

    return [NSString stringWithFormat:@"Private: 0x%02x", descriptorTag];
}

@end
