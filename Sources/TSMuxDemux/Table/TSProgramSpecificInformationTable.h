//
//  TSProgramSpecificInformationTable.h
//  
//
//  Created by Magnus G Eriksson on 2021-04-22.
//

#import <Foundation/Foundation.h>

#define PSI_SECTION_SYNTAX_INDICATOR 0x01
#define PSI_PRIVATE_BIT 0x00
#define PSI_RESERVED_BITS 0x03
#define PSI_CRC_LEN 4

@interface TSProgramSpecificInformationTable : NSObject

@property(nonatomic, readonly) uint8_t tableId;
@property(nonatomic, readonly) uint8_t sectionSyntaxIndicator;
@property(nonatomic, readonly) uint8_t reservedBit1;
@property(nonatomic, readonly) uint8_t reservedBits2;

/// The number of bytes of the section immediately following the section_length field, and including the CRC.
/// The value in this field shall not exceed 1021 (0x3FD).
@property(nonatomic, readonly) uint16_t sectionLength;
/// 'sectionData' property is null in the muxer flow (since the PAT/PMT serialize and inject themselves as sectionData)
/// 'sectionData' property is non-null in the demuxer flow (since the sectionData is received over the network)
// Includes everything after section_length, excluding CRC
@property(nonatomic) NSData * _Nullable sectionDataExcludingCrc;
@property(nonatomic) uint32_t crc;

// Bytes 4 and 5 have different meanings depending on the table type (e.g. transport stream id, program number, etc)
-(uint16_t)byte4And5;
-(uint8_t)versionNumber;
-(BOOL)currentNextIndicator;
-(uint8_t)sectionNumber;
-(uint8_t)lastSectionNumber;

-(instancetype _Nullable)initWithTableId:(uint8_t)tableId
                  sectionSyntaxIndicator:(uint8_t)sectionSyntaxIndicator
                            reservedBit1:(uint8_t)reservedBit1
                           reservedBits2:(uint8_t)reservedBits2
                           sectionLength:(uint16_t)sectionLength
                 sectionDataExcludingCrc:(NSData* _Nullable)sectionDataExcludingCrc
                                     crc:(uint32_t)crc;


+(NSData* _Nonnull)makeCommonSectionDataFromFirstTwoBytes:(uint16_t)firstTwoBytes
                                            versionNumber:(uint8_t)versionNumber
                                     currentNextIndicator:(BOOL)currentNextIndicator
                                            sectionNumber:(uint8_t)sectionNumber
                                        lastSectionNumber:(uint8_t)lastSectionNumber;

-(NSData* _Nonnull)toTsPacketPayload:(NSData* _Nonnull)sectionDataExcludingCrc;

#pragma mark Overridden

-(BOOL)isEqual:(id _Nullable)object;
-(NSUInteger)hash;

@end
