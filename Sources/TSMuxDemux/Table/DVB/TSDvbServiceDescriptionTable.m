//
//  TSDvbServiceDescriptionTable.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2025-03-23.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSDvbServiceDescriptionTable.h"
#import "../../TSElementaryStream.h"
#import "../../Descriptor/TSDescriptor.h"
#import "../../Descriptor/TSRegistrationDescriptor.h"

@interface TSDvbServiceDescriptionEntry()
-(instancetype)initWithServiceId:(uint16_t)serviceId
                 eitScheduleFlag:(BOOL)eitScheduleFlag
         eitPresentFollowingFlag:(BOOL)eitPresentFollowingFlag
                   runningStatus:(uint8_t)runningStatus
                      freeCaMode:(BOOL)freeCaMode
                     descriptors:(NSArray<TSDescriptor*> * _Nullable)descriptors;
@end

@implementation TSDvbServiceDescriptionEntry

-(instancetype)initWithServiceId:(uint16_t)serviceId
                 eitScheduleFlag:(BOOL)eitScheduleFlag
         eitPresentFollowingFlag:(BOOL)eitPresentFollowingFlag
                   runningStatus:(uint8_t)runningStatus
                      freeCaMode:(BOOL)freeCaMode
                     descriptors:(NSArray<TSDescriptor*> * _Nullable)descriptors
{
    self = [super init];
    if (self) {
        _serviceId = serviceId;
        _eitScheduleFlag = eitScheduleFlag;
        _eitPresentFollowingFlag = eitPresentFollowingFlag;
        _runningStatus = runningStatus;
        _freeCaMode = freeCaMode;
        _descriptors = descriptors;
    }
    return self;
}


-(BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[TSDvbServiceDescriptionEntry class]]) {
        return NO;
    }
    return [self isEqualToDvbSDTEntry:(TSDvbServiceDescriptionEntry*)object];
}

-(BOOL)isEqualToDvbSDTEntry:(TSDvbServiceDescriptionEntry*)e
{
    if (self.serviceId != e.serviceId) {
        return NO;
    }
    if (self.eitScheduleFlag != e.eitScheduleFlag) {
        return NO;
    }
    if (self.eitPresentFollowingFlag != e.eitPresentFollowingFlag) {
        return NO;
    }
    if (self.runningStatus != e.runningStatus) {
        return NO;
    }
    if (self.freeCaMode != e.freeCaMode) {
        return NO;
    }
    if (self.descriptors.count != e.descriptors.count) {
        return NO;
    }
    for (NSUInteger i=0; i < self.descriptors.count; ++i) {
        TSDescriptor *d1 = self.descriptors[i];
        TSDescriptor *d2 = e.descriptors[i];
        if (d1.descriptorTag != d2.descriptorTag) {
            return NO;
        }
    }
    return YES;
}

-(NSString *)description
{
    NSMutableString *formattedDescriptors = [NSMutableString stringWithFormat:@"%@", @""];
    
    BOOL first = YES;
    for (TSDescriptor *d in self.descriptors) {
        if (!first) {
            [formattedDescriptors appendString:@", "];
        }
        [formattedDescriptors appendString:[d tagDescription]];
        first = NO;
    }
    
    return [NSString stringWithFormat:@"{ serviceId: %hu, EITSchedule: %hhd, EITPresentFollowing: %hhd, runningStatus: %u, freeCaMode: %hhd, descriptors: %@}",
            _serviceId,
            _eitScheduleFlag,
            _eitPresentFollowingFlag,
            _runningStatus,
            _freeCaMode,
            formattedDescriptors
    ];
}

@end

@implementation TSDvbServiceDescriptionTable

#pragma mark - Demuxer

-(instancetype _Nullable)initWithPSI:(TSProgramSpecificInformationTable* _Nonnull)psi
{
    if (!psi.sectionDataExcludingCrc || psi.sectionDataExcludingCrc.length == 0) {
        NSLog(@"SDT received PSI with no section data");
        return nil;
    }
    
    self = [super init];
    if (self) {
        _psi = psi;
    }
    return self;
}

-(uint16_t)transportStreamId
{
    return self.psi.byte4And5;
}

-(uint16)originalNetworkId
{
    uint16_t sdBytes6And7 = 0x0;
    [self.psi.sectionDataExcludingCrc getBytes:&sdBytes6And7 range:NSMakeRange(5, 2)];
    return CFSwapInt16BigToHost(sdBytes6And7);
}

