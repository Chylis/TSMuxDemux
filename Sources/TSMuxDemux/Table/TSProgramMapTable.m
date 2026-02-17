//
//  TSProgramMapTable.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-07.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSProgramMapTable.h"
#import "../TSElementaryStream.h"
#import "../Descriptor/TSDescriptor.h"
#import "../Descriptor/TSRegistrationDescriptor.h"
#import "../TSLog.h"
#import "../TSBitReader.h"

#define ELEMENTARY_STREAM_BYTE_LENGTH 5

@implementation TSProgramMapTable
{
    NSSet<TSElementaryStream*> *_elementaryStreams;
}

#pragma mark - Muxer

-(instancetype _Nullable)initWithProgramNumber:(uint16_t)programNumber
                                 versionNumber:(uint8_t)versionNumber
                                        pcrPid:(uint16_t)pcrPid
                             elementaryStreams:(NSSet<TSElementaryStream*>* _Nonnull)elementaryStreams
{
    
    self = [super init];
    if (self) {
        NSData *sectionDataExcludingCrc = [TSProgramMapTable makeSectionDataFromProgramNumber:programNumber
                                                                                versionNumber:versionNumber
                                                                         currentNextIndicator:YES
                                                                                sectionNumber:0
                                                                            lastSectionNumber:0
                                                                                       pcrPid:pcrPid
                                                                            elementaryStreams:elementaryStreams
        ];
        _psi = [[TSProgramSpecificInformationTable alloc]
                initWithTableId:TABLE_ID_PMT
                sectionSyntaxIndicator:PSI_SECTION_SYNTAX_INDICATOR
                reservedBit1:PSI_PRIVATE_BIT
                reservedBits2:PSI_RESERVED_BITS
                sectionLength:sectionDataExcludingCrc.length + PSI_CRC_LEN
                sectionDataExcludingCrc:sectionDataExcludingCrc
                crc:0];
    }
    return self;
}

-(NSData*)toTsPacketPayload
{
    return [self.psi toTsPacketPayload:self.psi.sectionDataExcludingCrc];
}

+(NSData*)makeSectionDataFromProgramNumber:(uint16_t)programNumber
                             versionNumber:(uint8_t)versionNumber
                      currentNextIndicator:(BOOL)currentNextIndicator
                             sectionNumber:(uint8_t)sectionNumber
                         lastSectionNumber:(uint8_t)lastSectionNumber
                                    pcrPid:(uint16_t)pcrPid
                         elementaryStreams:(NSSet<TSElementaryStream*>* _Nonnull)elementaryStreams
{
    uint16_t programInfoLength = 0; // FIXME MG: Add support to mux program descriptors
    
    NSData *commonSectionData = [TSProgramSpecificInformationTable makeCommonSectionDataFromFirstTwoBytes:programNumber
                                                                                            versionNumber:versionNumber
                                                                                     currentNextIndicator:currentNextIndicator
                                                                                            sectionNumber:sectionNumber
                                                                                        lastSectionNumber:lastSectionNumber];
    NSMutableData *sectionDataExcludingCrc = [NSMutableData dataWithCapacity:
                                              commonSectionData.length
                                              + 4
                                              + programInfoLength
                                              + (elementaryStreams.count * ELEMENTARY_STREAM_BYTE_LENGTH)];
    [sectionDataExcludingCrc appendData:commonSectionData];
    
    // byte 6:          111X XXXX
    // bits 1-3:        reserved = '111' = 0x07 << 5 = 0xE0
    // bits 4-8:        5 MSB of PCR_PID (a 13-bit field)
    const uint8_t byte6 = 0xE0 | ((pcrPid >> 8) & 0x1F);
    [sectionDataExcludingCrc appendBytes:&byte6 length:1];
    
    // byte 7:          8 LSB of PCR_PID (a 13-bit field)
    const uint8_t byte7 = pcrPid & 0xFF;
    [sectionDataExcludingCrc appendBytes:&byte7 length:1];
    
    // byte 8:          1111 00XX, where XX = 0 since program descriptors are currently omitted = 1111 0000
    // bits 1-4:        reserved = '1111'
    // bits 5-6:        constant = '00'
    // bits 5-8:        2 MSB of program info length (a 10-bit field) specifing the number of bytes of the descriptors immediately following the program_info_length = 0 (i.e. no descriptors)
    const uint8_t byte8 = 0xF0;
    [sectionDataExcludingCrc appendBytes:&byte8 length:1];
    
    // byte 4:     8 LSB of program info length = 0x0
    const uint8_t byte9 = 0x00;
    [sectionDataExcludingCrc appendBytes:&byte9 length:1];
    
    // Program-descriptors skipped
    
    // Sort elementary streams by PID for deterministic serialization.
    // NSSet has no contractual enumeration order; without sorting, the CRC
    // changes across serializations even when the logical content is unchanged.
    NSSortDescriptor *pidSorter = [NSSortDescriptor sortDescriptorWithKey:@"pid" ascending:YES];
    NSArray<TSElementaryStream*> *sortedStreams = [[elementaryStreams allObjects] sortedArrayUsingDescriptors:@[pidSorter]];

    // 5 bytes for each elementary stream in PMT
    for (TSElementaryStream *es in sortedStreams) {
        // Elementary stream byte 1:        stream type
        const uint8_t esByte1 = es.streamType;
        [sectionDataExcludingCrc appendBytes:&esByte1 length:1];
        
        // Elementary stream byte 2:        111X XXXX
        // bits 1-3:                        reserved = '111' = 0x7 << 5 = 0xE0
        // bits 4-8:                        5 MSB of elementary PID (a 13-bit value)
        const uint8_t esByte2 = 0xE0 | ((es.pid >> 8) & 0x1F);
        [sectionDataExcludingCrc appendBytes:&esByte2 length:1];
        
        // Elementary stream byte 3:        8 LSB of elementary PID
        const uint8_t esByte3 = es.pid & 0xFF;
        [sectionDataExcludingCrc appendBytes:&esByte3 length:1];
        
        // Elementary stream byte 4:        1111 00XX, where XX = 00 since we es-descriptors are currently omitted = 0xF0
        // bits 1-4:                        reserved = '1111'
        // bits 5-6:                        constant = '00'
        // bits 7-8:                        2 MSB of ES info length (a 10-bit field) specifing the number of bytes of the descriptors of the associated program element immediately following the ES_info_length field = 0 (no descriptors)
        const uint8_t esByte4 = 0xF0;
        [sectionDataExcludingCrc appendBytes:&esByte4 length:1];
        
        // Elementary stream byte 5:        8 LSB of ES info length = 0x0 (no descriptors)
        const uint8_t esByte5 = 0x00;
        [sectionDataExcludingCrc appendBytes:&esByte5 length:1];
        
        // Elementary-stream descriptors skipped
    }
    
    return sectionDataExcludingCrc;
}



