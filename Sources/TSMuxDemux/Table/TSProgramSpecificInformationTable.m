//
//  TSProgramSpecificInformationTable.m
//  
//
//  Created by Magnus G Eriksson on 2021-04-22.
//

#import "TSProgramSpecificInformationTable.h"
#import "../TSPacket.h"
#import "../TSConstants.h"
#import "../TSCrc.h"
#import "../TSLog.h"
#import "../TSBitReader.h"

@implementation TSProgramSpecificInformationTable

#pragma mark - Muxer

-(NSData* _Nonnull)toTsPacketPayload:(NSData* _Nonnull)sectionDataExcludingCrc
{
    const BOOL newTableSectionBeginsInPacket = YES;
    const uint16_t sectionLength = sectionDataExcludingCrc.length + PSI_CRC_LEN;
    
    NSMutableData *data = [NSMutableData
                           dataWithCapacity:(newTableSectionBeginsInPacket ? 1 : 0) + 3 + sectionLength];
    
    if (newTableSectionBeginsInPacket) {
        const uint8_t pointerField = 0x00;
        [data appendBytes:&pointerField length:1];
    }
    
    // PSI byte 1: tableId
    [data appendBytes:&_tableId length:1];
    
    // PSI byte 2:
    // bit 1:           section syntax indicator = '1'
    // bit 2:           constant = '0'
    // bit 3-4:         reserved = '11'
    // bit 5-8:         4 MSB of section length (a 12-bit field) specifying the number of bytes of the section starting immediately following the section_length field, and including the CRC
    const uint8_t byte2 = 0x80 | 0x30 | ((sectionLength >> 8) & 0x0F);
    [data appendBytes:&byte2 length:1];
    
    // PSI byte 3:      8 LSB of section length
    const uint8_t byte3 = sectionLength & 0xFF;
    [data appendBytes:&byte3 length:1];
    
    // PSI bytes 4-N:   section data
    [data appendData:sectionDataExcludingCrc];
    
    // Final 4 bytes: CRC of data, excluding pointer field
    uint32_t hostCrc = [TSCrc crc32:data.bytes + (newTableSectionBeginsInPacket ? 1 : 0)
                            length:data.length - (newTableSectionBeginsInPacket ? 1 : 0)];
    uint32_t crc = CFSwapInt32HostToBig(hostCrc);
    [data appendBytes:&crc length:PSI_CRC_LEN];
    
    return data;
}

#pragma mark - Common

-(instancetype _Nullable)initWithTableId:(uint8_t)tableId
                  sectionSyntaxIndicator:(uint8_t)sectionSyntaxIndicator
                            reservedBit1:(uint8_t)reservedBit1
                           reservedBits2:(uint8_t)reservedBits2
                           sectionLength:(uint16_t)sectionLength
                 sectionDataExcludingCrc:(NSData* _Nullable)sectionDataExcludingCrc
                                     crc:(uint32_t)crc
{
    
    if (sectionLength > 1021) {
        TSLogWarnC(@"Invalid PSI section length: %u", sectionLength);
        return nil;
    }
    
    self = [super init];
    if (self) {
        _tableId = tableId;
        _sectionSyntaxIndicator = sectionSyntaxIndicator;
        _reservedBit1 = reservedBit1;
        _reservedBits2 = reservedBits2;
        _sectionLength = sectionLength;
        _sectionDataExcludingCrc = sectionDataExcludingCrc;
        _crc = crc;
    }
    return self;
}


-(uint16_t)byte4And5
{
    if (self.sectionDataExcludingCrc.length < 2) {
        return 0;
    }
    TSBitReader reader = TSBitReaderMake(self.sectionDataExcludingCrc);
    return TSBitReaderReadUInt16BE(&reader);
}

