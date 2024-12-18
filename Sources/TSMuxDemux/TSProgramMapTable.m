//
//  TSProgramMapTable.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-07.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSProgramMapTable.h"
#import "TSElementaryStream.h"

#define ELEMENTARY_STREAM_BYTE_LENGTH 5

@implementation TSProgramMapTable

#pragma mark - Muxer

-(instancetype _Nullable)initWithProgramNumber:(uint16_t)programNumber
                                        pcrPid:(uint16_t)pcrPid
                             elementaryStreams:(NSSet<TSElementaryStream*>* _Nonnull)elementaryStreams
{
    
    self = [super init];
    if (self) {
        _pcrPid = pcrPid;
        _programInfoLength = 0;
        _elementaryStreams = elementaryStreams;
        _psi = [[TSProgramSpecificInformationTable alloc] initWithTableId:TABLE_ID_PMT byte4And5:programNumber];
    }
    return self;
}

-(NSData*)toTsPacketPayload
{
    return [self.psi toTsPacketPayload:[TSProgramMapTable makeSectionDataFromPcrPid:self.pcrPid
                                                                  programInfoLength:self.programInfoLength
                                                                  elementaryStreams:self.elementaryStreams]];
}

+(NSData*)makeSectionDataFromPcrPid:(uint16_t)pcrPid
                  programInfoLength:(uint16_t)programInfoLength
                  elementaryStreams:(NSSet<TSElementaryStream*>* _Nonnull)elementaryStreams
{
    NSMutableData *data = [NSMutableData dataWithCapacity:2 + 2 + programInfoLength + (elementaryStreams.count * ELEMENTARY_STREAM_BYTE_LENGTH)];
    
    // byte 1:          111X XXXX
    // bits 1-3:        reserved = '111' = 0x07 << 5 = 0xE0
    // bits 4-8:        5 MSB of PCR_PID (a 13-bit field)
    const uint8_t byte1 = 0xE0 | ((pcrPid >> 8) & 0x1F);
    [data appendBytes:&byte1 length:1];
    
    // byte 2:          8 LSB of PCR_PID (a 13-bit field)
    const uint8_t byte2 = pcrPid & 0xFF;
    [data appendBytes:&byte2 length:1];
    
    // byte 3:          1111 00XX, where XX = 0 since program descriptors are currently omitted = 1111 0000
    // bits 1-4:        reserved = '1111'
    // bits 5-6:        constant = '00'
    // bits 5-8:        2 MSB of program info length (a 10-bit field) specifing the number of bytes of the descriptors immediately following the program_info_length = 0 (i.e. no descriptors)
    const uint8_t byte3 = 0xF0;
    [data appendBytes:&byte3 length:1];
    
    // byte 4:     8 LSB of program info length = 0x0
    const uint8_t byte4 = 0x00;
    [data appendBytes:&byte4 length:1];
    
    // Program-descriptors skipped
    
    // 5 bytes for each elementary stream in PMT
    for (TSElementaryStream *es in elementaryStreams) {
        // Elementary stream byte 1:        stream type
        const uint8_t esByte1 = es.streamType;
        [data appendBytes:&esByte1 length:1];
        
        // Elementary stream byte 2:        111X XXXX
        // bits 1-3:                        reserved = '111' = 0x7 << 5 = 0xE0
        // bits 4-8:                        5 MSB of elementary PID (a 13-bit value)
        const uint8_t esByte2 = 0xE0 | ((es.pid >> 8) & 0x1F);
        [data appendBytes:&esByte2 length:1];
        
        // Elementary stream byte 3:        8 LSB of elementary PID
        const uint8_t esByte3 = es.pid & 0xFF;
        [data appendBytes:&esByte3 length:1];
        
        // Elementary stream byte 4:        1111 00XX, where XX = 00 since we es-descriptors are currently omitted = 0xF0
        // bits 1-4:                        reserved = '1111'
        // bits 5-6:                        constant = '00'
        // bits 7-8:                        2 MSB of ES info length (a 10-bit field) specifing the number of bytes of the descriptors of the associated program element immediately following the ES_info_length field = 0 (no descriptors)
        const uint8_t esByte4 = 0xF0;
        [data appendBytes:&esByte4 length:1];
        
        // Elementary stream byte 5:        8 LSB of ES info length = 0x0 (no descriptors)
        const uint8_t esByte5 = 0x00;
        [data appendBytes:&esByte5 length:1];
        
        // Elementary-stream descriptors skipped
    }
    
    return data;
}



#pragma mark - Demuxer