-(NSArray<TSDvbServiceDescriptionEntry*> * _Nullable)entries
{
    NSUInteger offset = 8;
    NSMutableArray<TSDvbServiceDescriptionEntry*> *entries = [NSMutableArray array];
    
    while (offset < self.psi.sectionDataExcludingCrc.length) { // service description entry loop begin
        uint16_t bytes1And2 = 0x0;
        [self.psi.sectionDataExcludingCrc getBytes:&bytes1And2 range:NSMakeRange(offset, 2)];
        offset+=2;
        const uint16_t serviceId = CFSwapInt16BigToHost(bytes1And2);
        
        uint8_t byte3 = 0x0;
        [self.psi.sectionDataExcludingCrc getBytes:&byte3 range:NSMakeRange(offset, 1)];
        offset++;
        uint8_t reserved_future_use = (byte3 >> 2) & 0x3F;
        BOOL eitScheduleFlag = (byte3 >> 1) & 0x01;
        BOOL eitPresentFollowingFlag = byte3 & 0x01;
        
        uint16_t bytes4And5 = 0x0;
        [self.psi.sectionDataExcludingCrc getBytes:&bytes4And5 range:NSMakeRange(offset, 2)];
        bytes4And5 = CFSwapInt16BigToHost(bytes4And5);
        offset +=2;
        const uint8_t runningStatus = (bytes4And5 >> 13) & 0b00000111;
        const BOOL freeCAMode = (bytes4And5 >> 12) & 0b00000001;
        const uint16_t descriptorsLength = bytes4And5 & 0x0FFF;
        
        NSMutableArray<TSDescriptor*> *descriptors = nil;
        int remainingDescriptorsLength = descriptorsLength;
        if (descriptorsLength > 0) {
            descriptors = [NSMutableArray array];
            while (remainingDescriptorsLength > 0) { // descriptor loop begin
                uint8_t descriptorTag = 0x0;
                [self.psi.sectionDataExcludingCrc getBytes:&descriptorTag range:NSMakeRange(offset, 1)];
                offset++;
                remainingDescriptorsLength--;
                
                uint8_t descriptorLength = 0x0;
                [self.psi.sectionDataExcludingCrc getBytes:&descriptorLength range:NSMakeRange(offset, 1)];
                offset++;
                remainingDescriptorsLength--;
                
                NSData *descriptorPayload = descriptorLength > 0
                ? [NSData dataWithBytesNoCopy:(void*)[self.psi.sectionDataExcludingCrc bytes] + offset
                                       length:descriptorLength
                                 freeWhenDone:NO]
                : nil;
                TSDescriptor *esDescriptor = [TSDescriptor makeWithTag:descriptorTag
                                                                length:descriptorLength
                                                                  data:descriptorPayload];
                offset += descriptorLength;
                remainingDescriptorsLength -= descriptorLength;
                [descriptors addObject:esDescriptor];
            } // descriptor loop end
        }
        
        TSDvbServiceDescriptionEntry *entry = [[TSDvbServiceDescriptionEntry alloc] initWithServiceId:serviceId
                                                                                      eitScheduleFlag:eitScheduleFlag
                                                                              eitPresentFollowingFlag:eitPresentFollowingFlag
                                                                                        runningStatus:runningStatus
                                                                                           freeCaMode:freeCAMode
                                                                                          descriptors:descriptors];
        [entries addObject:entry];
    }  // service description entry loop end
    
    return entries;
}


#pragma mark - Overridden

-(BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[TSDvbServiceDescriptionTable class]]) {
        return NO;
    }
    return [self isEqualToDvbSDT:(TSDvbServiceDescriptionTable*)object];
}

-(BOOL)isEqualToDvbSDT:(TSDvbServiceDescriptionTable*)sdt
{
    return self.transportStreamId == sdt.transportStreamId
    && self.originalNetworkId == sdt.originalNetworkId
    && self.psi.versionNumber == sdt.psi.versionNumber
    && [self.entries isEqual:sdt.entries];
}


-(NSString*)description
{
    return [NSString stringWithFormat:
                @"{ v: %u, tsId: %hu, oni: %hu, entries: [%@] }",
            self.psi.versionNumber,
            self.transportStreamId,
            self.originalNetworkId,
            self.entries
    ];
}


@end
