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

@property(nonatomic, strong) TSContinuityChecker *ccChecker;

/// Byte-level: accumulates one section spanning multiple TS packets (e.g. 400-byte PMT needs 3 packets)
@property(nonatomic, strong) TSProgramSpecificInformationTable *sectionInProgress;
/// Section-level: collects complete sections of one table (e.g. large SDT with lastSectionNumber=3)
/// Key = section number.
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, TSProgramSpecificInformationTable*> *pendingSections;

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
        _pendingSections = [NSMutableDictionary dictionary];
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
        // Packets were lost - discard in-progress table and pending sections to avoid corrupted data
        if (self.sectionInProgress || self.pendingSections.count > 0) {
            NSLog(@"TSPsiTableBuilder: CC gap on PID 0x%04x (packets lost), discarding incomplete table 0x%02x and %lu pending sections",
                  self.pid, self.sectionInProgress.tableId, (unsigned long)self.pendingSections.count);
        }
        self.sectionInProgress = nil;
        [self.pendingSections removeAllObjects];
        return;
    }

    if (ccResult == TSContinuityCheckResultDuplicate) {
        return;
    }

    NSUInteger offset = 0;
    
    if (tsPacket.header.payloadUnitStartIndicator) {
        BOOL hasIncompleteTable =
        self.sectionInProgress &&
        (self.sectionInProgress.sectionDataExcludingCrc.length + PSI_CRC_LEN) < self.sectionInProgress.sectionLength;
        if (hasIncompleteTable) {
            NSLog(@"TSPsiTableBuilder: Discarding incomplete PSI section on PID 0x%04x, table: 0x%04x, len: %u", self.pid, self.sectionInProgress.tableId, self.sectionInProgress.sectionLength);
            self.sectionInProgress = nil;
        }
        
        uint8_t pointerField = 0x0;
        [tsPacket.payload getBytes:&pointerField range:NSMakeRange(0, 1)];
        offset++;
        // The pointer gives the number of bytes, immediately following the pointer_field until the
        // first byte of the first section that is present in the payload of the transport stream packet 
        offset+=pointerField;
    } else if (!self.sectionInProgress) {
        NSLog(@"TSPsiTableBuilder: Waiting for start of PSI PID 0x%04x, table: 0x%04x, len: %u", self.pid, self.sectionInProgress.tableId, self.sectionInProgress.sectionLength);
        return;
    }
    
    while (offset < tsPacket.payload.length) {
        TSProgramSpecificInformationTable *table = self.sectionInProgress ?:
        [self parseTableNoSectionData:tsPacket.payload atOffset:&offset];
        if (!table) {
            break;
        }
        
        const NSUInteger remainingBytesInPacket = tsPacket.payload.length - offset;
        NSUInteger remainingBytesInTable = table.sectionLength;
        if (self.sectionInProgress) {
            remainingBytesInTable -= self.sectionInProgress.sectionDataExcludingCrc.length;
        }
        
        BOOL tableFitsInCurrentPacket = remainingBytesInTable < remainingBytesInPacket;
        if (tableFitsInCurrentPacket) {
            NSData *readSectionDataNoCrc = [tsPacket.payload subdataWithRange:
                                                        NSMakeRange(offset, remainingBytesInTable - PSI_CRC_LEN)];
            offset+=readSectionDataNoCrc.length;
            
            // TODO: Performance improvement - use persistent mutable buffer instead of copying on each append
            NSData *sectionDataExcludingCrc = readSectionDataNoCrc;
            if (self.sectionInProgress) {
                NSMutableData *collectedData = [NSMutableData dataWithData:self.sectionInProgress.sectionDataExcludingCrc];
                [collectedData appendData:readSectionDataNoCrc];
                sectionDataExcludingCrc = [NSData dataWithData:collectedData];
            }
            table.sectionDataExcludingCrc = sectionDataExcludingCrc;
            
            uint32_t extractedCrc;
            [tsPacket.payload getBytes:&extractedCrc range:NSMakeRange(offset, PSI_CRC_LEN)];
            offset+=PSI_CRC_LEN;
            uint32_t crc = CFSwapInt32BigToHost(extractedCrc);
            table.crc = crc;

            [self deliverCompletedSection:table];
            self.sectionInProgress = nil;
        } else {
            NSData *readSectionData = [tsPacket.payload subdataWithRange:NSMakeRange(offset, remainingBytesInPacket)];
            offset+=readSectionData.length;
            
            NSData *partialSectionData = readSectionData;
            if (self.sectionInProgress) {
                NSMutableData *collectedData = [NSMutableData dataWithData:self.sectionInProgress.sectionDataExcludingCrc];
                [collectedData appendData:readSectionData];
                partialSectionData = [NSData dataWithData:collectedData];
            }
            table.sectionDataExcludingCrc = partialSectionData;
            self.sectionInProgress = table;
        }
    } // end while / no more packet data
}

