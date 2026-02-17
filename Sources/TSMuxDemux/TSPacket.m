//
//  TSPacket.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-07.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSPacket.h"
#import "TSConstants.h"
#import "TSElementaryStream.h"
#import "TSLog.h"
#import "TSBitReader.h"


#pragma mark - TSPacketHeader

@implementation TSPacketHeader

-(instancetype)initWithSyncByte:(uint8_t)syncByte
                            tei:(BOOL)tei
                           pusi:(BOOL)pusi
              transportPriority:(BOOL)transportPriority
                            pid:(uint16_t)pid
                    isScrambled:(BOOL)isScrambled
                 adaptationMode:(TSAdaptationMode)adaptationMode
              continuityCounter:(uint8_t)continuityCounter
{
    self = [super init];
    if (self) {
        _syncByte = syncByte;
        _transportErrorIndicator = tei;
        _payloadUnitStartIndicator = pusi;
        _transportPriority = transportPriority;
        _pid = pid;
        _isScrambled = isScrambled;
        _adaptationMode = adaptationMode;
        _continuityCounter = continuityCounter;
    }
    return self;
}

+(instancetype)initWithTsPacketData:(NSData*)tsPacketData
{
    if (tsPacketData.length < TS_PACKET_HEADER_SIZE) {
        TSLogError(@"Failed parsing ts-header - too few bytes: %lu", (unsigned long)tsPacketData.length);
        return nil;
    }
    
    TSBitReader reader = TSBitReaderMake(tsPacketData);
    
    // Byte 1: sync byte
    const uint8_t syncByte = TSBitReaderReadUInt8(&reader);
    
    // Byte 2-3 bit fields:
    // - 1 bit: transport error indicator
    // - 1 bit: payload unit start indicator
    // - 1 bit: transport priority
    // - 13 bits: PID
    const BOOL transportErrorIndicator = TSBitReaderReadBits(&reader, 1) != 0;
    const BOOL payloadUnitStartIndicator = TSBitReaderReadBits(&reader, 1) != 0;
    const BOOL transportPriority = TSBitReaderReadBits(&reader, 1) != 0;
    const uint16_t pid = TSBitReaderReadBits(&reader, 13);
    
    // Byte 4 bit fields:
    // - 2 bits: transport scrambling control
    // - 2 bits: adaptation field control
    // - 4 bits: continuity counter
    const BOOL isScrambled = TSBitReaderReadBits(&reader, 2) != 0;
    const TSAdaptationMode adaptationMode = TSBitReaderReadBits(&reader, 2);
    const uint8_t continuityCounter = TSBitReaderReadBits(&reader, 4);
    
    if (reader.error) {
        TSLogError(@"Failed parsing ts-header - read error");
        return nil;
    }
    
    TSPacketHeader *header = [[TSPacketHeader alloc] initWithSyncByte:syncByte
                                                                  tei:transportErrorIndicator
                                                                 pusi:payloadUnitStartIndicator
                                                    transportPriority:transportPriority
                                                                  pid:pid
                                                          isScrambled:isScrambled
                                                       adaptationMode:adaptationMode
                                                    continuityCounter:continuityCounter];
    return header;
}

-(NSData*)getBytes
{
    NSMutableData *data = [NSMutableData dataWithCapacity:TS_PACKET_HEADER_SIZE];
    
    // Header byte 1:       Sync byte
    const uint8_t byte1 = self.syncByte;
    [data appendBytes:&byte1 length:1];
    
    // Header byte 2:
    // bit 1:               tranport error indicator
    // bit 2:               payload unit start indicator
    // bit 3:               transport priority
    // bits 4-8:            5 MSB bits of the 13-bit PID
    const uint8_t byte2 =   ((self.transportErrorIndicator ? 0x01 : 0x00) << 7) |
    ((self.payloadUnitStartIndicator ? 0x01 : 0x00) << 6) |
    ((self.transportPriority ? 0x01 : 0x00) << 5) |
    ((self.pid >> 8) & 0x1F);
    
    [data appendBytes:&byte2 length:1];
    
    // Header byte 3:       8 LSB bits of the 13-bit PID
    const uint8_t byte3 = self.pid & 0xFF;
    [data appendBytes:&byte3 length:1];
    
    // Header byte 4:
    // bits 1-2:            transport scrambling control
    // bits 3-4:            adaption field control
    // bits 5-8:            continuity counter
    const uint8_t byte4 =   ((self.isScrambled ? 0x01 : 0x00) << 6) |
    (self.adaptationMode << 4) |
    (self.continuityCounter & 0x0F);
    [data appendBytes:&byte4 length:1];
    
    return data;
}

