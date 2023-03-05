//
//  TSProgramSpecificInformationTable.m
//  
//
//  Created by Magnus G Eriksson on 2021-04-22.
//

#import "TSProgramSpecificInformationTable.h"
#import "TSPacket.h"
#import "TSConstants.h"
#import "TSCrc.h"

@implementation TSProgramSpecificInformationTable

#pragma mark - Muxer

-(instancetype _Nonnull)initWithTableId:(uint8_t)tableId
                              byte4And5:(uint16_t)byte4And5
{
    return [self initWithTableId:tableId
          sectionSyntaxIndicator:PSI_SECTION_SYNTAX_INDICATOR
                    reservedBit1:PSI_PRIVATE_BIT
                   reservedBits2:PSI_RESERVED_BITS
                   sectionLength:0
                       byte4And5:byte4And5
                   reservedBits3:PSI_RESERVED_BITS
                   versionNumber:0
            currentNextIndicator:YES
                   sectionNumber:0
               lastSectionNumber:0
                     sectionData:nil
                             crc:0];
}


-(NSData* _Nonnull)toTsPacketPayload:(NSData* _Nonnull)tableSectionData
{
    const BOOL newTableSectionBeginsInPacket = YES;
    const uint16_t sectionLength = 5 + tableSectionData.length + 4;
    
    NSMutableData *data = [NSMutableData dataWithCapacity:(newTableSectionBeginsInPacket ? 1 : 0) + 8 + tableSectionData.length + 4];
    
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
    // bit 5-6:         constant = '00'
    // bit 7-8:         2 MSB of section length (a 10-bit field) specifying the number of bytes of the section starting immediately following the section_length field, and including the CRC
    const uint8_t byte2 = 0x80 | 0x30 | ((sectionLength >> 8) & 0x03);
    [data appendBytes:&byte2 length:1];
    
    // PSI byte 3:      8 LSB of section length
    const uint8_t byte3 = sectionLength & 0xFF;
    [data appendBytes:&byte3 length:1];
    
    // PSI bytes 4 and 5:
    const uint16_t bytes4And5 = CFSwapInt16HostToBig(self.byte4And5);
    [data appendBytes:&bytes4And5 length:2];
    
    // PSI byte 6:
    // bits 1-2:        reserved = '11' = (0x3 << 6) = 0xC0
    // bit 3-7:         version number (a 5-bit field between 0-31) = ((pmtVersion << 1) & 0x3E) = 00XX XXX0
    // bit 8:           current next indicator = '1'
    const uint8_t byte6 = 0xC0 | ((_versionNumber << 1) & 0x3E) | (self.currentNextIndicator ? 0x01 : 0x00);
    [data appendBytes:&byte6 length:1];
    
    // PSI byte 7:      section number = 0x0
    [data appendBytes:&_sectionNumber length:1];
    
    // PSI byte 8:      last section number = 0x0
    [data appendBytes:&_lastSectionNumber length:1];
    
    // PSI bytes 9-N:   section data
    [data appendData:tableSectionData];
    
    // Final 4 bytes:     CRC
    uint32_t crc = CFSwapInt32HostToBig([TSCrc crc32:data.bytes+1 length:data.length-1]); // + 1 to exclude pointer field
    [data appendBytes:&crc length:4];
    
    return data;
}

#pragma mark - Demuxer

