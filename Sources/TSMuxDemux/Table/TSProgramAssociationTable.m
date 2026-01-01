//
//  TSProgramAssociationTable.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-07.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSProgramAssociationTable.h"

#define PROGRAM_BYTE_LENGTH 4

@implementation TSProgramAssociationTable
{
    NSDictionary<ProgramNumber, PmtPid> *_programmes;
}

#pragma mark - Muxer

-(instancetype _Nullable)initWithTransportStreamId:(uint16_t)transportStreamId
                                        programmes:(NSDictionary<ProgramNumber, PmtPid> * _Nonnull)programmes
{
    self = [super init];
    if (self) {
        
        NSData *sectionDataExcludingCrc = [TSProgramAssociationTable makeSectionDataFromTransportStreamId:transportStreamId
                                                                                            versionNumber:0
                                                                                     currentNextIndicator:YES
                                                                                            sectionNumber:0
                                                                                        lastSectionNumber:0
                                                                                               programmes:programmes];
        _psi = [[TSProgramSpecificInformationTable alloc]
                initWithTableId:TABLE_ID_PAT
                sectionSyntaxIndicator:PSI_SECTION_SYNTAX_INDICATOR
                reservedBit1:PSI_PRIVATE_BIT
                reservedBits2:PSI_RESERVED_BITS
                sectionLength:sectionDataExcludingCrc.length
                sectionDataExcludingCrc:sectionDataExcludingCrc
                crc:0];
    }
    return self;
}

-(NSData* _Nonnull)toTsPacketPayload
{
    return [self.psi toTsPacketPayload:self.psi.sectionDataExcludingCrc];
}

+(NSData*)makeSectionDataFromTransportStreamId:(uint16_t)transportStreamId
                                 versionNumber:(uint8_t)versionNumber
                          currentNextIndicator:(BOOL)currentNextIndicator
                                 sectionNumber:(uint8_t)sectionNumber
                             lastSectionNumber:(uint8_t)lastSectionNumber
                                    programmes:(NSDictionary<ProgramNumber, PmtPid> * _Nonnull)programmes
{
    NSData *commonSectionData = [TSProgramSpecificInformationTable makeCommonSectionDataFromFirstTwoBytes:transportStreamId
                                                                                            versionNumber:versionNumber
                                                                                     currentNextIndicator:currentNextIndicator
                                                                                            sectionNumber:sectionNumber
                                                                                        lastSectionNumber:lastSectionNumber];
    NSMutableData *sectionDataExcludingCrc = [NSMutableData dataWithCapacity:commonSectionData.length + (programmes.count * PROGRAM_BYTE_LENGTH)];
    [sectionDataExcludingCrc appendData:commonSectionData];
    
    for (ProgramNumber programNumber in programmes) {
        // Program byte 1 + 2:
        // 16 bits, 1-16:   Program_number. 0 is reserved for the network pid). It specifies the program to which the program_map_PID is applicable.
        uint16_t programByte1And2 = CFSwapInt16HostToBig(programNumber.unsignedShortValue);
        [sectionDataExcludingCrc appendBytes:&programByte1And2 length:2];
        
        // byte 3
        // 3 bits, 17-19:   reserved (111)
        // 5 bits: 20-24:   5 MSB of PMT Pid
        const uint16_t pmtPid = [programmes objectForKey:programNumber].unsignedShortValue;
        const uint8_t programByte3 = (((1 << 3) - 1) << 5) | ((pmtPid >> 8) & 0xff);
        [sectionDataExcludingCrc appendBytes:&programByte3 length:1];
        
        // byte 4:
        // 8 bits, 25-32:   8 LSB of PMT pid
        const uint8_t programByte4 = pmtPid & 0xff;
        [sectionDataExcludingCrc appendBytes:&programByte4 length:1];
    }
    
    return sectionDataExcludingCrc;
}

#pragma mark - Demuxer

-(instancetype _Nullable)initWithPSI:(TSProgramSpecificInformationTable* _Nonnull)psi
{
    if (!psi.sectionDataExcludingCrc || psi.sectionDataExcludingCrc.length == 0) {
        NSLog(@"PAT received PSI with no section data");
        return nil;
    }
    
    self = [super init];
    if (self) {
        _psi = psi;
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

-(NSDictionary*)programmes
{
    if (_programmes) {
        return _programmes;
    }

    NSUInteger baseOffset = 5;
    const NSUInteger numberOfPrograms = (self.psi.sectionDataExcludingCrc.length - baseOffset) / PROGRAM_BYTE_LENGTH;
    NSMutableDictionary *programPmtMap = [NSMutableDictionary dictionaryWithCapacity:numberOfPrograms];
    for (int i = 0; i < numberOfPrograms; ++i) {
        const NSUInteger programOffset = baseOffset + i * PROGRAM_BYTE_LENGTH;
        uint16_t programByte1And2 = 0x0;
        [self.psi.sectionDataExcludingCrc getBytes:&programByte1And2 range:NSMakeRange(programOffset, 2)];
        uint16_t programNumber = CFSwapInt16BigToHost(programByte1And2);

        uint16_t programByte3And4 = 0x0;
        [self.psi.sectionDataExcludingCrc getBytes:&programByte3And4 range:NSMakeRange(programOffset + 2, 2)];
        uint16_t programPmtPid = CFSwapInt16BigToHost(programByte3And4) & 0x1FFF;

        programPmtMap[@(programNumber)] = @(programPmtPid);
    }
    _programmes = programPmtMap;
    return _programmes;
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

-(NSUInteger)hash
{
    return self.transportStreamId ^ self.psi.versionNumber ^ self.programmes.hash;
}

-(NSString*)description
{
    return [NSString stringWithFormat:@"{ v: %u, tsId: %hu, programmes: %@ }",
            self.psi.versionNumber,
            self.transportStreamId,
            self.programmes];
}

@end
