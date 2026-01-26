//
//  TSDvbServiceDescriptionTable.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2025-03-23.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSDvbServiceDescriptionTable.h"
#import "../../TSBitReader.h"
#import "../../TSElementaryStream.h"
#import "../../Descriptor/TSDescriptor.h"
#import "../../Descriptor/TSRegistrationDescriptor.h"
#import "../../TSLog.h"

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
        if (![d1 isEqual:d2]) {
            return NO;
        }
    }
    return YES;
}

-(NSUInteger)hash
{
    return _serviceId;
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
        TSLogWarn(@"SDT received PSI with no section data");
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

-(uint16_t)originalNetworkId
{
    TSBitReader reader = TSBitReaderMake(self.psi.sectionDataExcludingCrc);
    TSBitReaderSkip(&reader, 5);  // Skip first 5 bytes
    return TSBitReaderReadUInt16BE(&reader);
}

-(NSArray<TSDvbServiceDescriptionEntry*> * _Nullable)entries
{
    NSData *data = self.psi.sectionDataExcludingCrc;
    if (data.length < 8) {
        return @[];
    }

    TSBitReader reader = TSBitReaderMake(data);
    TSBitReaderSkip(&reader, 8);  // Skip header bytes

    NSMutableArray<TSDvbServiceDescriptionEntry*> *entries = [NSMutableArray array];

    // Each SDT entry requires at minimum 5 bytes (serviceId:2 + flags:1 + descriptorsLength:2)
    while (TSBitReaderRemainingBytes(&reader) >= 5) {
        uint16_t serviceId = TSBitReaderReadUInt16BE(&reader);

        uint8_t byte3 = TSBitReaderReadUInt8(&reader);
        BOOL eitScheduleFlag = (byte3 >> 1) & 0x01;
        BOOL eitPresentFollowingFlag = byte3 & 0x01;

        uint16_t bytes4And5 = TSBitReaderReadUInt16BE(&reader);
        const uint8_t runningStatus = (bytes4And5 >> 13) & 0b00000111;
        const BOOL freeCAMode = (bytes4And5 >> 12) & 0b00000001;
        const uint16_t descriptorsLength = bytes4And5 & 0x0FFF;

        if (reader.error) {
            TSLogWarn(@"SDT: read error while parsing entry for service 0x%04X", serviceId);
            break;
        }

        NSMutableArray<TSDescriptor*> *descriptors = nil;
        if (descriptorsLength > 0) {
            descriptors = [NSMutableArray array];
            NSUInteger descriptorsEndOffset = reader.byteOffset + descriptorsLength;

            // Each descriptor requires at minimum 2 bytes (tag + length)
            while (TSBitReaderRemainingBytes(&reader) >= 2 && reader.byteOffset < descriptorsEndOffset) {
                uint8_t descriptorTag = TSBitReaderReadUInt8(&reader);
                uint8_t descriptorLength = TSBitReaderReadUInt8(&reader);

                if (reader.error) {
                    TSLogWarn(@"SDT: descriptor header truncated for service 0x%04X", serviceId);
                    break;
                }

                // Bounds check: ensure descriptor payload fits
                if (TSBitReaderRemainingBytes(&reader) < descriptorLength) {
                    TSLogError(@"SDT descriptor payload truncated: need %u bytes, but only %lu available",
                               descriptorLength, (unsigned long)TSBitReaderRemainingBytes(&reader));
                    break;
                }

                NSData *descriptorPayload = descriptorLength > 0
                    ? TSBitReaderReadData(&reader, descriptorLength)
                    : nil;
                TSDescriptor *esDescriptor = [TSDescriptor makeWithTag:descriptorTag
                                                                length:descriptorLength
                                                                  data:descriptorPayload];
                if (esDescriptor) {
                    [descriptors addObject:esDescriptor];
                }
            }
        }

        TSDvbServiceDescriptionEntry *entry = [[TSDvbServiceDescriptionEntry alloc] initWithServiceId:serviceId
                                                                                      eitScheduleFlag:eitScheduleFlag
                                                                              eitPresentFollowingFlag:eitPresentFollowingFlag
                                                                                        runningStatus:runningStatus
                                                                                           freeCaMode:freeCAMode
                                                                                          descriptors:descriptors];
        [entries addObject:entry];
    }

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

-(NSUInteger)hash
{
    return self.transportStreamId ^ (self.psi.versionNumber << 16);
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