#pragma mark - Demuxer

-(instancetype _Nullable)initWithPSI:(TSProgramSpecificInformationTable* _Nonnull)psi
{
    if (!psi.sectionDataExcludingCrc || psi.sectionDataExcludingCrc.length == 0) {
        TSLogWarn(@"PMT received PSI with no section data");
        return nil;
    }
    
    self = [super init];
    if (self) {
        _psi = psi;
    }
    
    return self;
}


#pragma mark - Common


-(uint16_t)programNumber
{
    return self.psi.byte4And5;
}
-(uint16_t)pcrPid
{
    if (self.psi.sectionDataExcludingCrc.length < 7) return 0;
    TSBitReader reader = TSBitReaderMakeWithBytes(
        (const uint8_t *)self.psi.sectionDataExcludingCrc.bytes + 5, 2);
    TSBitReaderSkipBits(&reader, 3);  // reserved
    return TSBitReaderReadBits(&reader, 13);
}

-(uint16_t)programInfoLength
{
    if (self.psi.sectionDataExcludingCrc.length < 9) return 0;
    TSBitReader reader = TSBitReaderMakeWithBytes(
        (const uint8_t *)self.psi.sectionDataExcludingCrc.bytes + 7, 2);
    TSBitReaderSkipBits(&reader, 4);  // reserved
    return TSBitReaderReadBits(&reader, 12);
}

-(NSArray<TSDescriptor*> * _Nullable)programDescriptors
{
    NSMutableArray<TSDescriptor*> *programDescriptors = [NSMutableArray array];
    uint16_t programInfoLength = self.programInfoLength;
    if (programInfoLength == 0) return programDescriptors;

    NSUInteger dataLength = self.psi.sectionDataExcludingCrc.length;
    if (9 + programInfoLength > dataLength) return programDescriptors;

    TSBitReader reader = TSBitReaderMakeWithBytes(
        (const uint8_t *)self.psi.sectionDataExcludingCrc.bytes + 9,
        programInfoLength);

    while (TSBitReaderRemainingBytes(&reader) >= 2) {
        uint8_t descriptorTag = TSBitReaderReadUInt8(&reader);
        uint8_t descriptorLength = TSBitReaderReadUInt8(&reader);

        if (reader.error || TSBitReaderRemainingBytes(&reader) < descriptorLength) {
            TSLogWarn(@"PMT: program descriptor truncated");
            break;
        }

        NSData *descriptorPayload = descriptorLength > 0
            ? TSBitReaderReadData(&reader, descriptorLength)
            : nil;

        TSDescriptor *programDescriptor = [TSDescriptor makeWithTag:descriptorTag
                                                             length:descriptorLength
                                                               data:descriptorPayload];
        if (programDescriptor) {
            [programDescriptors addObject:programDescriptor];
        }
    }

    return programDescriptors;
}

