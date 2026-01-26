//
//  TSDvbServiceDescriptor.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSDvbServiceDescriptor.h"
#import "../../TSStringEncodingUtil.h"
#import "../../TSLog.h"
#import "../../TSBitReader.h"

@implementation TSDvbServiceDescriptor

-(instancetype _Nullable)initWithTag:(uint8_t)tag
                             payload:(NSData *)payload
                              length:(NSUInteger)length
{
    self = [super initWithTag:tag length:length];
    if (self) {
        if (payload.length && length > 0) {
            TSBitReader reader = TSBitReaderMake(payload);

            _serviceType = TSBitReaderReadUInt8(&reader);
            if (reader.error) {
                TSLogWarn(@"DVB service descriptor truncated: missing service_type");
                return nil;
            }

            uint8_t serviceProviderNameLength = TSBitReaderReadUInt8(&reader);
            if (reader.error) {
                TSLogWarn(@"DVB service descriptor truncated: missing service_provider_name_length");
                return nil;
            }
            if (serviceProviderNameLength > 0) {
                _serviceProviderName = [TSBitReaderReadData(&reader, serviceProviderNameLength) copy];
                if (reader.error) {
                    TSLogWarn(@"DVB service descriptor truncated: service_provider_name needs %u bytes",
                              serviceProviderNameLength);
                    return nil;
                }
            }

            uint8_t serviceNameLength = TSBitReaderReadUInt8(&reader);
            if (reader.error) {
                TSLogWarn(@"DVB service descriptor truncated: missing service_name_length");
                return nil;
            }
            if (serviceNameLength > 0) {
                _serviceName = [TSBitReaderReadData(&reader, serviceNameLength) copy];
                if (reader.error) {
                    TSLogWarn(@"DVB service descriptor truncated: service_name needs %u bytes",
                              serviceNameLength);
                    return nil;
                }
            }
        } else {
            TSLogWarn(@"Received DVB service descriptor with no payload");
            return nil;
        }
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
    if (![super isEqual:object]) {
        return NO;
    }
    TSDvbServiceDescriptor *other = (TSDvbServiceDescriptor*)object;
    if (self.serviceType != other.serviceType) {
        return NO;
    }
    if (self.serviceProviderName != other.serviceProviderName &&
        ![self.serviceProviderName isEqual:other.serviceProviderName]) {
        return NO;
    }
    if (self.serviceName != other.serviceName &&
        ![self.serviceName isEqual:other.serviceName]) {
        return NO;
    }
    return YES;
}

-(NSUInteger)hash
{
    return [super hash] ^ self.serviceType ^ self.serviceProviderName.hash ^ self.serviceName.hash;
}

-(NSString*)description
{
    return [self tagDescription];
}

-(NSString*)tagDescription
{
    return [NSString stringWithFormat:@"type: %@, service provider: %@, service: %@",
            [self serviceDescription] ?: [NSString stringWithFormat:@"%u", _serviceType],
            [TSStringEncodingUtil dvbStringFromCharData:self.serviceProviderName],
            [TSStringEncodingUtil dvbStringFromCharData:self.serviceName]
    ];
}

-(NSString*)serviceDescription
{
    
    switch (self.serviceType) {
        case TSDvbServiceDescriptorServiceTypeDigitalTelevisionService:
            return @"Digital Television";
        case TSDvbServiceDescriptorServiceTypeDigitalRadioSoundService:
            return @"Digital Radio Sound";
        case TSDvbServiceDescriptorServiceTypeTeletextService:
            return @"Telextext";
        case TSDvbServiceDescriptorServiceTypeNVODReferenceService:
            return @"NVOD Reference";
        case TSDvbServiceDescriptorServiceTypeNVODTimeshiftedService:
            return @"NVOD Timeshifted";
        case TSDvbServiceDescriptorServiceTypeMosaicService:
            return @"Mosaic";
        case TSDvbServiceDescriptorServiceTypeFMRadioService:
            return @"FM Radio";
        case TSDvbServiceDescriptorServiceTypeDVBSRMService:
            return @"SRM";
        case TSDvbServiceDescriptorServiceTypeAdvancedCodedDigitalRadioSoundService:
            return @"Advanced Coded Digital Radio Sound";
        case TSDvbServiceDescriptorServiceTypeAVCMosaicService:
            return @"AVC Mosaic";
        case TSDvbServiceDescriptorServiceTypeDataBroadcastService:
            return @"Data broadcast";
        case TSDvbServiceDescriptorServiceTypeReservedforCIUsage:
            return @"Reserved CI";
        case TSDvbServiceDescriptorServiceTypeRCSMap:
            return @"RCS Map";
        case TSDvbServiceDescriptorServiceTypeRCSForwardLinkSignalling:
            return @"RCS Forward Link Signalling";
        case TSDvbServiceDescriptorServiceTypeDVBMHPService:
            return @"Multimedia Home Platform";
        case TSDvbServiceDescriptorServiceTypeMPEG2HDDigitalTelevisionService:
            return @"MPEG-2HD Digital Television";
        case TSDvbServiceDescriptorServiceTypeAVCSDDigitalTelevisionService:
            return @"AVC SD Digital Television";
        case TSDvbServiceDescriptorServiceTypeAVCSDNVODTimeshiftedService:
            return @"AVC SDNVOD Timeshifted";
        case TSDvbServiceDescriptorServiceTypeAVCSDNVODReferenceService:
            return @"AVC SDNVOD Reference";
        case TSDvbServiceDescriptorServiceTypeAVCHDDigitalTelevisionService:
            return @"AVC HD Digital Television";
        case TSDvbServiceDescriptorServiceTypeAVCHDNVODTimeshiftedService:
            return @"AVC HDNVOD Timeshifted";
        case TSDvbServiceDescriptorServiceTypeAVCHDNVODReferenceService:
            return @"AVC HDNVOD Reference";
        case TSDvbServiceDescriptorServiceTypeAVCFrameCompatiblePlanoStereoscopicHDDigitalTelevisionService:
            return @"AVC Frame Compatible Plano-stereoscopic HD Digital Television";
        case TSDvbServiceDescriptorServiceTypeAVCFrameCompatiblePlanoStereoscopicHDNVODTimeshiftedservice:
            return @"AVC Frame Compatible Plano-stereoscopic HDNVOD Timeshifted ";
        case TSDvbServiceDescriptorServiceTypeAVCFrameCompatiblePlanoStereoscopicHDNVODReferenceService:
            return @"AVC Frame Compatible Plano-stereoscopic HDNVOD Reference";
        case TSDvbServiceDescriptorServiceTypeHEVCDigitalTelevisionService:
            return @"HEVC Digital Television";
        case TSDvbServiceDescriptorServiceTypeHEVCUHDDigitalTelevisionService:
            return @"HEVC UHD Digital Television";
    }
    
    return nil;
}

@end
