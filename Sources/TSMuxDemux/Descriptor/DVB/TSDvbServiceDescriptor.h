//
//  TSDvbServiceDescriptor.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "../TSDescriptor.h"

typedef NS_ENUM(uint8_t, TSDvbServiceDescriptorServiceType) {
    TSDvbServiceDescriptorServiceTypeReservedForFutureUse1 = 0x00,
    TSDvbServiceDescriptorServiceTypeDigitalTelevisionService = 0x01,
    TSDvbServiceDescriptorServiceTypeDigitalRadioSoundService = 0x02,
    TSDvbServiceDescriptorServiceTypeTeletextService = 0x03,
    TSDvbServiceDescriptorServiceTypeNVODReferenceService = 0x04,
    TSDvbServiceDescriptorServiceTypeNVODTimeshiftedService = 0x05,
    TSDvbServiceDescriptorServiceTypeMosaicService = 0x06,
    TSDvbServiceDescriptorServiceTypeFMRadioService = 0x07,
    TSDvbServiceDescriptorServiceTypeDVBSRMService = 0x08,
    TSDvbServiceDescriptorServiceTypeReservedForFutureUse2 = 0x09,
    TSDvbServiceDescriptorServiceTypeAdvancedCodedDigitalRadioSoundService = 0x0A,
    TSDvbServiceDescriptorServiceTypeAVCMosaicService = 0x0B,
    TSDvbServiceDescriptorServiceTypeDataBroadcastService = 0x0C,
    TSDvbServiceDescriptorServiceTypeReservedforCIUsage = 0x0D,
    TSDvbServiceDescriptorServiceTypeRCSMap = 0x0E,
    TSDvbServiceDescriptorServiceTypeRCSForwardLinkSignalling = 0x0F,
    TSDvbServiceDescriptorServiceTypeDVBMHPService = 0x10,
    TSDvbServiceDescriptorServiceTypeMPEG2HDDigitalTelevisionService = 0x11,
    // 0x12 - 0x15 reserved for future use
    TSDvbServiceDescriptorServiceTypeAVCSDDigitalTelevisionService = 0x16,
    TSDvbServiceDescriptorServiceTypeAVCSDNVODTimeshiftedService = 0x17,
    TSDvbServiceDescriptorServiceTypeAVCSDNVODReferenceService = 0x18,
    TSDvbServiceDescriptorServiceTypeAVCHDDigitalTelevisionService = 0x19,
    TSDvbServiceDescriptorServiceTypeAVCHDNVODTimeshiftedService = 0x1A,
    TSDvbServiceDescriptorServiceTypeAVCHDNVODReferenceService = 0x1B,
    TSDvbServiceDescriptorServiceTypeAVCFrameCompatiblePlanoStereoscopicHDDigitalTelevisionService = 0x1C,
    TSDvbServiceDescriptorServiceTypeAVCFrameCompatiblePlanoStereoscopicHDNVODTimeshiftedservice = 0x1D,
    TSDvbServiceDescriptorServiceTypeAVCFrameCompatiblePlanoStereoscopicHDNVODReferenceService = 0x1E,
    TSDvbServiceDescriptorServiceTypeHEVCDigitalTelevisionService = 0x1F,
    TSDvbServiceDescriptorServiceTypeHEVCUHDDigitalTelevisionService = 0x20,
    // 0x21 - 0x7F reserved for future use
    // 0x80 - 0xFE user defined
    // 0xFF reserved for future use
    
};

@interface TSDvbServiceDescriptor: TSDescriptor

@property(nonatomic, readonly) uint8_t serviceType;
@property(nonatomic, readonly, nullable) NSData *serviceProviderName;
@property(nonatomic, readonly, nullable) NSData *serviceName;

-(instancetype _Nonnull)initWithTag:(uint8_t)tag
                            payload:(NSData* _Nonnull)payload
                             length:(NSUInteger)length;

@end