-(uint8_t)versionNumber
{
    if (self.sectionDataExcludingCrc.length < 3) {
        return 0;
    }
    TSBitReader reader = TSBitReaderMake(self.sectionDataExcludingCrc);
    TSBitReaderSkip(&reader, 2);
    uint8_t sdByte3 = TSBitReaderReadUInt8(&reader);
    return (sdByte3 & 0x3E) >> 1;
}
-(BOOL)currentNextIndicator
{
    if (self.sectionDataExcludingCrc.length < 3) {
        return NO;
    }
    TSBitReader reader = TSBitReaderMake(self.sectionDataExcludingCrc);
    TSBitReaderSkip(&reader, 2);
    uint8_t sdByte3 = TSBitReaderReadUInt8(&reader);
    return (sdByte3 & 0x01) != 0x00;
}
-(uint8_t)sectionNumber
{
    if (self.sectionDataExcludingCrc.length < 4) {
        return 0;
    }
    TSBitReader reader = TSBitReaderMake(self.sectionDataExcludingCrc);
    TSBitReaderSkip(&reader, 3);
    return TSBitReaderReadUInt8(&reader);
}
-(uint8_t)lastSectionNumber
{
    if (self.sectionDataExcludingCrc.length < 5) {
        return 0;
    }
    TSBitReader reader = TSBitReaderMake(self.sectionDataExcludingCrc);
    TSBitReaderSkip(&reader, 4);
    return TSBitReaderReadUInt8(&reader);
}

+(NSData*)makeCommonSectionDataFromFirstTwoBytes:(uint16_t)firstTwoBytes
                                   versionNumber:(uint8_t)versionNumber
                            currentNextIndicator:(BOOL)currentNextIndicator
                                   sectionNumber:(uint8_t)sectionNumber
                               lastSectionNumber:(uint8_t)lastSectionNumber
{
    NSMutableData *commonSectionData = [NSMutableData dataWithCapacity:5];
    const uint16_t bytes1And2 = CFSwapInt16HostToBig(firstTwoBytes);
    [commonSectionData appendBytes:&bytes1And2 length:2];
    // Byte 3:
    // bits 1-2:        reserved = '11' = (0x3 << 6) = 0xC0
    // bit 3-7:         version number (a 5-bit field between 0-31) = ((pmtVersion << 1) & 0x3E) = 00XX XXX0
    // bit 8:           current next indicator = '1'
    const uint8_t byte3 = 0xC0 | ((versionNumber << 1) & 0x3E) | (currentNextIndicator ? 0x01 : 0x00);
    [commonSectionData appendBytes:&byte3 length:1];
    [commonSectionData appendBytes:&sectionNumber length:1];
    [commonSectionData appendBytes:&lastSectionNumber length:1];
    return commonSectionData;
}



#pragma mark - Overridden

-(BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[TSProgramSpecificInformationTable class]]) {
        return NO;
    }
    return [self isEqualToPsi:(TSProgramSpecificInformationTable*)object];
}

-(BOOL)isEqualToPsi:(TSProgramSpecificInformationTable*)psi
{
    return
    self.tableId == psi.tableId &&
    self.sectionLength == psi.sectionLength &&
    self.byte4And5 == psi.byte4And5 &&
    self.versionNumber == psi.versionNumber &&
    self.currentNextIndicator == psi.currentNextIndicator &&
    self.sectionNumber == psi.sectionNumber &&
    self.lastSectionNumber == psi.lastSectionNumber &&
    (
     (!self.sectionDataExcludingCrc && !psi.sectionDataExcludingCrc)
     || [self.sectionDataExcludingCrc isEqualToData:psi.sectionDataExcludingCrc]
     );
}

-(NSUInteger)hash
{
    return
    [@(self.tableId) hash] ^
    [@(self.sectionLength) hash] ^
    [@(self.byte4And5) hash] ^
    [@(self.versionNumber) hash] ^
    [@(self.currentNextIndicator) hash] ^
    [@(self.sectionNumber) hash] ^
    [@(self.lastSectionNumber) hash] ^
    [self.sectionDataExcludingCrc hash];
}

-(NSString*)description
{
    return [NSString stringWithFormat:@"{ tableId: 0x%02x, v: %u, section: %u/%u, length: %hu }",
            self.tableId,
            self.versionNumber,
            self.sectionNumber,
            self.lastSectionNumber,
            self.sectionLength];
}

@end