@end

#pragma mark - TSPacketAdaptationField

@implementation TSAdaptationField
-(instancetype)initWithAdaptationFieldLength:(uint8_t)adaptationFieldLength
                           discontinuityFlag:(BOOL)discontinuityFlag
                            randomAccessFlag:(BOOL)randomAccessFlag
                              esPriorityFlag:(BOOL)esPriorityFlag
                                     pcrFlag:(BOOL)pcrFlag
                                    oPcrFlag:(BOOL)oPcrFlag
                           splicingPointFlag:(BOOL)splicingPointFlag
                    transportPrivateDataFlag:(BOOL)transportPrivateDataFlag
                adaptationFieldExtensionFlag:(BOOL)adaptationFieldExtensionFlag
                                     pcrBase:(uint64_t)pcrBase
                                      pcrExt:(uint16_t)pcrExt
                        numberOfStuffedBytes:(NSUInteger)numberOfStuffedBytes
{
    self = [super init];
    if (self) {
        _adaptationFieldLength = adaptationFieldLength;
        
        _discontinuityFlag = discontinuityFlag;
        _randomAccessFlag = randomAccessFlag;
        _esPriorityFlag = esPriorityFlag;
        _pcrFlag = pcrFlag;
        _oPcrFlag = oPcrFlag;
        _splicingPointFlag = splicingPointFlag;
        _transportPrivateDataFlag = transportPrivateDataFlag;
        _adaptationFieldExtensionFlag = adaptationFieldExtensionFlag;
        
        _pcrBase = pcrBase;
        _pcrExt = pcrExt;
        _numberOfStuffedBytes = numberOfStuffedBytes;
    }
    return self;
}

+(instancetype _Nonnull)initWithPcrBase:(uint64_t)pcrBase
                                 pcrExt:(uint16_t)pcrExt
                      discontinuityFlag:(BOOL)discontinuityFlag
                       randomAccessFlag:(BOOL)randomAccessFlag
                   remainingPayloadSize:(NSUInteger)remainingPayloadSize
{
    const BOOL hasPcr = pcrBase != kNoPcr;
    const BOOL shouldIncludeHeaderByte2 = hasPcr || discontinuityFlag || randomAccessFlag;
    const BOOL singleByteStuffing = !shouldIncludeHeaderByte2 && remainingPayloadSize == 183;
    
    uint64_t numberOfBytesToStuff;
    NSUInteger adaptationFieldTotalSize;
    if (singleByteStuffing) {
        numberOfBytesToStuff = 0;
        adaptationFieldTotalSize = 1;
    } else {
        const NSUInteger adaptationHeaderSize = 1 + 1 + (hasPcr ? 6 : 0);
        const NSUInteger remainingPacketSpace = TS_PACKET_SIZE_188 - TS_PACKET_HEADER_SIZE - adaptationHeaderSize;
        const NSUInteger packetPayloadSize = MIN(remainingPacketSpace, remainingPayloadSize);
        numberOfBytesToStuff = remainingPacketSpace - packetPayloadSize;
        adaptationFieldTotalSize = adaptationHeaderSize + numberOfBytesToStuff;
    }
    
    const uint8_t adaptationFieldLength = adaptationFieldTotalSize - 1;
    return [[TSAdaptationField alloc] initWithAdaptationFieldLength:adaptationFieldLength
                                                  discontinuityFlag:discontinuityFlag
                                                   randomAccessFlag:randomAccessFlag
                                                     esPriorityFlag:NO
                                                            pcrFlag:hasPcr
                                                           oPcrFlag:NO
                                                  splicingPointFlag:NO
                                           transportPrivateDataFlag:NO
                                       adaptationFieldExtensionFlag:NO
                                                            pcrBase:pcrBase
                                                             pcrExt:pcrExt
                                               numberOfStuffedBytes:numberOfBytesToStuff];
}

