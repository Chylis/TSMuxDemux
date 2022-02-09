//
//  TSProgramSpecificInformationTable.h
//  
//
//  Created by Magnus G Eriksson on 2021-04-22.
//

#import <Foundation/Foundation.h>
@class TSPacket;

#define PSI_SECTION_SYNTAX_INDICATOR 0x01
#define PSI_PRIVATE_BIT 0x00
#define PSI_RESERVED_BITS 0x03

@interface TSProgramSpecificInformationTable : NSObject

@property(nonatomic, readonly) uint8_t tableId;
@property(nonatomic, readonly) uint8_t sectionSyntaxIndicator;
@property(nonatomic, readonly) uint8_t reservedBit1;
@property(nonatomic, readonly) uint8_t reservedBits2;

/// The number of bytes of the section immediately following the section_length field, and including the CRC.
/// The value in this field shall not exceed 1021 (0x3FD).
@property(nonatomic, readonly) uint16_t sectionLength;

/// Bytes 4 and 5 have different meanings depending on the table type (e.g. transport stream id, program number, etc
@property(nonatomic, readonly) uint16_t byte4And5;

@property(nonatomic, readonly) uint8_t reservedBits3;
@property(nonatomic) uint8_t versionNumber;
@property(nonatomic, readonly) BOOL currentNextIndicator;
@property(nonatomic, readonly) uint8_t sectionNumber;
@property(nonatomic, readonly) uint8_t lastSectionNumber;

/// 'sectionData' property is null in the muxer flow (since the PAT/PMT serialize and inject themselves as sectionData)
/// 'sectionData' property is non-null in the demuxer flow (since the sectionData is received over the network)
@property(nonatomic, readonly) NSData * _Nullable sectionData;

@property(nonatomic, readonly) uint32_t crc;

#pragma mark Muxer

-(instancetype _Nonnull)initWithTableId:(uint8_t)tableId
                              byte4And5:(uint16_t)byte4And5;

-(NSData* _Nonnull)toTsPacketPayload:(NSData* _Nonnull)sectionData;

#pragma mark Demuxer

-(instancetype _Nullable)initWithTsPacket:(TSPacket* _Nonnull)packet;


#pragma mark Overridden

-(BOOL)isEqual:(id _Nullable)object;
-(NSUInteger)hash;

@end