-(instancetype _Nullable)initWithTsPacket:(TSPacket* _Nonnull)packet
{
    TSProgramSpecificInformationTable *psi = [[TSProgramSpecificInformationTable alloc] initWithTsPacket:packet];
    if (!psi.sectionData) {
        return nil;
    }
    
    self = [super init];
    if (self) {
        _psi = psi;
        
        NSUInteger offset = 0;
        
        uint16_t bytes1And2 = 0x0;
        [psi.sectionData getBytes:&bytes1And2 range:NSMakeRange(offset, 2)];
        offset += 2;
        _pcrPid = CFSwapInt16BigToHost(bytes1And2) & (uint16_t)0x1FFF;
        
        uint16_t bytes3And4 = 0x0;
        [psi.sectionData getBytes:&bytes3And4 range:NSMakeRange(offset, 2)];
        offset +=2;
        // programInfoLength specifies the number of bytes of the descriptors immediately following the program_info_length field.
        _programInfoLength = CFSwapInt16BigToHost(bytes3And4) & (uint16_t)0x3FF;
        
        NSUInteger descriptorsRemainingLength = _programInfoLength;
        while (descriptorsRemainingLength > 0) {
            uint8_t descriptorTag = 0x0;
            [psi.sectionData getBytes:&descriptorTag range:NSMakeRange(offset, 1)];
            offset++;
            descriptorsRemainingLength--;
            
            // descriptorLength specifies the number of bytes of the descriptor immediately following the descriptor_length field.
            uint8_t descriptorLength = 0x0;
            [psi.sectionData getBytes:&descriptorLength range:NSMakeRange(offset, 1)];
            offset++;
            descriptorsRemainingLength--;
            
            // Skip remaining fields...
            offset += descriptorLength;
            descriptorsRemainingLength -= descriptorLength;
        }
        
        NSMutableSet *streams = [NSMutableSet set];
        while (offset < psi.sectionData.length) {
            uint8_t esByte1 = 0x0;
            [psi.sectionData getBytes:&esByte1 range:NSMakeRange(offset, 1)];
            offset++;
            const uint8_t esStreamType = esByte1;
            
            uint16_t esBytes2And3 = 0x0;
            [psi.sectionData getBytes:&esBytes2And3 range:NSMakeRange(offset, 2)];
            offset +=2;
            const uint16_t esPid = CFSwapInt16BigToHost(esBytes2And3) & (uint16_t)0x1FFF;
            
            uint16_t esBytes4And5 = 0x0;
            [psi.sectionData getBytes:&esBytes4And5 range:NSMakeRange(offset, 2)];
            offset +=2;
            // esInfoLength specifies the number of bytes of the descriptors of the associated program element immediately following the ES_info_length field.
            const uint16_t esInfoLength = CFSwapInt16BigToHost(esBytes4And5) & (uint16_t)0x3FF;
            NSUInteger esInfoRemainingLength = esInfoLength;

            TSDescriptorTag esDescriptorTag = TSDescriptorTagUnknown;
            while (esInfoRemainingLength > 0) {
                uint8_t byte1 = 0x0;
                [psi.sectionData getBytes:&byte1 range:NSMakeRange(offset, 1)];
                offset++;
                esInfoRemainingLength--;
                esDescriptorTag = byte1;
                
                // descriptorLength specifies the number of bytes of the descriptor immediately following the descriptor_length field.
                uint8_t descriptorLength = 0x0;
                [psi.sectionData getBytes:&descriptorLength range:NSMakeRange(offset, 1)];
                offset++;
                esInfoRemainingLength--;
                
                // Skip remaining fields...
                // TODO: Parse elemental stream descriptors...
                offset += descriptorLength;
                esInfoRemainingLength -= descriptorLength;
            }
            
            TSElementaryStream *stream = [[TSElementaryStream alloc] initWithPid:esPid
                                                                      streamType:esStreamType
                                                                   descriptorTag:esDescriptorTag];
            [streams addObject:stream];
        }
        _elementaryStreams = streams;
    }
    return self;
}

#pragma mark - Common

-(uint16_t)programNumber
{
    return self.psi.byte4And5;
}


-(void)setPcrPid:(uint16_t)pcrPid
{
    if (self.pcrPid != pcrPid) {
        _pcrPid = pcrPid;
        [self.psi setVersionNumber:self.psi.versionNumber + 1];
    }
}


-(void)addElementaryStream:(TSElementaryStream* _Nonnull)es
{
    const BOOL alreadyExists = [self elementaryStreamWithPid:es.pid] != nil;
    if (!alreadyExists) {
        _elementaryStreams = [self.elementaryStreams setByAddingObject:es];
        [self.psi setVersionNumber:self.psi.versionNumber + 1];
    }
}

-(TSElementaryStream* _Nullable)elementaryStreamWithPid:(uint16_t)pid
{
    for (TSElementaryStream *es in self.elementaryStreams) {
        if (es.pid == pid) return es;
    }
    return nil;
}

#pragma mark - Equatable

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
    return self.programNumber == pmt.programNumber &&
    [self.elementaryStreams isEqual:pmt.elementaryStreams];
}


@end