-(instancetype _Nullable)initWithTsPacket:(TSPacket* _Nonnull)packet
{
    // FIXME: Move pointer field elsewhere
    const BOOL hasPointerField = packet.header.payloadUnitStartIndicator;
    NSUInteger sectionOffset = hasPointerField ? 1 : 0; // + 1 byte for pointer field itself
    if (hasPointerField) {
        // The pointer gives the number of bytes, immediately following the pointer_field until the
        // first byte of the first section that is present in the payload of the transport stream packet 
        uint8_t pointerField = 0x0;
        [packet.payload getBytes:&pointerField range:NSMakeRange(0, 1)];
        sectionOffset += pointerField;
    }
    
    uint8_t tableId = 0x0;
    [packet.payload getBytes:&tableId range:NSMakeRange(0 + sectionOffset, 1)];
    
    uint8_t byte2 = 0x0;
    uint8_t byte3 = 0x0;
    [packet.payload getBytes:&byte2 range:NSMakeRange(1 + sectionOffset, 1)];
    [packet.payload getBytes:&byte3 range:NSMakeRange(2 + sectionOffset, 1)];
    const uint8_t sectionSyntaxIndicator = (byte2 & 0x80) >> 7;
    const uint16_t sectionLength = ((byte2 & 0x03) << 8) | (uint16_t)byte3;
    
    if ((sectionOffset + 1 + 1 + 1 + sectionLength) > TS_PACKET_MAX_PAYLOAD_SIZE) {
        NSLog(@"Error: PSI tables must fit within a single TS-packet");
        [NSException raise:@"TSUnimplementedException" format:@"PSI tables must fit within a single TS-packet"];
    }
    
    uint16_t bytes4And5 = 0x0;
    [packet.payload getBytes:&bytes4And5 range:NSMakeRange(3 + sectionOffset, 2)];
    bytes4And5 = CFSwapInt16BigToHost(bytes4And5);
    
    uint8_t byte6 = 0x0;
    [packet.payload getBytes:&byte6 range:NSMakeRange(5 + sectionOffset, 1)];
    const uint8_t versionNumber = (byte6 & 0x3E) >> 1;
    const BOOL isCurrent = (byte6 & 0x01) != 0x00;
    
    uint8_t byte7 = 0x0;
    [packet.payload getBytes:&byte7 range:NSMakeRange(6 + sectionOffset, 1)];
    const uint8_t sectionNumber = byte7;
    
    uint8_t byte8 = 0x0;
    [packet.payload getBytes:&byte8 range:NSMakeRange(7 + sectionOffset, 1)];
    const uint8_t lastSection = byte8;
    
    NSUInteger tableSectionLength = sectionLength - (5 + 4); // 5=num bytes read after sectionLength. 4 = CRC length
    uint8_t sectionData[tableSectionLength];
    [packet.payload getBytes:sectionData range:NSMakeRange(9, tableSectionLength)];
    
    //FIXME MG: CRC + reservedBits
    
    return [self initWithTableId:tableId
          sectionSyntaxIndicator:sectionSyntaxIndicator
                    reservedBit1:PSI_PRIVATE_BIT // FIXME: Parse
                   reservedBits2:PSI_RESERVED_BITS // FIXME: Parse
                   sectionLength:sectionLength
                       byte4And5:bytes4And5
                   reservedBits3:PSI_RESERVED_BITS // FIXME: Parse
                   versionNumber:versionNumber
            currentNextIndicator:isCurrent
                   sectionNumber:sectionNumber
               lastSectionNumber:lastSection
                     sectionData:[NSData dataWithBytes:sectionData length:tableSectionLength]
                             crc:0x00];
}

#pragma mark - Common

-(instancetype _Nonnull)initWithTableId:(uint8_t)tableId
                 sectionSyntaxIndicator:(uint8_t)sectionSyntaxIndicator
                           reservedBit1:(uint8_t)reservedBit1
                          reservedBits2:(uint8_t)reservedBits2
                          sectionLength:(uint16_t)sectionLength
                              byte4And5:(uint16_t)byte4And5
                          reservedBits3:(uint8_t)reservedBits3
                          versionNumber:(uint8_t)versionNumber
                   currentNextIndicator:(BOOL)currentNextIndicator
                          sectionNumber:(uint8_t)sectionNumber
                      lastSectionNumber:(uint8_t)lastSectionNumber
                            sectionData:(NSData* _Nullable)sectionData
                                    crc:(uint32_t)crc
{
    
    if (sectionLength > 1021) {
        NSLog(@"Invalid PSI section length: %u", sectionLength);
    }
    if (versionNumber > 31) {
        NSLog(@"Version number exceeds 5 bits");
    }
    
    self = [super init];
    if (self) {
        _tableId = tableId;
        _sectionSyntaxIndicator = sectionSyntaxIndicator;
        _reservedBit1 = reservedBit1;
        _reservedBits2 = reservedBits2;
        _sectionLength = sectionLength;
        _byte4And5 = byte4And5;
        _reservedBits3 = reservedBits3;
        _versionNumber = versionNumber;
        _currentNextIndicator = currentNextIndicator;
        _sectionNumber = sectionNumber;
        _lastSectionNumber = lastSectionNumber;
        _sectionData = sectionData;
        _crc = crc;
    }
    return self;
}

-(void)setVersionNumber:(uint8_t)versionNumber
{
    _versionNumber = versionNumber % 32; // Version number is a 5 bit field. 2^5 = 32.
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
     (!self.sectionData && !psi.sectionData) ||
     [self.sectionData isEqualToData:psi.sectionData]
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
    [self.sectionData hash];
}

@end