+(instancetype)initWithTsPacketData:(NSData*)tsPacketData
{
    TSBitReader reader = TSBitReaderMakeWithBytes((const uint8_t *)tsPacketData.bytes + TS_PACKET_HEADER_SIZE,
                                                  tsPacketData.length - TS_PACKET_HEADER_SIZE);
    
    const uint8_t adaptationFieldLength = TSBitReaderReadUInt8(&reader);
    
    BOOL discontinuityFlag = NO;
    BOOL randomAccessIndicator = NO;
    BOOL esPriorityIndicator = NO;
    BOOL pcrFlag = NO;
    BOOL oPcrFlag = NO;
    BOOL splicingPointFlag = NO;
    BOOL transportPrivateDataFlag = NO;
    BOOL adaptationFieldExtensionFlag = NO;
    uint64_t pcrBase = 0;
    uint16_t pcrExt = 0;
    
    if (adaptationFieldLength > 0) {
        // Flags byte (8 single-bit flags)
        discontinuityFlag = TSBitReaderReadBits(&reader, 1) != 0;
        randomAccessIndicator = TSBitReaderReadBits(&reader, 1) != 0;
        esPriorityIndicator = TSBitReaderReadBits(&reader, 1) != 0;
        pcrFlag = TSBitReaderReadBits(&reader, 1) != 0;
        oPcrFlag = TSBitReaderReadBits(&reader, 1) != 0;
        splicingPointFlag = TSBitReaderReadBits(&reader, 1) != 0;
        transportPrivateDataFlag = TSBitReaderReadBits(&reader, 1) != 0;
        adaptationFieldExtensionFlag = TSBitReaderReadBits(&reader, 1) != 0;
        
        // Parse PCR (48 bits) if present: 33-bit base + 6 reserved + 9-bit extension
        if (pcrFlag) {
            pcrBase = ((uint64_t)TSBitReaderReadBits(&reader, 32) << 1) | TSBitReaderReadBits(&reader, 1);
            TSBitReaderSkipBits(&reader, 6);  // Reserved bits
            pcrExt = TSBitReaderReadBits(&reader, 9);
        }
        
        // Skip OPCR (48 bits) if present
        if (oPcrFlag) {
            TSBitReaderSkipBits(&reader, 48);
        }
        
        // Skip splice_countdown (8 bits) if present
        if (splicingPointFlag) {
            TSBitReaderSkipBits(&reader, 8);
        }
        
        // Skip transport_private_data if present (length byte + data)
        if (transportPrivateDataFlag) {
            uint8_t transportPrivateDataLength = TSBitReaderReadUInt8(&reader);
            TSBitReaderSkip(&reader, transportPrivateDataLength);
        }
        
        // Skip adaptation_field_extension if present (length byte + data)
        if (adaptationFieldExtensionFlag) {
            uint8_t adaptationFieldExtensionLength = TSBitReaderReadUInt8(&reader);
            TSBitReaderSkip(&reader, adaptationFieldExtensionLength);
        }
    }
    
    if (reader.error) {
        TSLogError(@"Malformed adaptation field: read exceeded bounds");
        return nil;
    }
    
    // Calculate stuffing bytes: total length minus bytes consumed after the length byte
    NSUInteger numberOfStuffedBytes = 0;
    if (adaptationFieldLength > 0) {
        NSUInteger bytesConsumed = reader.byteOffset - 1;  // -1 excludes the length byte itself
        numberOfStuffedBytes = (adaptationFieldLength > bytesConsumed) ? (adaptationFieldLength - bytesConsumed) : 0;
    }
    
    TSAdaptationField *adaptationField = [[TSAdaptationField alloc] initWithAdaptationFieldLength:adaptationFieldLength
                                                                                discontinuityFlag:discontinuityFlag
                                                                                 randomAccessFlag:randomAccessIndicator
                                                                                   esPriorityFlag:esPriorityIndicator
                                                                                          pcrFlag:pcrFlag
                                                                                         oPcrFlag:oPcrFlag
                                                                                splicingPointFlag:splicingPointFlag
                                                                         transportPrivateDataFlag:transportPrivateDataFlag
                                                                     adaptationFieldExtensionFlag:adaptationFieldExtensionFlag
                                                                                          pcrBase:pcrBase
                                                                                           pcrExt:pcrExt
                                                                             numberOfStuffedBytes:numberOfStuffedBytes];
    
    return adaptationField;
}