-(TSElementaryStream* _Nullable)elementaryStreamWithPid:(uint16_t)pid
{
    for (TSElementaryStream *es in self.elementaryStreams) {
        if (es.pid == pid) return es;
    }
    return nil;
}

-(NSSet<TSElementaryStream*> * _Nonnull)elementaryStreams
{
    if (_elementaryStreams) {
        return _elementaryStreams;
    }

    NSMutableSet *result = [NSMutableSet set];
    NSUInteger esDataStart = 9 + self.programInfoLength;
    NSUInteger dataLength = self.psi.sectionDataExcludingCrc.length;

    if (esDataStart >= dataLength) {
        _elementaryStreams = result;
        return _elementaryStreams;
    }

    TSBitReader reader = TSBitReaderMakeWithBytes(
        (const uint8_t *)self.psi.sectionDataExcludingCrc.bytes + esDataStart,
        dataLength - esDataStart);

    // Each ES entry requires at minimum 5 bytes (1 stream_type + 2 PID + 2 ES_info_length)
    while (TSBitReaderRemainingBytes(&reader) >= 5) {
        // 8 bits: stream_type
        const uint8_t esStreamType = TSBitReaderReadUInt8(&reader);
        // 3 bits: reserved, 13 bits: elementary PID
        TSBitReaderSkipBits(&reader, 3);
        const uint16_t esPid = TSBitReaderReadBits(&reader, 13);
        // 4 bits: reserved, 12 bits: ES_info_length
        TSBitReaderSkipBits(&reader, 4);
        const uint16_t esInfoLength = TSBitReaderReadBits(&reader, 12);

        if (reader.error) {
            TSLogWarn(@"PMT: read error while parsing ES entry for PID 0x%04X", esPid);
            break;
        }

        NSMutableArray<TSDescriptor*> *esDescriptors = nil;
        if (esInfoLength > 0) {
            esDescriptors = [NSMutableArray array];
            TSBitReader descReader = TSBitReaderSubReader(&reader, esInfoLength);

            while (TSBitReaderRemainingBytes(&descReader) >= 2) {
                uint8_t descriptorTag = TSBitReaderReadUInt8(&descReader);
                uint8_t descriptorLength = TSBitReaderReadUInt8(&descReader);

                if (descReader.error || TSBitReaderRemainingBytes(&descReader) < descriptorLength) {
                    TSLogWarn(@"PMT: ES descriptor truncated for PID 0x%04X", esPid);
                    break;
                }

                NSData *descriptorPayload = descriptorLength > 0
                    ? TSBitReaderReadData(&descReader, descriptorLength)
                    : nil;

                TSDescriptor *esDescriptor = [TSDescriptor makeWithTag:descriptorTag
                                                                length:descriptorLength
                                                                  data:descriptorPayload];
                if (esDescriptor) {
                    [esDescriptors addObject:esDescriptor];
                }
            }
        }

        TSElementaryStream *stream = [[TSElementaryStream alloc] initWithPid:esPid
                                                                  streamType:esStreamType
                                                                 descriptors:esDescriptors];
        [result addObject:stream];
    }

    _elementaryStreams = result;
    return _elementaryStreams;
}

#pragma mark - Overridden

-(BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[TSProgramMapTable class]]) {
        return NO;
    }
    return [self isEqualToPmt:(TSProgramMapTable*)object];
}

-(BOOL)isEqualToPmt:(TSProgramMapTable *)pmt
{
    return self.programNumber == pmt.programNumber
    && self.psi.versionNumber == pmt.psi.versionNumber
    && [self.elementaryStreams isEqual:pmt.elementaryStreams];
}

-(NSUInteger)hash
{
    return self.programNumber ^ (self.psi.versionNumber << 16) ^ self.elementaryStreams.hash;
}

-(NSString*)description
{
    NSMutableString *progDescriptors = [NSMutableString stringWithFormat:@"%@", @""];
        
    BOOL first = YES;
    for (TSDescriptor *d in self.programDescriptors) {
        if (!first) {
            [progDescriptors appendString:@", "];
        }
        [progDescriptors appendString:[d tagDescription]];
        first = NO;
    }
    
    NSSortDescriptor *pidSorter = [NSSortDescriptor sortDescriptorWithKey:@"pid" ascending:YES];
    NSArray *sortedStreams = [[self.elementaryStreams allObjects]
                              sortedArrayUsingDescriptors:@[pidSorter]];
    
    return [NSString stringWithFormat:
            @"{ v: %u, program: %hu, pcrPid: %hu, tags: [%@], streams: %@ }",
            self.psi.versionNumber,
            self.programNumber,
            self.pcrPid,
            progDescriptors,
            sortedStreams];
}


@end
