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

#pragma mark - TSPacketHeader

@implementation TSPacketHeader

-(instancetype)initWithTei:(BOOL)tei
                      pusi:(BOOL)pusi
         transportPriority:(BOOL)transportPriority
                       pid:(uint16_t)pid
               isScrambled:(BOOL)isScrambled
            adaptationMode:(TSAdaptationMode)adaptationMode
         continuityCounter:(uint8_t)continuityCounter
{
    self = [super init];
    if (self) {
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
        NSLog(@"Failed parsing ts-header - too few bytes: %lu", (unsigned long)tsPacketData.length);
        return nil;
    }
    
    // Header byte 1:       Sync byte
    uint8_t byte1 = 0x00;
    [tsPacketData getBytes:&byte1 range:NSMakeRange(0, 1)];
    if (byte1 != TS_PACKET_HEADER_SYNC_BYTE) {
        NSLog(@"Failed parsing ts-header - invalid sync byte");
        return nil;
    }
    
    // Header byte 2:
    // bit 1:               tranport error indicator
    // bit 2:               payload unit start indicator
    // bit 3:               transport priority
    // bits 4-8:            5 MSB bits of the 13-bit PID
    uint8_t byte2 = 0x00;
    [tsPacketData getBytes:&byte2 range:NSMakeRange(1, 1)];
    const BOOL transportErrorIndicator = (byte2 & 0x80) != 0x00;
    const BOOL payloadUnitStartIndicator = (byte2 & 0x40) != 0x00;
    const BOOL transportPriority = (byte2 & 0x20) != 0x00;
    
    // Header byte 3:       8 LSB bits of the 13-bit PID
    uint8_t byte3 = 0x00;
    [tsPacketData getBytes:&byte3 range:NSMakeRange(2, 1)];
    const uint16_t pid = ((byte2 & 0x1F) << 8) | byte3;
    
    // Header byte 4:
    // bits 1-2:            transport scrambling control
    // bits 3-4:            adaption field control
    // bits 5-8:            continuity counter
    uint8_t byte4 = 0x00;
    [tsPacketData getBytes:&byte4 range:NSMakeRange(3, 1)];
    const BOOL isScrambled = (byte4 & 0xC0) != 0x00;
    const TSAdaptationMode adaptationMode = ((byte4 & 0x30) >> 4);
    const uint8_t continuityCounter = byte4 & 0x0F;
    
    TSPacketHeader *header = [[TSPacketHeader alloc] initWithTei:transportErrorIndicator
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
    const uint8_t byte1 = TS_PACKET_HEADER_SYNC_BYTE;
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
    NSAssert(adaptationFieldLength <= 183, @"Max adaptation field length exceeded");

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
                   remainingPayloadSize:(NSUInteger)remainingPayloadSize
{
    const BOOL hasPcr = pcrBase > 0;
    const BOOL shouldIncludeHeaderByte2 = hasPcr;
    const BOOL singleByteStuffing = !shouldIncludeHeaderByte2 && remainingPayloadSize == 183;

    uint64_t numberOfBytesToStuff;
    NSUInteger adaptationFieldTotalSize;
    if (singleByteStuffing) {
        numberOfBytesToStuff = 0;
        adaptationFieldTotalSize = 1;
    } else {
        const NSUInteger adaptationHeaderSize = 1 + 1 + (hasPcr ? 6 : 0);
        const NSUInteger remainingPacketSpace = TS_PACKET_SIZE - TS_PACKET_HEADER_SIZE - adaptationHeaderSize;
        const NSUInteger packetPayloadSize = MIN(remainingPacketSpace, remainingPayloadSize);
        numberOfBytesToStuff = remainingPacketSpace - packetPayloadSize;
        adaptationFieldTotalSize = adaptationHeaderSize + numberOfBytesToStuff;
    }
    
    const uint8_t adaptationFieldLength = adaptationFieldTotalSize - 1;
    const BOOL hasPayload = remainingPayloadSize > 0;
    if (hasPayload) {
        // When the adaptation_field_control value is '11 - both', the value of the adaptation_field_length shall be in the range 0 to 182.
        NSAssert(adaptationFieldLength <= 182, @"Invalid adaptation field length, expected 0...182");
    } else {
        // When the adaptation_field_control value is '10 - adaptation only', the value of the adaptation_field_length shall be 183.
        NSAssert(adaptationFieldLength == 183, @"Invalid adaptation field length, expected 183");
    }
    
    return [[TSAdaptationField alloc] initWithAdaptationFieldLength:adaptationFieldLength
                                                  discontinuityFlag:NO
                                                   randomAccessFlag:NO
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
    NSUInteger offset = TS_PACKET_HEADER_SIZE;
    
    uint8_t adaptationFieldLength = 0x00;
    [tsPacketData getBytes:&adaptationFieldLength range:NSMakeRange(offset, 1)];
    offset +=1;
    
    BOOL discontinuityFlag = NO;
    BOOL randomAccessIndicator = NO;
    BOOL esPriorityIndicator = NO;
    BOOL pcrFlag = NO;
    BOOL oPcrFlag = NO;
    BOOL splicingPointFlag = NO;
    BOOL transportPrivateDataFlag = NO;
    BOOL adaptationFieldExtensionFlag = NO;
    const uint64_t pcrBase = 0;
    const uint16_t pcrExt = 0;
    
    if (adaptationFieldLength > 0) {
        // byte 2:
        // bit 1:               discontinuity_indicator
        // bit 2:               random_access_indicator
        // bit 3:               elementary_stream_priority_indicator
        // bit 4:               PCR_flag
        // bit 5:               OPCR_flag
        // bit 6:               splicing_point_flag
        // bit 7:               transport_private_data_flag
        // bit 8:               adaptation_field_extension_flag
        uint8_t byte2 = 0x00;
        [tsPacketData getBytes:&byte2 range:NSMakeRange(offset, 1)];
        offset +=1;
        
        discontinuityFlag = (byte2 & 0x80) != 0x00;
        randomAccessIndicator = (byte2 & 0x40) != 0x00;
        esPriorityIndicator = (byte2 & 0x20) != 0x00;
        pcrFlag = (byte2 & 0x10) != 0x00;
        oPcrFlag = (byte2 & 0x8) != 0x00;
        splicingPointFlag = (byte2 & 0x4) != 0x00;
        transportPrivateDataFlag = (byte2 & 0x2) != 0x00;
        adaptationFieldExtensionFlag = (byte2 & 0x1) != 0x00;
        
        if (pcrFlag) {
            // FIXME: Parse pcrBase + pcrExtension
        }
        if (oPcrFlag) {
            // FIXME: Parse remaining fields...
        }
        if (splicingPointFlag) {
            // FIXME: Parse remaining fields...
        }
        if (transportPrivateDataFlag) {
            // FIXME: Parse remaining fields...
        }
        if (adaptationFieldExtensionFlag) {
            // FIXME: Parse remaining fields...
            
        }
    }
    
    // FIXME MG: Read a correct value here after parsing adaptationFieldLength
    const NSUInteger dummyNumberOfStuffedBytes = adaptationFieldLength - 1;
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
                                                                             numberOfStuffedBytes:dummyNumberOfStuffedBytes];
    
    return adaptationField;
}


-(NSData*)getBytes
{
    const BOOL hasPcr = self.pcrBase > 0;
    NSMutableData *data = [NSMutableData dataWithCapacity:1 + self.adaptationFieldLength];
    
    // Adaption header byte 1:
    // adaptation_field_length = number of bytes in the adaptation_field following this field
    const uint8_t adaptionHeaderByte1 = self.adaptationFieldLength;
    [data appendBytes:&adaptionHeaderByte1 length:1];
    
    if (self.adaptationFieldLength > 0) {
        // FIXME MG: Consider discontinuity, random access, etc
        // Adaption header byte 2:      flags indicating the presence of optional fields in the adaptation header
        const uint8_t adaptionHeaderByte2 = hasPcr ? 0b00010000 : 0b00000000;
        [data appendBytes:&adaptionHeaderByte2 length:1];
    
        if (hasPcr) {
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
    
    
    NSString *msg = [NSString stringWithFormat:@"%lu != %d: data: %lu adap len: %d, stuff: %lu, pcr: %hu", (unsigned long)data.length, self.adaptationFieldLength + 1, (unsigned long)data.length, self.adaptationFieldLength, (unsigned long)self.numberOfStuffedBytes, hasPcr];
    NSAssert(data.length == self.adaptationFieldLength + 1, msg);

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
    
    if (size != TS_PACKET_SIZE) {
        NSLog(@"TSPacket: Invalid packet size: %lu", (unsigned long)size);
        return nil;
    }
    
    return self;
}

+(NSArray<TSPacket*>*)packetsFromChunkedTsData:(NSData* _Nonnull)chunk
{
    NSAssert(chunk.length % TS_PACKET_SIZE == 0, @"Received non-integer number of ts packets");
    
    NSUInteger numberOfPackets = chunk.length / TS_PACKET_SIZE;
    NSMutableArray *packets = [NSMutableArray arrayWithCapacity:numberOfPackets];
    for (int i = 0; i < numberOfPackets; ++i) {
        NSData *tsPacketData = [NSData dataWithBytesNoCopy:(void*)chunk.bytes + (i * TS_PACKET_SIZE)
                                                    length:TS_PACKET_SIZE
                                              freeWhenDone:NO];
        const TSPacketHeader *header = [TSPacketHeader initWithTsPacketData:tsPacketData];
        if (!header) {
            return nil;
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
            const NSUInteger payloadLength = TS_PACKET_SIZE - payloadOffset;
            payload = [NSData dataWithBytes:(void*)tsPacketData.bytes + payloadOffset length:payloadLength];
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
              forcePusi:(BOOL)forcePusi
                pcrBase:(uint64_t)pcrBase
                 pcrExt:(uint16_t)pcrExt
         onTsPacketData:(OnTsPacketDataCallback _Nonnull)onTsPacketCb
{
    const BOOL hasPcr = pcrBase > 0;
    NSUInteger packetNumber = 0;
    NSUInteger remainingPayloadLength = payload.length;
    while (remainingPayloadLength > 0) {
        const BOOL isFirstPacket = packetNumber == 0;
        const BOOL shouldSendPcr = hasPcr && isFirstPacket;
        const BOOL needsStuffing = remainingPayloadLength < (TS_PACKET_SIZE - TS_PACKET_HEADER_SIZE);
        BOOL shouldIncludeAdaptationField = shouldSendPcr || needsStuffing;
        
        NSData *adaptationField = shouldIncludeAdaptationField ? [[TSAdaptationField initWithPcrBase:pcrBase
                                                                                              pcrExt:pcrExt
                                                                                remainingPayloadSize:remainingPayloadLength]
                                                                  getBytes] : nil;
        
        const NSUInteger remainingSpaceInPacket = TS_PACKET_SIZE - TS_PACKET_HEADER_SIZE - adaptationField.length;
        const NSUInteger packetPayloadSize = MIN(remainingSpaceInPacket, remainingPayloadLength);
        const NSUInteger payloadOffset = payload.length - remainingPayloadLength;
        
        TSPacketHeader *header = [[TSPacketHeader alloc] initWithTei:NO
                                                                pusi:isFirstPacket || forcePusi
                                                   transportPriority:NO
                                                                 pid:track.pid
                                                         isScrambled:NO
                                                      adaptationMode:adaptationField ? TSAdaptationModeAdaptationAndPayload : TSAdaptationModePayloadOnly
                                                   continuityCounter:track.continuityCounter];
        if (packetPayloadSize > 0) {
            // The cc shall not be incremented when the adaptation_field_control of the packet equals '00' or '10'.
            track.continuityCounter = track.continuityCounter + 1;
        }
        
        
        NSMutableData *tsPacket = [NSMutableData dataWithCapacity:TS_PACKET_SIZE];
        [tsPacket appendData:header.getBytes];
        if (adaptationField) {
            [tsPacket appendData:adaptationField];
        }
        [tsPacket appendBytes:(void*)payload.bytes + payloadOffset length:packetPayloadSize];
        if (tsPacket.length != TS_PACKET_SIZE) {
            NSString *msg = [NSString stringWithFormat:@"Invalid TS-packet size: %lu", (unsigned long)tsPacket.length];
            NSAssert(NO, msg);
        }
        onTsPacketCb(tsPacket);

        remainingPayloadLength -= packetPayloadSize;
        packetNumber = packetNumber + 1;
    }
}
@end
