//
//  TSPsiTableBuilder.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-08.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSPsiTableBuilder.h"
#import "../TSPacket.h"
#import "../TSContinuityChecker.h"
#import "TSProgramSpecificInformationTable.h"
#import <CoreMedia/CoreMedia.h>

@interface TSPsiTableBuilder()
@property(nonatomic, strong) TSProgramSpecificInformationTable *tableInProgress;
@property(nonatomic, strong) TSContinuityChecker *ccChecker;
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
        _ccChecker = [[TSContinuityChecker alloc] init];
    }
    return self;
}

-(void)addTsPacket:(TSPacket* _Nonnull)tsPacket
{
    if (tsPacket.header.pid != self.pid) {
        NSLog(@"TSPsiTableBuilder: PID mismatch (got %u, expected %u)", tsPacket.header.pid, self.pid);
        return;
    }

    TSContinuityCheckResult ccResult = [self.ccChecker checkPacket:tsPacket];

    if (ccResult == TSContinuityCheckResultGap) {
        // Packets were lost - discard in-progress table to avoid processing corrupted section
        if (self.tableInProgress) {
            NSLog(@"TSPsiTableBuilder: CC gap on PID 0x%04x (packets lost), discarding incomplete table 0x%02x",
                  self.pid, self.tableInProgress.tableId);
        }
        self.tableInProgress = nil;
        return;
    }

    if (ccResult == TSContinuityCheckResultDuplicate) {
        return;
    }

    NSUInteger offset = 0;
    
    if (tsPacket.header.payloadUnitStartIndicator) {
        BOOL hasIncompleteTable =
        self.tableInProgress &&
        (self.tableInProgress.sectionDataExcludingCrc.length + PSI_CRC_LEN) < self.tableInProgress.sectionLength;
        if (hasIncompleteTable) {
            NSLog(@"TSPsiTableBuilder: Discarding incomplete PSI section on PID 0x%04x, table: 0x%04x, len: %u", self.pid, self.tableInProgress.tableId, self.tableInProgress.sectionLength);
            self.tableInProgress = nil;
        }
        
        uint8_t pointerField = 0x0;
        [tsPacket.payload getBytes:&pointerField range:NSMakeRange(0, 1)];
        offset++;
        // The pointer gives the number of bytes, immediately following the pointer_field until the
        // first byte of the first section that is present in the payload of the transport stream packet 
        offset+=pointerField;
    } else if (!self.tableInProgress) {
        NSLog(@"TSPsiTableBuilder: Waiting for start of PSI PID 0x%04x, table: 0x%04x, len: %u", self.pid, self.tableInProgress.tableId, self.tableInProgress.sectionLength);
        return;
    }
    
    while (offset < tsPacket.payload.length) {
        TSProgramSpecificInformationTable *table = self.tableInProgress ?:
        [self parseTableNoSectionData:tsPacket.payload atOffset:&offset];
        if (!table) {
            break;
        }
        
        const NSUInteger remainingBytesInPacket = tsPacket.payload.length - offset;
        NSUInteger remainingBytesInTable = table.sectionLength;
        if (self.tableInProgress) {
            remainingBytesInTable -= self.tableInProgress.sectionDataExcludingCrc.length;
        }
        
        BOOL tableFitsInCurrentPacket = remainingBytesInTable < remainingBytesInPacket;
        if (tableFitsInCurrentPacket) {
            NSData *readSectionDataNoCrc = [tsPacket.payload subdataWithRange:
                                                        NSMakeRange(offset, remainingBytesInTable - PSI_CRC_LEN)];
            offset+=readSectionDataNoCrc.length;
            
            NSData *sectionDataExcludingCrc = readSectionDataNoCrc;
            if (self.tableInProgress) {
                NSMutableData *collectedData = [NSMutableData dataWithData:self.tableInProgress.sectionDataExcludingCrc];
                [collectedData appendData:readSectionDataNoCrc];
                sectionDataExcludingCrc = [NSData dataWithData:collectedData];
            }
            table.sectionDataExcludingCrc = sectionDataExcludingCrc;
            
            uint32_t extractedCrc;
            [tsPacket.payload getBytes:&extractedCrc range:NSMakeRange(offset, PSI_CRC_LEN)];
            offset+=PSI_CRC_LEN;
            uint32_t crc = CFSwapInt32BigToHost(extractedCrc);
            table.crc = crc;
            
            // TODO: Consider async dispatch here.
            [self.delegate tableBuilder:self didBuildTable:table];
            self.tableInProgress = nil;
        } else {
            NSData *readSectionData = [tsPacket.payload subdataWithRange:NSMakeRange(offset, remainingBytesInPacket)];
            offset+=readSectionData.length;
            
            NSData *partialSectionData = readSectionData;
            if (self.tableInProgress) {
                NSMutableData *collectedData = [NSMutableData dataWithData:self.tableInProgress.sectionDataExcludingCrc];
                [collectedData appendData:readSectionData];
                partialSectionData = [NSData dataWithData:collectedData];
            }
            table.sectionDataExcludingCrc = partialSectionData;
            self.tableInProgress = table;
        }
    } // end while / no more packet data
}

-(TSProgramSpecificInformationTable * _Nullable)parseTableNoSectionData:(NSData *)data
                                                               atOffset:(NSUInteger*)ioOffset
{
    uint8_t tableId = 0x0;
    [data getBytes:&tableId range:NSMakeRange(*ioOffset, 1)];
    (*ioOffset)++;
    
    BOOL isStuffing = tableId == 0xFF;
    if (isStuffing) {
        return nil;
    }
    
    uint8_t byte2 = 0x0;
    [data getBytes:&byte2 range:NSMakeRange(*ioOffset, 1)];
    (*ioOffset)++;
    
    uint8_t byte3 = 0x0;
    [data getBytes:&byte3 range:NSMakeRange(*ioOffset, 1)];
    (*ioOffset)++;
    
    const uint8_t sectionSyntaxIndicator = (byte2 & 0x80) >> 7;
    const uint16_t sectionLength = ((byte2 & 0x03) << 8) | (uint16_t)byte3;
    
    TSProgramSpecificInformationTable *section = [[TSProgramSpecificInformationTable alloc]
                                                  initWithTableId:tableId
                                                  sectionSyntaxIndicator:sectionSyntaxIndicator
                                                  reservedBit1:PSI_PRIVATE_BIT
                                                  reservedBits2:PSI_RESERVED_BITS
                                                  sectionLength:sectionLength
                                                  sectionDataExcludingCrc:nil
                                                  crc:0];
    return section;
}

@end
