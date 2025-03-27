//
//  TSProgramAssociationTable.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-07.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSProgramAssociationTable.h"

#define PROGRAM_BYTE_LENGTH 4

/// No stored properties are used - everything is contained within 'sectionData'
@implementation TSProgramAssociationTable

#pragma mark - Muxer

-(instancetype _Nullable)initWithTransportStreamId:(uint16_t)transportStreamId
                                        programmes:(NSDictionary<ProgramNumber, PmtPid> * _Nonnull)programmes
{
    self = [super init];
    if (self) {
        _psi = [[TSProgramSpecificInformationTable alloc]
                initWithTableId:TABLE_ID_PAT
                byte4And5:transportStreamId
                versionNumber:0];
        _programmes = programmes;
    }
    return self;
}

-(NSData* _Nonnull)toTsPacketPayload
{
    return [self.psi toTsPacketPayload:[TSProgramAssociationTable makeSectionDataFromProgrammes:self.programmes]];
}

+(NSData*)makeSectionDataFromProgrammes:(NSDictionary<ProgramNumber, PmtPid> * _Nonnull)programmes
{
    NSMutableData *sectionData = [NSMutableData dataWithCapacity:programmes.count * PROGRAM_BYTE_LENGTH];
    
    for (ProgramNumber programNumber in programmes) {
        // Program byte 1 + 2:
        // 16 bits, 1-16:   Program_number. 0 is reserved for the network pid). It specifies the program to which the program_map_PID is applicable.
        uint16_t programByte1And2 = CFSwapInt16HostToBig(programNumber.unsignedShortValue);
        [sectionData appendBytes:&programByte1And2 length:2];
        
        // byte 3
        // 3 bits, 17-19:   reserved (111)
        // 5 bits: 20-24:   5 MSB of PMT Pid
        const uint16_t pmtPid = [programmes objectForKey:programNumber].unsignedShortValue;
        const uint8_t programByte3 = (((1 << 3) - 1) << 5) | ((pmtPid >> 8) & 0xff);
        [sectionData appendBytes:&programByte3 length:1];
        
        // byte 4:
        // 8 bits, 25-32:   8 LSB of PMT pid
        const uint8_t programByte4 = pmtPid & 0xff;
        [sectionData appendBytes:&programByte4 length:1];
    }
    
    return sectionData;
}

#pragma mark - Demuxer

-(instancetype _Nullable)initWithTsPacket:(TSPacket* _Nonnull)packet
{
    TSProgramSpecificInformationTable *psi = [[TSProgramSpecificInformationTable alloc]
                                              initWithTsPacket:packet];
    if (!psi.sectionData) {
        return nil;
    }
    
    self = [super init];
    if (self) {
        _psi = psi;
        
        const NSUInteger numberOfPrograms = psi.sectionData.length / PROGRAM_BYTE_LENGTH;
        NSMutableDictionary *programPmtMap = [NSMutableDictionary dictionaryWithCapacity:numberOfPrograms];
        for (int i = 0; i < numberOfPrograms; ++i) {
            const NSUInteger programOffset = i * PROGRAM_BYTE_LENGTH;
            uint16_t programByte1And2 = 0x0;
            [psi.sectionData getBytes:&programByte1And2 range:NSMakeRange(programOffset, 2)];
            uint16_t programNumber = CFSwapInt16BigToHost(programByte1And2);
            
            uint16_t programByte3And4 = 0x0;
            [psi.sectionData getBytes:&programByte3And4 range:NSMakeRange(programOffset + 2, 2)];
            uint16_t programPmtPid = CFSwapInt16BigToHost(programByte3And4) & 0x1FFF;
            
            programPmtMap[@(programNumber)] = @(programPmtPid);
        }
        _programmes = programPmtMap;
        
    }
    
    return self;
}


#pragma mark - Common

-(uint16_t)transportStreamId
{
    return self.psi.byte4And5;
}

-(ProgramNumber)programNumberFromPid:(uint16_t)pid
{
    for (ProgramNumber program in self.programmes) {
        uint16_t programPmtPid = self.programmes[program].unsignedShortValue;
        if (pid == programPmtPid) {
            return program;
        }
    }
    return nil;
}


#pragma mark - Equatable

-(BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[TSProgramAssociationTable class]]) {
        return NO;
    }
    return [self isEqualToPat:(TSProgramAssociationTable*)object];
}

-(BOOL)isEqualToPat:(TSProgramAssociationTable *)pat
{
    return [self.programmes isEqual:pat.programmes];
}

@end