-(NSData*)getBytes
{
    NSMutableData *data = [NSMutableData dataWithCapacity:1 + self.adaptationFieldLength];
    
    // Adaption header byte 1:
    // adaptation_field_length = number of bytes in the adaptation_field following this field
    const uint8_t adaptionHeaderByte1 = self.adaptationFieldLength;
    [data appendBytes:&adaptionHeaderByte1 length:1];
    
    if (self.adaptationFieldLength > 0) {
        // Adaption header byte 2: flags indicating the presence of optional fields in the adaptation header
        // Per ISO/IEC 13818-1:
        // Bit 7: discontinuity_indicator
        // Bit 6: random_access_indicator
        // Bit 5: elementary_stream_priority_indicator
        // Bit 4: PCR_flag
        // Bit 3: OPCR_flag
        // Bit 2: splicing_point_flag
        // Bit 1: transport_private_data_flag
        // Bit 0: adaptation_field_extension_flag
        const uint8_t adaptionHeaderByte2 =
        (self.discontinuityFlag            ? 0b10000000 : 0) |
        (self.randomAccessFlag             ? 0b01000000 : 0) |
        (self.esPriorityFlag               ? 0b00100000 : 0) |
        (self.pcrFlag                      ? 0b00010000 : 0) |
        (self.oPcrFlag                     ? 0b00001000 : 0) |
        (self.splicingPointFlag            ? 0b00000100 : 0) |
        (self.transportPrivateDataFlag     ? 0b00000010 : 0) |
        (self.adaptationFieldExtensionFlag ? 0b00000001 : 0);
        [data appendBytes:&adaptionHeaderByte2 length:1];
        
        if (self.pcrFlag) {
            // PCR: a 48-bit container containing a 42-bit pcr coded in two parts (pcrBase + pcrExt) separated by 6 reserved bits, i.e. base + reserved + ext.
            uint8_t pcr[6];
            // byte 1: bits 8-1:    Bits 33-26 of the pcrBase
            pcr[0] = ((self.pcrBase >> 25) & 0xFF);
            // byte 2: bits 8-1:    Bits 25-18 of the pcrBase
            pcr[1] = ((self.pcrBase >> 17) & 0xFF);
            // byte 3: bits 8-1:    Bits 17-10 of the pcrBase
            pcr[2] = ((self.pcrBase >> 9) & 0xFF);
            // byte 4: bits 8-1:    Bits 9-2 of the pcrBase
            pcr[3] = ((self.pcrBase >> 1) & 0xFF);
            // byte 5: bit 8:       Bit 1 of the pcrBase
            // byte 5: bits 7-2:    6 reserved bits
            // byte 5: bit 1:       Bit 9 of pcrExt
            pcr[4] = ((self.pcrBase & 0x01) << 7) | 0b01111110 | ((self.pcrExt >> 8) & 0x01);
            // byte 6: bits 8-1:    Bits 8-1 of pcrExt
            pcr[5] = self.pcrExt & 0xFF;
            [data appendBytes:pcr length:6];
        }
        
        // Stuffing (N bytes)
        const uint8_t stuffing = 0xFF; // 1111 1111
        for (int j = 0; j < self.numberOfStuffedBytes; j++) {
            [data appendBytes:&stuffing length:1];
        }
    }
    
    return data;
}


@end


#pragma mark - TSPacket

@implementation TSPacket

-(instancetype)initWithHeader:(TSPacketHeader* _Nonnull)header
              adaptationField:(TSAdaptationField* _Nullable)adaptationField
                      payload:(NSData* _Nullable)payload
{
    self = [super init];
    if (self) {
        _header = header;
        _adaptationField = adaptationField;
        _payload = payload;
    }
    
    NSUInteger size = TS_PACKET_HEADER_SIZE
    + (self.header.adaptationMode == TSAdaptationModePayloadOnly ? 0 : 1) // + 1 for the first byte of the adaptation header itself
    + self.adaptationField.adaptationFieldLength
    + self.payload.length;
    
    if (size != TS_PACKET_SIZE_188) {
        TSLogError(@"Invalid packet size: %lu", (unsigned long)size);
        return nil;
    }
    
    return self;
}

