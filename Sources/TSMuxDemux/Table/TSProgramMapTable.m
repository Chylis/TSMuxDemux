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
                sectionLength:sectionDataExcludingCrc.length
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
    
    // 5 bytes for each elementary stream in PMT
    for (TSElementaryStream *es in elementaryStreams) {
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
        NSLog(@"PMT received PSI with no section data");
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
    uint16_t sdBytes6And7 = 0x0;
    [self.psi.sectionDataExcludingCrc getBytes:&sdBytes6And7 range:NSMakeRange(5, 2)];
    return CFSwapInt16BigToHost(sdBytes6And7) & (uint16_t)0x1FFF;
}

-(uint16_t)programInfoLength
{
    uint16_t sdBytes8And9 = 0x0;
    [self.psi.sectionDataExcludingCrc getBytes:&sdBytes8And9 range:NSMakeRange(7, 2)];
    return CFSwapInt16BigToHost(sdBytes8And9) & (uint16_t)0x3FF;
}

-(NSArray<TSDescriptor*> * _Nullable)programDescriptors
{
    NSMutableArray<TSDescriptor*> *programDescriptors = [NSMutableArray array];
    NSUInteger programDescriptorsRemainingLength = self.programInfoLength;
    NSUInteger offset = 9;
    
    NSUInteger dataLength = self.psi.sectionDataExcludingCrc.length;
    while (programDescriptorsRemainingLength > 0) { // program-info loop begin
        // Bounds check: need at least 2 bytes for tag and length
        if (offset + 2 > dataLength) break;

        uint8_t descriptorTag = 0x0;
        [self.psi.sectionDataExcludingCrc getBytes:&descriptorTag range:NSMakeRange(offset, 1)];
        offset++;
        programDescriptorsRemainingLength--;

        // descriptorLength specifies the number of bytes of the descriptor immediately following the descriptor_length field.
        uint8_t descriptorLength = 0x0;
        [self.psi.sectionDataExcludingCrc getBytes:&descriptorLength range:NSMakeRange(offset, 1)];
        offset++;
        programDescriptorsRemainingLength--;

        // Bounds check: ensure descriptor payload fits in buffer
        if (offset + descriptorLength > dataLength) break;

        NSData *descriptorPayload = descriptorLength > 0
        ? [NSData dataWithBytesNoCopy:(void*)[self.psi.sectionDataExcludingCrc bytes] + offset
                               length:descriptorLength
                         freeWhenDone:NO]
        : nil;
        TSDescriptor *programDescriptor = [TSDescriptor makeWithTag:descriptorTag
                                                             length:descriptorLength
                                                               data:descriptorPayload];
        offset += descriptorLength;
        programDescriptorsRemainingLength -= descriptorLength;
        [programDescriptors addObject:programDescriptor];
        
    } // program-info loop end
    
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
    NSUInteger offset = 9 + self.programInfoLength;
    while (offset < self.psi.sectionDataExcludingCrc.length) { // elementary stream loop begin
        uint8_t esByte1 = 0x0;
        [self.psi.sectionDataExcludingCrc getBytes:&esByte1 range:NSMakeRange(offset, 1)];
        offset++;
        const uint8_t esStreamType = esByte1;

        uint16_t esBytes2And3 = 0x0;
        [self.psi.sectionDataExcludingCrc getBytes:&esBytes2And3 range:NSMakeRange(offset, 2)];
        offset +=2;
        const uint16_t esPid = CFSwapInt16BigToHost(esBytes2And3) & (uint16_t)0x1FFF;

        uint16_t esBytes4And5 = 0x0;
        [self.psi.sectionDataExcludingCrc getBytes:&esBytes4And5 range:NSMakeRange(offset, 2)];
        offset +=2;
        // esInfoLength specifies the number of bytes of the descriptors of the associated program element immediately following the ES_info_length field.
        const uint16_t esInfoLength = CFSwapInt16BigToHost(esBytes4And5) & (uint16_t)0x3FF;
        NSUInteger esInfoRemainingLength = esInfoLength;

        NSMutableArray<TSDescriptor*> *esDescriptors = nil;
        if (esInfoLength > 0) {
            esDescriptors = [NSMutableArray array];
            NSUInteger esDataLength = self.psi.sectionDataExcludingCrc.length;
            while (esInfoRemainingLength > 0) { // es-descriptor loop begin
                // Bounds check: need at least 2 bytes for tag and length
                if (offset + 2 > esDataLength) break;

                uint8_t descriptorTag = 0x0;
                [self.psi.sectionDataExcludingCrc getBytes:&descriptorTag range:NSMakeRange(offset, 1)];
                offset++;
                esInfoRemainingLength--;

                // descriptorLength specifies the number of bytes of the descriptor immediately following the descriptor_length field.
                uint8_t descriptorLength = 0x0;
                [self.psi.sectionDataExcludingCrc getBytes:&descriptorLength range:NSMakeRange(offset, 1)];
                offset++;
                esInfoRemainingLength--;

                // Bounds check: ensure descriptor payload fits in buffer
                if (offset + descriptorLength > esDataLength) break;

                NSData *descriptorPayload = descriptorLength > 0
                ? [NSData dataWithBytesNoCopy:(void*)[self.psi.sectionDataExcludingCrc bytes] + offset
                                       length:descriptorLength
                                 freeWhenDone:NO]
                : nil;
                TSDescriptor *esDescriptor = [TSDescriptor makeWithTag:descriptorTag
                                                                length:descriptorLength
                                                                  data:descriptorPayload];
                offset += descriptorLength;
                esInfoRemainingLength -= descriptorLength;
                [esDescriptors addObject:esDescriptor];
            } // es-descriptor loop end
        }

        TSElementaryStream *stream = [[TSElementaryStream alloc] initWithPid:esPid
                                                                  streamType:esStreamType
                                                                 descriptors:esDescriptors];
        [result addObject:stream];
    } // ES-stream loop end

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
