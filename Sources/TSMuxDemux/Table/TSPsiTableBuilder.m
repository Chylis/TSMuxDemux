//
//  TSPsiTableBuilder.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-08.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSPsiTableBuilder.h"
#import "../TSPacket.h"
#import "TSProgramSpecificInformationTable.h"
#import <CoreMedia/CoreMedia.h>

@interface TSPsiTableBuilder()

@property(nonatomic, strong) TSProgramSpecificInformationTable *tableInProgress;
@property(nonatomic, strong) NSMutableData *collectedSectionDataExcludingCrc;
@property(nonatomic, strong) TSPacket *lastPacket;

@end

/**
 
 Assumptions:
 - PSI sections must not be interleaved on the same PID,
 i.e. once a tableId/section begins (e.g.SDT), all subsequent TS packets with that PID must continue that section until complete.
 
 Example of invalid sequence:
 packet 1: pid 0x11 (SDT, packet 1/4)
 packet 2: pid 0x11 (SDT, packet 2/4)
 packet 3: pid 0x11 (BAT, full section)
 packet 4: pid 0x11 (SDT, packet 3/4)
 packet 5: pid 0x11 (SDT, packet 4/4)
 
 -
 */
@implementation TSPsiTableBuilder

-(instancetype _Nonnull)initWithDelegate:(id<TSPsiTableBuilderDelegate>)delegate
                                     pid:(uint16_t)pid
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _pid = pid;
        _lastPacket = nil;
    }
    return self;
}


-(void)addTsPacket:(TSPacket* _Nonnull)tsPacket
{
    NSAssert(tsPacket.header.pid == self.pid, @"PID mismatch");
    //NSLog(@"pid: %u, CC '%u', adaptation: %u", self.pid, tsPacket.header.continuityCounter, tsPacket.header.adaptationMode);
    
    BOOL isDuplicateCC = tsPacket.header.continuityCounter == self.lastPacket.header.continuityCounter;
    
    [self setLastPacket:tsPacket];
    
    if (isDuplicateCC) {
        // FIXME MG: Consider not only duplicate CCs but also gaps
        return;
    }
    
    BOOL isFirstTable = tsPacket.header.payloadUnitStartIndicator;
    if (isFirstTable) {
        BOOL hasIncompleteTable =
        self.tableInProgress &&
        self.collectedSectionDataExcludingCrc.length < (self.tableInProgress.sectionLength - PSI_CRC_LEN);
        if (hasIncompleteTable) {
            NSLog(@"TSPsiTableBuilder: Discarding incomplete PSI section on PID %u", self.pid);
            self.tableInProgress = nil;
            self.collectedSectionDataExcludingCrc = nil;
        }
        
        NSUInteger offset = 0;
        
        uint8_t pointerField = 0x0;
        [tsPacket.payload getBytes:&pointerField range:NSMakeRange(0, 1)];
        offset++;
        // The pointer gives the number of bytes, immediately following the pointer_field until the
        // first byte of the first section that is present in the payload of the transport stream packet 
        offset+=pointerField;
        
        uint8_t tableId = 0x0;
        [tsPacket.payload getBytes:&tableId range:NSMakeRange(offset, 1)];
        offset++;
        
        uint8_t byte2 = 0x0;
        [tsPacket.payload getBytes:&byte2 range:NSMakeRange(offset, 1)];
        offset++;
        
        uint8_t byte3 = 0x0;
        [tsPacket.payload getBytes:&byte3 range:NSMakeRange(offset, 1)];
        offset++;
        
        const uint8_t sectionSyntaxIndicator = (byte2 & 0x80) >> 7;
        const uint16_t sectionLength = ((byte2 & 0x03) << 8) | (uint16_t)byte3;
        
        TSProgramSpecificInformationTable *firstTable = [[TSProgramSpecificInformationTable alloc]
                                                         initWithTableId:tableId
                                                         sectionSyntaxIndicator:sectionSyntaxIndicator
                                                         reservedBit1:PSI_PRIVATE_BIT
                                                         reservedBits2:PSI_RESERVED_BITS
                                                         sectionLength:sectionLength
                                                         sectionDataExcludingCrc:nil
                                                         crc:0];
        
        NSUInteger remainingBytesInPacket = tsPacket.payload.length - offset;
        BOOL fitsInCurrentPacket = remainingBytesInPacket >= sectionLength;
        if (fitsInCurrentPacket) {
            NSData *sectionDataExcludingCrc = [tsPacket.payload subdataWithRange:
                                               NSMakeRange(offset, sectionLength - PSI_CRC_LEN)];
            offset+=sectionDataExcludingCrc.length;
            
            uint32_t extractedCrc;
            [tsPacket.payload getBytes:&extractedCrc range:NSMakeRange(offset, PSI_CRC_LEN)];
            offset+=PSI_CRC_LEN;
            uint32_t crc = CFSwapInt32BigToHost(extractedCrc);
            
            firstTable.sectionDataExcludingCrc = sectionDataExcludingCrc;
            firstTable.crc = crc;
            [self.delegate tableBuilder:self didBuildTable:firstTable];
            
            self.tableInProgress = nil;
            self.collectedSectionDataExcludingCrc = nil;
        } else {
            // Only part of the section is available in this packet (i.e. no CRC)
            NSData *sectionDataExcludingCrc = [tsPacket.payload subdataWithRange:NSMakeRange(offset, remainingBytesInPacket)];
            offset+=sectionDataExcludingCrc.length;
            
            self.tableInProgress = firstTable;
            self.collectedSectionDataExcludingCrc = [NSMutableData dataWithData:sectionDataExcludingCrc];
        }
    } else {
        // Continuation of tableInProgress
        if (!self.tableInProgress) {
            NSLog(@"TSPsiTableBuilder: No table in progress for pid %u - discarding", self.pid);
            return;
        }
        NSUInteger remainingBytesToRead = self.tableInProgress.sectionLength - (self.collectedSectionDataExcludingCrc.length + PSI_CRC_LEN);
        BOOL isFinalPacket = tsPacket.payload.length >= remainingBytesToRead;
        if (isFinalPacket) {
            NSUInteger offset = 0;
            [self.collectedSectionDataExcludingCrc appendBytes:tsPacket.payload.bytes
                                                        length:remainingBytesToRead - PSI_CRC_LEN];
            offset+=(remainingBytesToRead - PSI_CRC_LEN);
            
            uint32_t extractedCrc;
            [tsPacket.payload getBytes:&extractedCrc
                                 range:NSMakeRange(offset, PSI_CRC_LEN)];
            offset+=PSI_CRC_LEN;
            uint32_t crc = CFSwapInt32BigToHost(extractedCrc);
            
            
            self.tableInProgress.sectionDataExcludingCrc = [NSData dataWithData:self.collectedSectionDataExcludingCrc];
            self.tableInProgress.crc = crc;
            [self.delegate tableBuilder:self didBuildTable:self.tableInProgress];
            
            self.tableInProgress = nil;
            self.collectedSectionDataExcludingCrc = nil;
        } else {
            // Only part of the section is available in this packet (i.e. no CRC)
            [self.collectedSectionDataExcludingCrc appendData:tsPacket.payload];
        }
    }
}

@end