+(NSArray<TSPacket*>*)packetsFromChunkedTsData:(NSData* _Nonnull)chunk
                                    packetSize:(NSUInteger)packetSize
{
    if (packetSize != TS_PACKET_SIZE_188 && packetSize != TS_PACKET_SIZE_204) {
        TSLogError(@"Invalid packet size: %lu (expected %u or %u)",
                   (unsigned long)packetSize, TS_PACKET_SIZE_188, TS_PACKET_SIZE_204);
        return @[];
    }
    if (chunk.length % packetSize != 0) {
        TSLogError(@"Received non-integer number of ts packets: %lu (expected multiple of %lu)",
                   (unsigned long)chunk.length, (unsigned long)packetSize);
        return @[];
    }
    
    NSUInteger numberOfPackets = chunk.length / packetSize;
    NSMutableArray *packets = [NSMutableArray arrayWithCapacity:numberOfPackets];
    for (NSUInteger i = 0; i < numberOfPackets; ++i) {
        // Stride by packetSize but only read 188 bytes (RS parity at bytes 188-203 is ignored)
        NSData *tsPacketData = [NSData dataWithBytesNoCopy:(void*)chunk.bytes + (i * packetSize)
                                                    length:TS_PACKET_SIZE_188
                                              freeWhenDone:NO];
        const TSPacketHeader *header = [TSPacketHeader initWithTsPacketData:tsPacketData];
        if (!header) {
            return nil;
        }
        
        // Skip packets with transport error indicator set - payload is unreliable
        if (header.transportErrorIndicator) {
            TSLogError(@"Skipping TS packet with transport error indicator set (PID=%u)", header.pid);
            continue;
        }
        
        TSAdaptationField *adaptationField = nil;
        NSData *payload = nil;
        
        const BOOL hasAdaptationField =
        header.adaptationMode == TSAdaptationModeAdaptationOnly
        || header.adaptationMode == TSAdaptationModeAdaptationAndPayload;
        if (hasAdaptationField) {
            adaptationField = [TSAdaptationField initWithTsPacketData:tsPacketData];
        }
        
        const BOOL hasPayload = header.adaptationMode != TSAdaptationModeAdaptationOnly;
        if (hasPayload) {
            const NSUInteger payloadOffset =
            TS_PACKET_HEADER_SIZE
            + (hasAdaptationField ? 1 : 0) // + 1 for the first byte of the adaptation header itself
            + (adaptationField.adaptationFieldLength ?: 0);
            if (payloadOffset >= TS_PACKET_SIZE_188) {
                TSLogError(@"Invalid TS packet: payloadOffset %lu exceeds packet size (adaptation_field_length=%u)",
                           (unsigned long)payloadOffset, adaptationField.adaptationFieldLength);
                continue;
            }
            const NSUInteger payloadLength = TS_PACKET_SIZE_188 - payloadOffset;
            payload = [NSData dataWithBytesNoCopy:(void*)tsPacketData.bytes + payloadOffset
                                           length:payloadLength
                                     freeWhenDone:NO];
        }
        
        TSPacket *packet = [[TSPacket alloc] initWithHeader:(TSPacketHeader* _Nonnull)header
                                            adaptationField:adaptationField
                                                    payload:payload];
        [packets addObject:packet];
    }
    
    return packets;
}