/// Handles completed section delivery, collecting multi-section tables until all sections received.
-(void)deliverCompletedSection:(TSProgramSpecificInformationTable *)section
{
    uint8_t sectionNumber = section.sectionNumber;
    uint8_t lastSectionNumber = section.lastSectionNumber;

    if (sectionNumber == 0 && lastSectionNumber == 0) {
        [self.delegate tableBuilder:self didBuildTable:section];
        return;
    }

    // Multi-section table handling - check if this is a new table (different tableId or version)
    TSProgramSpecificInformationTable *existingSection = self.pendingSections.allValues.firstObject;
    if (existingSection &&
        (section.tableId != existingSection.tableId || section.versionNumber != existingSection.versionNumber)) {
        NSLog(@"TSPsiTableBuilder: New table version on PID 0x%04x (tableId=0x%02x, version=%u), discarding %lu pending sections",
              self.pid, section.tableId, section.versionNumber, (unsigned long)self.pendingSections.count);
        [self.pendingSections removeAllObjects];
    }

    self.pendingSections[@(sectionNumber)] = section;

    // Check if we have all sections (0 through lastSectionNumber)
    if (self.pendingSections.count == (NSUInteger)(lastSectionNumber + 1)) {
        TSProgramSpecificInformationTable *aggregated = [self aggregatePendingSections];
        [self.delegate tableBuilder:self didBuildTable:aggregated];
        [self.pendingSections removeAllObjects];
    }
}

/// Aggregates all pending sections into a single table with combined payload data.
-(TSProgramSpecificInformationTable *)aggregatePendingSections
{
    TSProgramSpecificInformationTable *section0 = self.pendingSections[@0];

    // sectionDataExcludingCrc layout:
    // Bytes 0-1: tableIdExtension
    // Byte 2: reserved + versionNumber + currentNextIndicator
    // Byte 3: sectionNumber
    // Byte 4: lastSectionNumber
    // Bytes 5+: table-specific payload

    NSMutableData *aggregatedData = [NSMutableData data];

    // Copy first 3 bytes from section 0 (tableIdExtension + version/flags)
    [aggregatedData appendData:[section0.sectionDataExcludingCrc subdataWithRange:NSMakeRange(0, 3)]];

    // Set sectionNumber=0, lastSectionNumber=0 for aggregated table
    uint8_t zero = 0;
    [aggregatedData appendBytes:&zero length:1];
    [aggregatedData appendBytes:&zero length:1];

    // Concatenate table-specific payload from all sections in order
    for (uint8_t i = 0; i <= section0.lastSectionNumber; i++) {
        TSProgramSpecificInformationTable *section = self.pendingSections[@(i)];
        NSUInteger payloadStart = 5;
        NSUInteger payloadLength = section.sectionDataExcludingCrc.length - payloadStart;
        if (payloadLength > 0) {
            NSData *payload = [section.sectionDataExcludingCrc subdataWithRange:NSMakeRange(payloadStart, payloadLength)];
            [aggregatedData appendData:payload];
        }
    }

    // Create aggregated table
    TSProgramSpecificInformationTable *aggregated = [[TSProgramSpecificInformationTable alloc]
                                                     initWithTableId:section0.tableId
                                                     sectionSyntaxIndicator:section0.sectionSyntaxIndicator
                                                     reservedBit1:PSI_PRIVATE_BIT
                                                     reservedBits2:PSI_RESERVED_BITS
                                                     sectionLength:(uint16_t)(aggregatedData.length + PSI_CRC_LEN)
                                                     sectionDataExcludingCrc:aggregatedData
                                                     crc:0]; // CRC not meaningful for aggregated data

    return aggregated;
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
