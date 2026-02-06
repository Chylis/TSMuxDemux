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
#import "../TSLog.h"
#import "../TSBitReader.h"
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
        TSLogWarn(@"PID mismatch (got %u, expected %u)", tsPacket.header.pid, self.pid);
        return;
    }

    TSContinuityCheckResult ccResult = [self.ccChecker checkPacket:tsPacket];

    if (ccResult == TSContinuityCheckResultGap) {
        // Packets were lost - discard in-progress table and pending sections to avoid corrupted data
        if (self.sectionInProgress || self.pendingSections.count > 0) {
            TSLogWarn(@"CC gap on PID 0x%04x (packets lost), discarding incomplete table 0x%02x and %lu pending sections",
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
        TSBitReader ptrReader = TSBitReaderMake(tsPacket.payload);
        uint8_t pointerField = TSBitReaderReadUInt8(&ptrReader);
        if (ptrReader.error) {
            TSLogWarn(@"PSI packet too short for pointer field on PID 0x%04x", self.pid);
            return;
        }
        offset++;

        // Validate pointer_field bounds
        if (offset + pointerField > tsPacket.payload.length) {
            TSLogWarn(@"PSI pointer field overflow on PID 0x%04x (pointer=%u, remaining=%lu)",
                      self.pid, pointerField, (unsigned long)(tsPacket.payload.length - offset));
            return;
        }

        // If pointer_field > 0, bytes before pointer are continuation of previous section
        if (pointerField > 0 && self.sectionInProgress) {
            // Complete the in-progress section with continuation bytes
            NSData *continuationData = [tsPacket.payload subdataWithRange:NSMakeRange(offset, pointerField)];
            NSUInteger remainingBytesInTable = self.sectionInProgress.sectionLength - self.sectionInProgress.sectionDataExcludingCrc.length;

            if (remainingBytesInTable >= PSI_CRC_LEN && pointerField >= remainingBytesInTable) {
                // Section completes within continuation bytes
                NSUInteger dataBytesNeeded = remainingBytesInTable - PSI_CRC_LEN;
                NSData *finalDataNoCrc = [continuationData subdataWithRange:NSMakeRange(0, dataBytesNeeded)];

                NSMutableData *completeData = [NSMutableData dataWithData:self.sectionInProgress.sectionDataExcludingCrc];
                [completeData appendData:finalDataNoCrc];
                self.sectionInProgress.sectionDataExcludingCrc = [NSData dataWithData:completeData];

                // Read CRC
                if (dataBytesNeeded + PSI_CRC_LEN <= pointerField) {
                    TSBitReader crcReader = TSBitReaderMakeWithBytes(
                        (const uint8_t *)continuationData.bytes + dataBytesNeeded, PSI_CRC_LEN);
                    self.sectionInProgress.crc = TSBitReaderReadUInt32BE(&crcReader);

                    [self deliverCompletedSection:self.sectionInProgress];
                }
                self.sectionInProgress = nil;
            } else {
                // Not enough continuation bytes or invalid state - discard
                TSLogDebug(@"PSI: discarding incomplete section on PID 0x%04x (pointer=%u, needed=%lu)",
                           self.pid, pointerField, (unsigned long)remainingBytesInTable);
                self.sectionInProgress = nil;
            }
        } else if (pointerField == 0 && self.sectionInProgress) {
            // New section starts immediately but we have incomplete section - discard it
            TSLogDebug(@"Discarding incomplete PSI section on PID 0x%04x, table: 0x%04x, len: %u",
                       self.pid, self.sectionInProgress.tableId, self.sectionInProgress.sectionLength);
            self.sectionInProgress = nil;
        }

        // Move offset past pointer_field bytes to start of new section
        offset += pointerField;
    } else if (!self.sectionInProgress) {
        TSLogDebug(@"Waiting for start of PSI PID 0x%04x (no section in progress)", self.pid);
        return;
    }
    
    // PSI section header requires 3 bytes minimum (table_id + section_length)
    while (offset + 3 <= tsPacket.payload.length || self.sectionInProgress) {
        // If we're continuing a section in progress, we don't need to parse the header
        if (!self.sectionInProgress && offset + 3 > tsPacket.payload.length) {
            break;  // Not enough bytes for a new section header
        }
        TSProgramSpecificInformationTable *table = self.sectionInProgress ?:
        [self parseTableNoSectionData:tsPacket.payload atOffset:&offset];
        if (!table) {
            break;
        }
        
        const NSUInteger remainingBytesInPacket = tsPacket.payload.length - offset;
        if (remainingBytesInPacket == 0) {
            // No more data in this packet, section continues in next packet
            break;
        }
        NSUInteger remainingBytesInTable = table.sectionLength;
        if (self.sectionInProgress) {
            remainingBytesInTable -= self.sectionInProgress.sectionDataExcludingCrc.length;
        }
        
        // Validate section_length is at least PSI_CRC_LEN to prevent unsigned underflow
        if (remainingBytesInTable < PSI_CRC_LEN) {
            TSLogError(@"Invalid PSI section_length %lu (less than CRC size %d)",
                       (unsigned long)remainingBytesInTable, PSI_CRC_LEN);
            self.sectionInProgress = nil;
            break;
        }

        BOOL tableFitsInCurrentPacket = remainingBytesInTable <= remainingBytesInPacket;
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

            if (offset + PSI_CRC_LEN > tsPacket.payload.length) {
                TSLogWarn(@"PSI: insufficient bytes for CRC on PID 0x%04X", self.pid);
                self.sectionInProgress = nil;
                break;
            }
            TSBitReader crcReader = TSBitReaderMakeWithBytes(
                (const uint8_t *)tsPacket.payload.bytes + offset, PSI_CRC_LEN);
            uint32_t crc = TSBitReaderReadUInt32BE(&crcReader);
            if (crcReader.error) {
                TSLogWarn(@"PSI: failed to read CRC on PID 0x%04X", self.pid);
                self.sectionInProgress = nil;
                break;
            }
            offset += PSI_CRC_LEN;
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
        TSLogDebug(@"New table version on PID 0x%04x (tableId=0x%02x, version=%u), discarding %lu pending sections",
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

    const NSUInteger kHeaderSize = 5;  // Common PSI section header size

    // Validate section0 has enough data for header
    if (section0.sectionDataExcludingCrc.length < 3) {
        TSLogWarn(@"Section 0 too short for aggregation: %lu bytes",
                  (unsigned long)section0.sectionDataExcludingCrc.length);
        return nil;
    }

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
        if (section.sectionDataExcludingCrc.length > kHeaderSize) {
            NSUInteger payloadLength = section.sectionDataExcludingCrc.length - kHeaderSize;
            NSData *payload = [section.sectionDataExcludingCrc subdataWithRange:NSMakeRange(kHeaderSize, payloadLength)];
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
    TSBitReader reader = TSBitReaderMakeWithBytes(
        (const uint8_t *)data.bytes + *ioOffset, data.length - *ioOffset);

    uint8_t tableId = TSBitReaderReadUInt8(&reader);
    if (reader.error) {
        TSLogWarn(@"PSI: failed to read table ID on PID 0x%04X", self.pid);
        return nil;
    }

    BOOL isStuffing = tableId == 0xFF;
    if (isStuffing) {
        (*ioOffset)++;
        return nil;
    }

    uint8_t byte2 = TSBitReaderReadUInt8(&reader);
    uint8_t byte3 = TSBitReaderReadUInt8(&reader);
    if (reader.error) {
        TSLogWarn(@"PSI: section header truncated on PID 0x%04X (tableId=0x%02X)", self.pid, tableId);
        return nil;
    }

    (*ioOffset) += 3;

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