+(void)packetizePayload:(NSData* _Nonnull)payload
                  track:(TSElementaryStream* _Nonnull)track
                pcrBase:(uint64_t)pcrBase
                 pcrExt:(uint16_t)pcrExt
      discontinuityFlag:(BOOL)discontinuityFlag
       randomAccessFlag:(BOOL)randomAccessFlag
         onTsPacketData:(OnTsPacketDataCallback _Nonnull)onTsPacketCb
{
    const BOOL hasPcr = pcrBase != kNoPcr;
    NSUInteger packetNumber = 0;
    NSUInteger remainingPayloadLength = payload.length;
    
    while (remainingPayloadLength > 0) {
        const BOOL isFirstPacket = packetNumber == 0;
        const BOOL shouldSendPcr = hasPcr && isFirstPacket;
        // RAI should only be set on the first packet of a PES (when PUSI=1).
        // See ISO/IEC 13818-1 section 2.4.3.4: "random_access_indicator [...] indicates that the current
        // transport stream packet [...] contain some information to aid random access at this point."
        const BOOL shouldSetRai = randomAccessFlag && isFirstPacket;
        const BOOL shouldSetDiscontinuity = discontinuityFlag && isFirstPacket;
        const BOOL needsStuffing = remainingPayloadLength < (TS_PACKET_SIZE_188 - TS_PACKET_HEADER_SIZE);
        BOOL shouldIncludeAdaptationField = shouldSendPcr || shouldSetRai || shouldSetDiscontinuity || needsStuffing;
        
        NSData *adaptationField = shouldIncludeAdaptationField ? [[TSAdaptationField initWithPcrBase:shouldSendPcr ? pcrBase : kNoPcr
                                                                                              pcrExt:shouldSendPcr ? pcrExt : 0
                                                                                   discontinuityFlag:shouldSetDiscontinuity
                                                                                    randomAccessFlag:shouldSetRai
                                                                                remainingPayloadSize:remainingPayloadLength]
                                                                  getBytes] : nil;
        
        const NSUInteger remainingSpaceInPacket = TS_PACKET_SIZE_188 - TS_PACKET_HEADER_SIZE - adaptationField.length;
        const NSUInteger packetPayloadSize = MIN(remainingSpaceInPacket, remainingPayloadLength);
        const NSUInteger payloadOffset = payload.length - remainingPayloadLength;
        
        TSPacketHeader *header = [[TSPacketHeader alloc] initWithSyncByte:TS_PACKET_HEADER_SYNC_BYTE
                                                                      tei:NO
                                                                     pusi:isFirstPacket
                                                        transportPriority:NO
                                                                      pid:track.pid
                                                              isScrambled:NO
                                                           adaptationMode:adaptationField ? TSAdaptationModeAdaptationAndPayload : TSAdaptationModePayloadOnly
                                                        continuityCounter:track.continuityCounter];
        if (packetPayloadSize > 0) {
            // The cc shall not be incremented when the adaptation_field_control of the packet equals '00' or '10'.
            track.continuityCounter = track.continuityCounter + 1;
        }
        
        NSMutableData *tsPacket = [NSMutableData dataWithCapacity:TS_PACKET_SIZE_188];
        [tsPacket appendData:header.getBytes];
        if (adaptationField) {
            [tsPacket appendData:adaptationField];
        }
        [tsPacket appendBytes:(void*)payload.bytes + payloadOffset length:packetPayloadSize];
        NSAssert(tsPacket.length == TS_PACKET_SIZE_188,
                 @"TS packet size mismatch: %lu (PID %u, packet #%lu)",
                 (unsigned long)tsPacket.length, track.pid, (unsigned long)packetNumber);
        onTsPacketCb(tsPacket, header.pid, header.continuityCounter);
        
        remainingPayloadLength -= packetPayloadSize;
        packetNumber = packetNumber + 1;
    }
}

+(NSData*)nullPacketData
{
    static NSData *nullPacket = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        uint8_t bytes[TS_PACKET_SIZE_188];
        memset(bytes, 0xFF, TS_PACKET_SIZE_188);
        bytes[0] = TS_PACKET_HEADER_SYNC_BYTE; // 0x47
        bytes[1] = 0x1F;                        // PID high 5 bits (0x1FFF >> 8)
        bytes[2] = 0xFF;                        // PID low 8 bits
        bytes[3] = 0x10;                        // adaptation=01 (payload only), CC=0
        nullPacket = [NSData dataWithBytes:bytes length:TS_PACKET_SIZE_188];
    });
    return nullPacket;
}

+(NSData*)pcrPacketDataWithPid:(uint16_t)pid
             continuityCounter:(uint8_t)continuityCounter
                       pcrBase:(uint64_t)pcrBase
                        pcrExt:(uint16_t)pcrExt
{
    // Build header: adaptation-field-only (0x20), no payload
    TSPacketHeader *header = [[TSPacketHeader alloc] initWithSyncByte:TS_PACKET_HEADER_SYNC_BYTE
                                                                  tei:NO
                                                                 pusi:NO
                                                    transportPriority:NO
                                                                  pid:pid
                                                          isScrambled:NO
                                                       adaptationMode:TSAdaptationModeAdaptationOnly
                                                    continuityCounter:continuityCounter];
    
    // Build adaptation field: PCR + stuffing to fill 188 bytes. remainingPayloadSize=0 → fills entire packet.
    TSAdaptationField *af = [TSAdaptationField initWithPcrBase:pcrBase
                                                        pcrExt:pcrExt
                                             discontinuityFlag:NO
                                              randomAccessFlag:NO
                                          remainingPayloadSize:0];
    
    NSMutableData *packet = [NSMutableData dataWithCapacity:TS_PACKET_SIZE_188];
    [packet appendData:[header getBytes]];
    [packet appendData:[af getBytes]];
    return packet;
}

@end
