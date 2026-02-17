//
//  TSTestUtils.m
//  TSMuxDemuxTests
//
//  Shared test utilities for creating TS packets.
//

#import "TSTestUtils.h"

@implementation TSTestUtils

+ (NSData *)createNullPackets:(NSUInteger)count packetSize:(NSUInteger)size {
    NSMutableData *chunk = [NSMutableData dataWithCapacity:count * size];
    for (NSUInteger i = 0; i < count; i++) {
        NSMutableData *packet = [NSMutableData dataWithLength:size];
        uint8_t *bytes = packet.mutableBytes;
        bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;  // 0x47
        bytes[1] = 0x1F;                         // PID high bits (null packet)
        bytes[2] = 0xFF;                         // PID low bits (0x1FFF = null packet)
        bytes[3] = 0x10;                         // Payload only, CC=0
        [chunk appendData:packet];
    }
    return chunk;
}

+ (TSPacket *)createPacketWithPid:(uint16_t)pid
                          payload:(NSData *)payload
                             pusi:(BOOL)pusi
                continuityCounter:(uint8_t)cc {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = (pusi ? 0x40 : 0x00) | ((pid >> 8) & 0x1F);
    bytes[2] = pid & 0xFF;
    bytes[3] = 0x10 | (cc & 0x0F);  // Payload only

    NSUInteger copyLen = MIN(payload.length, TS_PACKET_SIZE_188 - 4);
    memcpy(bytes + 4, payload.bytes, copyLen);

    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];
    return packets.firstObject;
}

+ (TSPacket *)createPacketWithPid:(uint16_t)pid
                          pcrBase:(uint64_t)pcrBase
                           pcrExt:(uint16_t)pcrExt
                continuityCounter:(uint8_t)cc {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = (pid >> 8) & 0x1F;
    bytes[2] = pid & 0xFF;
    bytes[3] = 0x30 | (cc & 0x0F);  // Adaptation + payload

    // Adaptation field (8 bytes: 1 length + 1 flags + 6 PCR)
    bytes[4] = 7;       // adaptation_field_length
    bytes[5] = 0x10;    // PCR flag set

    // Encode PCR
    bytes[6] = (pcrBase >> 25) & 0xFF;
    bytes[7] = (pcrBase >> 17) & 0xFF;
    bytes[8] = (pcrBase >> 9) & 0xFF;
    bytes[9] = (pcrBase >> 1) & 0xFF;
    bytes[10] = ((pcrBase & 0x01) << 7) | 0x7E | ((pcrExt >> 8) & 0x01);
    bytes[11] = pcrExt & 0xFF;

    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];
    return packets.firstObject;
}

+ (TSPacket *)createPsiPacketWithPid:(uint16_t)pid
                             tableId:(uint8_t)tableId
                    tableIdExtension:(uint16_t)tableIdExtension
                       versionNumber:(uint8_t)versionNumber
                       sectionNumber:(uint8_t)sectionNumber
                   lastSectionNumber:(uint8_t)lastSectionNumber
                             payload:(NSData *)payload
                   continuityCounter:(uint8_t)cc {
    // Build raw 188-byte TS packet
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    // TS Header (4 bytes)
    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;                    // Sync byte 0x47
    bytes[1] = 0x40 | ((pid >> 8) & 0x1F);                    // PUSI=1, PID high bits
    bytes[2] = pid & 0xFF;                                     // PID low bits
    bytes[3] = 0x10 | (cc & 0x0F);                            // Payload only, CC

    // TS Payload starts at byte 4
    NSUInteger offset = 4;

    // Pointer field (1 byte) - 0 means section starts immediately after
    bytes[offset++] = 0x00;

    // PSI Section Header
    bytes[offset++] = tableId;                                 // Table ID

    // Build section data to calculate section_length
    NSMutableData *sectionData = [NSMutableData data];

    // Table ID extension (2 bytes)
    uint16_t tidExt = CFSwapInt16HostToBig(tableIdExtension);
    [sectionData appendBytes:&tidExt length:2];

    // Reserved + version + current_next (1 byte): 11vvvvvc
    uint8_t versionByte = 0xC0 | ((versionNumber & 0x1F) << 1) | 0x01;
    [sectionData appendBytes:&versionByte length:1];

    // Section number
    [sectionData appendBytes:&sectionNumber length:1];

    // Last section number
    [sectionData appendBytes:&lastSectionNumber length:1];

    // Payload
    if (payload) {
        [sectionData appendData:payload];
    }

    // section_length = sectionData.length + CRC (4 bytes)
    uint16_t sectionLength = (uint16_t)(sectionData.length + 4);

    // Section syntax indicator (1) + private bit (0) + reserved (11) + section_length (12 bits)
    uint16_t byte2and3 = 0xB000 | (sectionLength & 0x0FFF);
    bytes[offset++] = (byte2and3 >> 8) & 0xFF;
    bytes[offset++] = byte2and3 & 0xFF;

    // Section data (excluding CRC)
    memcpy(bytes + offset, sectionData.bytes, sectionData.length);
    offset += sectionData.length;

    // CRC32 (4 bytes) - use dummy value for testing
    uint32_t crc = CFSwapInt32HostToBig(0x12345678);
    memcpy(bytes + offset, &crc, 4);
    offset += 4;

    // Fill rest with stuffing bytes (0xFF)
    while (offset < TS_PACKET_SIZE_188) {
        bytes[offset++] = 0xFF;
    }

    // Parse raw data into TSPacket
    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];
    return packets.firstObject;
}

+ (TSPacket *)createPacketWithPesPayload:(NSData *)payload {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x40 | 0x01;  // PUSI=1, PID high bits
    bytes[2] = 0x00;
    bytes[3] = 0x10;  // Payload only

    NSUInteger copyLen = MIN(payload.length, TS_PACKET_SIZE_188 - 4);
    memcpy(bytes + 4, payload.bytes, copyLen);

    NSArray<TSPacket *> *packets = [TSPacket packetsFromChunkedTsData:packet packetSize:TS_PACKET_SIZE_188];
    return packets.firstObject;
}

#pragma mark - PAT/PMT Utilities

+ (NSData *)createPatDataWithPmtPid:(uint16_t)pmtPid {
    // Use the muxer to create a proper PAT payload (includes pointer field)
    TSProgramAssociationTable *pat = [[TSProgramAssociationTable alloc]
                                      initWithTransportStreamId:1
                                      programmes:@{@1: @(pmtPid)}];
    NSData *patPayload = [pat toTsPacketPayload];

    // Wrap in TS packet on PID 0
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x40;  // PUSI=1, PID=0
    bytes[2] = 0x00;
    bytes[3] = 0x10;  // Payload only, CC=0

    // Copy PAT payload (already includes pointer field)
    NSUInteger copyLen = MIN(patPayload.length, TS_PACKET_SIZE_188 - 4);
    memcpy(bytes + 4, patPayload.bytes, copyLen);

    // Fill rest with stuffing
    for (NSUInteger i = 4 + copyLen; i < TS_PACKET_SIZE_188; i++) {
        bytes[i] = 0xFF;
    }

    return packet;
}

+ (NSData *)createPmtDataWithPmtPid:(uint16_t)pmtPid
                             pcrPid:(uint16_t)pcrPid
                 elementaryStreamPid:(uint16_t)elementaryStreamPid
                          streamType:(uint8_t)streamType {
    // Create elementary stream
    TSElementaryStream *es = [[TSElementaryStream alloc] initWithPid:elementaryStreamPid
                                                          streamType:streamType
                                                         descriptors:nil];

    // Use the muxer to create a proper PMT payload (includes pointer field)
    TSProgramMapTable *pmt = [[TSProgramMapTable alloc] initWithProgramNumber:1
                                                                versionNumber:0
                                                                       pcrPid:pcrPid
                                                            elementaryStreams:[NSSet setWithObject:es]];
    NSData *pmtPayload = [pmt toTsPacketPayload];

    // Wrap in TS packet
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x40 | ((pmtPid >> 8) & 0x1F);  // PUSI=1
    bytes[2] = pmtPid & 0xFF;
    bytes[3] = 0x10;  // Payload only, CC=0

    // Copy PMT payload (already includes pointer field)
    NSUInteger copyLen = MIN(pmtPayload.length, TS_PACKET_SIZE_188 - 4);
    memcpy(bytes + 4, pmtPayload.bytes, copyLen);

    // Fill rest with stuffing
    for (NSUInteger i = 4 + copyLen; i < TS_PACKET_SIZE_188; i++) {
        bytes[i] = 0xFF;
    }

    return packet;
}

+ (NSData *)createPesDataWithTrack:(TSElementaryStream *)track
                           payload:(NSData *)payload
                               pts:(CMTime)pts {
    // Create an access unit and use the muxer to generate PES
    TSAccessUnit *au = [[TSAccessUnit alloc] initWithPid:track.pid
                                                     pts:pts
                                                     dts:kCMTimeInvalid
                                         isDiscontinuous:NO
                                      isRandomAccessPoint:NO
                                              streamType:track.streamType
                                             descriptors:track.descriptors
                                          compressedData:payload];

    NSData *pesPayload = [au toTsPacketPayloadWithEpoch:kCMTimeInvalid];

    // Packetize into TS packets (track maintains CC across calls)
    NSMutableData *result = [NSMutableData data];
    [TSPacket packetizePayload:pesPayload
                         track:track

                       pcrBase:kNoPcr
                        pcrExt:0
             discontinuityFlag:NO
              randomAccessFlag:NO
                onTsPacketData:^(NSData * _Nonnull tsPacketData, uint16_t pid, uint8_t cc) {
        [result appendData:tsPacketData];
    }];

    return result;
}

+ (NSData *)createRawPacketDataWithPid:(uint16_t)pid
                               payload:(NSData *)payload
                                  pusi:(BOOL)pusi
                     continuityCounter:(uint8_t)cc {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = (pusi ? 0x40 : 0x00) | ((pid >> 8) & 0x1F);
    bytes[2] = pid & 0xFF;
    bytes[3] = 0x10 | (cc & 0x0F);  // Payload only

    NSUInteger copyLen = MIN(payload.length, TS_PACKET_SIZE_188 - 4);
    if (payload && copyLen > 0) {
        memcpy(bytes + 4, payload.bytes, copyLen);
    }

    // Fill rest with stuffing
    for (NSUInteger i = 4 + copyLen; i < TS_PACKET_SIZE_188; i++) {
        bytes[i] = 0xFF;
    }

    return packet;
}

+ (NSData *)createPacketWithAdaptationFieldPid:(uint16_t)pid
                             discontinuityFlag:(BOOL)discontinuityFlag
                                    hasPayload:(BOOL)hasPayload
                             continuityCounter:(uint8_t)cc {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = (pid >> 8) & 0x1F;
    bytes[2] = pid & 0xFF;

    // adaptation_field_control: 10 = adaptation only, 11 = adaptation + payload
    uint8_t adaptationControl = hasPayload ? 0x30 : 0x20;
    bytes[3] = adaptationControl | (cc & 0x0F);

    // Adaptation field
    if (hasPayload) {
        bytes[4] = 1;  // adaptation_field_length (just flags, no optional fields)
        bytes[5] = discontinuityFlag ? 0x80 : 0x00;  // discontinuity_indicator flag
        // Payload starts at byte 6, fill with stuffing
        for (NSUInteger i = 6; i < TS_PACKET_SIZE_188; i++) {
            bytes[i] = 0xFF;
        }
    } else {
        // Adaptation only - fill entire remaining space
        bytes[4] = 183;  // adaptation_field_length (fills rest of packet)
        bytes[5] = discontinuityFlag ? 0x80 : 0x00;
        // Fill rest with stuffing
        for (NSUInteger i = 6; i < TS_PACKET_SIZE_188; i++) {
            bytes[i] = 0xFF;
        }
    }

    return packet;
}

+ (NSData *)createPesDataWithTrack:(TSElementaryStream *)track
                           payload:(NSData *)payload
                               pts:(CMTime)pts
                           startCC:(uint8_t)startCC {
    // Set track's CC so the next packet will use startCC
    // (packetizer increments before using, so we set to startCC - 1)
    track.continuityCounter = (startCC - 1) & 0x0F;
    return [self createPesDataWithTrack:track payload:payload pts:pts];
}

+ (NSData *)createPmtDataWithPmtPid:(uint16_t)pmtPid
                             pcrPid:(uint16_t)pcrPid
                            streams:(NSArray<TSElementaryStream *> *)streams
                      versionNumber:(uint8_t)versionNumber
                  continuityCounter:(uint8_t)cc {
    return [self createPmtDataWithPmtPid:pmtPid
                           programNumber:1
                                  pcrPid:pcrPid
                                 streams:streams
                           versionNumber:versionNumber
                       continuityCounter:cc];
}

+ (NSData *)createPmtDataWithPmtPid:(uint16_t)pmtPid
                      programNumber:(uint16_t)programNumber
                             pcrPid:(uint16_t)pcrPid
                            streams:(NSArray<TSElementaryStream *> *)streams
                      versionNumber:(uint8_t)versionNumber
                  continuityCounter:(uint8_t)cc {
    // Create PMT using the muxer
    NSSet *streamSet = [NSSet setWithArray:streams];
    TSProgramMapTable *pmt = [[TSProgramMapTable alloc] initWithProgramNumber:programNumber
                                                                versionNumber:versionNumber
                                                                       pcrPid:pcrPid
                                                            elementaryStreams:streamSet];
    NSData *pmtPayload = [pmt toTsPacketPayload];

    // Wrap in TS packet
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x40 | ((pmtPid >> 8) & 0x1F);  // PUSI=1
    bytes[2] = pmtPid & 0xFF;
    bytes[3] = 0x10 | (cc & 0x0F);  // Payload only

    // Copy PMT payload
    NSUInteger copyLen = MIN(pmtPayload.length, TS_PACKET_SIZE_188 - 4);
    memcpy(bytes + 4, pmtPayload.bytes, copyLen);

    // Fill rest with stuffing
    for (NSUInteger i = 4 + copyLen; i < TS_PACKET_SIZE_188; i++) {
        bytes[i] = 0xFF;
    }

    return packet;
}

#pragma mark - Extended PAT Utilities

+ (NSData *)createPatDataWithProgrammes:(NSDictionary<NSNumber *, NSNumber *> *)programmes
                          versionNumber:(uint8_t)versionNumber
                      continuityCounter:(uint8_t)cc {
    // Create PAT using the muxer
    TSProgramAssociationTable *pat = [[TSProgramAssociationTable alloc]
                                      initWithTransportStreamId:1
                                      programmes:programmes];
    NSData *patPayload = [pat toTsPacketPayload];

    // Wrap in TS packet on PID 0
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x40;  // PUSI=1, PID=0
    bytes[2] = 0x00;
    bytes[3] = 0x10 | (cc & 0x0F);  // Payload only

    // Copy PAT payload (already includes pointer field)
    NSUInteger copyLen = MIN(patPayload.length, TS_PACKET_SIZE_188 - 4);
    memcpy(bytes + 4, patPayload.bytes, copyLen);

    // Patch version number in the PAT section data
    // Byte layout: pointer(1) + table_id(1) + section_syntax+length(2) + tsid(2) + version_byte(1)
    // version_byte is at offset 4 + 1 + 1 + 2 + 2 = 10
    // Format: 11vvvvvc (reserved + version + current_next)
    bytes[10] = 0xC0 | ((versionNumber & 0x1F) << 1) | 0x01;

    // Fill rest with stuffing
    for (NSUInteger i = 4 + copyLen; i < TS_PACKET_SIZE_188; i++) {
        bytes[i] = 0xFF;
    }

    return packet;
}

#pragma mark - Edge Case Utilities

+ (NSData *)createPacketWithTeiSetForPid:(uint16_t)pid
                       continuityCounter:(uint8_t)cc {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x80 | ((pid >> 8) & 0x1F);  // TEI=1, PUSI=0
    bytes[2] = pid & 0xFF;
    bytes[3] = 0x10 | (cc & 0x0F);  // Payload only

    // Fill with stuffing
    for (NSUInteger i = 4; i < TS_PACKET_SIZE_188; i++) {
        bytes[i] = 0xFF;
    }

    return packet;
}

+ (NSData *)createPacketWithInvalidSyncByte:(uint8_t)syncByte
                                        pid:(uint16_t)pid {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = syncByte;  // Invalid sync byte (not 0x47)
    bytes[1] = (pid >> 8) & 0x1F;
    bytes[2] = pid & 0xFF;
    bytes[3] = 0x10;  // Payload only, CC=0

    // Fill with stuffing
    for (NSUInteger i = 4; i < TS_PACKET_SIZE_188; i++) {
        bytes[i] = 0xFF;
    }

    return packet;
}

+ (NSData *)createScrambledPacketWithPid:(uint16_t)pid
                       continuityCounter:(uint8_t)cc {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = (pid >> 8) & 0x1F;
    bytes[2] = pid & 0xFF;
    bytes[3] = 0x50 | (cc & 0x0F);  // scrambling_control=01 (scrambled), payload only

    // Fill with stuffing
    for (NSUInteger i = 4; i < TS_PACKET_SIZE_188; i++) {
        bytes[i] = 0xFF;
    }

    return packet;
}

+ (NSData *)createPacketWithNoPayloadNorAdaptationForPid:(uint16_t)pid
                                       continuityCounter:(uint8_t)cc {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = (pid >> 8) & 0x1F;
    bytes[2] = pid & 0xFF;
    bytes[3] = 0x00 | (cc & 0x0F);  // adaptation_field_control=00 (reserved)

    // Fill with stuffing
    for (NSUInteger i = 4; i < TS_PACKET_SIZE_188; i++) {
        bytes[i] = 0xFF;
    }

    return packet;
}

#pragma mark - DVB SDT Utilities

+ (NSData *)createSdtDataWithTransportStreamId:(uint16_t)transportStreamId
                             originalNetworkId:(uint16_t)originalNetworkId
                                     serviceId:(uint16_t)serviceId
                                 versionNumber:(uint8_t)versionNumber
                             continuityCounter:(uint8_t)cc {
    // Build SDT section manually
    // SDT structure:
    // - table_id (8 bits) = 0x42 for actual TS
    // - section_syntax_indicator (1) + reserved (1) + reserved (2) + section_length (12)
    // - transport_stream_id (16)
    // - reserved (2) + version_number (5) + current_next_indicator (1)
    // - section_number (8)
    // - last_section_number (8)
    // - original_network_id (16)
    // - reserved_future_use (8)
    // - Service loop:
    //   - service_id (16)
    //   - reserved (6) + EIT_schedule_flag (1) + EIT_present_following_flag (1)
    //   - running_status (3) + free_CA_mode (1) + descriptors_loop_length (12)
    //   - descriptors
    // - CRC_32 (32)

    NSMutableData *section = [NSMutableData data];

    // original_network_id (2 bytes)
    uint16_t oni = CFSwapInt16HostToBig(originalNetworkId);
    [section appendBytes:&oni length:2];

    // reserved_future_use (1 byte)
    uint8_t reserved = 0xFF;
    [section appendBytes:&reserved length:1];

    // Service entry
    // service_id (2 bytes)
    uint16_t sid = CFSwapInt16HostToBig(serviceId);
    [section appendBytes:&sid length:2];

    // reserved (6) + EIT_schedule_flag (1) + EIT_present_following_flag (1)
    uint8_t flags1 = 0xFC | 0x02 | 0x01;  // reserved + both EIT flags set
    [section appendBytes:&flags1 length:1];

    // running_status (3) + free_CA_mode (1) + descriptors_loop_length (12)
    // running_status = 4 (running), free_CA_mode = 0
    uint16_t flags2 = 0x8000 | 0x0000;  // running (4<<13) | no descriptors
    flags2 = CFSwapInt16HostToBig(flags2);
    [section appendBytes:&flags2 length:2];

    // Build TS packet with PSI header
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    // TS Header
    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x40 | ((0x11 >> 8) & 0x1F);  // PUSI=1, PID=0x11
    bytes[2] = 0x11;
    bytes[3] = 0x10 | (cc & 0x0F);

    NSUInteger offset = 4;

    // Pointer field
    bytes[offset++] = 0x00;

    // Table ID (SDT actual TS = 0x42)
    bytes[offset++] = 0x42;

    // Section length (includes header fields after length + section data + CRC)
    // = 5 (tsid + version + section_num + last_section_num) + section.length + 4 (CRC)
    uint16_t sectionLength = 5 + (uint16_t)section.length + 4;
    bytes[offset++] = 0xB0 | ((sectionLength >> 8) & 0x0F);  // section_syntax_indicator=1
    bytes[offset++] = sectionLength & 0xFF;

    // transport_stream_id
    bytes[offset++] = (transportStreamId >> 8) & 0xFF;
    bytes[offset++] = transportStreamId & 0xFF;

    // reserved + version + current_next
    bytes[offset++] = 0xC0 | ((versionNumber & 0x1F) << 1) | 0x01;

    // section_number
    bytes[offset++] = 0x00;

    // last_section_number
    bytes[offset++] = 0x00;

    // Section data
    memcpy(bytes + offset, section.bytes, section.length);
    offset += section.length;

    // CRC32 (dummy for testing)
    uint32_t crc = CFSwapInt32HostToBig(0x12345678);
    memcpy(bytes + offset, &crc, 4);
    offset += 4;

    // Fill rest with stuffing
    while (offset < TS_PACKET_SIZE_188) {
        bytes[offset++] = 0xFF;
    }

    return packet;
}

#pragma mark - ATSC VCT Utilities

+ (NSData *)createTvctDataWithTransportStreamId:(uint16_t)transportStreamId
                                    channelName:(NSString *)channelName
                                   majorChannel:(uint16_t)majorChannel
                                   minorChannel:(uint16_t)minorChannel
                                  programNumber:(uint16_t)programNumber
                                  versionNumber:(uint8_t)versionNumber
                              continuityCounter:(uint8_t)cc {
    // Build VCT section manually
    // VCT structure after standard PSI header:
    // - protocol_version (8)
    // - num_channels_in_section (8)
    // - Channel loop (32 bytes each minimum):
    //   - short_name (7 x 16-bit UTF-16BE = 14 bytes)
    //   - major_channel_number (10 bits) + minor_channel_number (10 bits) + modulation (8 bits) = 4 bytes
    //   - carrier_frequency (32 bits) = 4 bytes
    //   - channel_TSID (16 bits) = 2 bytes
    //   - program_number (16 bits) = 2 bytes
    //   - flags (16 bits) = 2 bytes
    //   - source_id (16 bits) = 2 bytes
    //   - descriptors_length (16 bits) = 2 bytes
    //   - descriptors
    // - additional_descriptors_length (16 bits)
    // - additional descriptors
    // - CRC_32 (32)

    NSMutableData *section = [NSMutableData data];

    // protocol_version
    uint8_t protocolVersion = 0x00;
    [section appendBytes:&protocolVersion length:1];

    // num_channels_in_section
    uint8_t numChannels = 1;
    [section appendBytes:&numChannels length:1];

    // Channel entry
    // short_name: 7 x UTF-16BE chars (14 bytes)
    uint8_t nameBytes[14] = {0};
    NSData *nameData = [channelName dataUsingEncoding:NSUTF16BigEndianStringEncoding];
    NSUInteger nameCopyLen = MIN(nameData.length, 14);
    memcpy(nameBytes, nameData.bytes, nameCopyLen);
    [section appendBytes:nameBytes length:14];

    // major/minor channel + modulation
    // Bits: rrrr_mmmm_mmmm_mm nn_nnnn_nnnn_MMMM_MMMM
    uint32_t channelBits = ((majorChannel & 0x3FF) << 18) | ((minorChannel & 0x3FF) << 8) | 0x04;  // modulation=0x04 (8VSB)
    uint8_t channelBytes[4];
    channelBytes[0] = (channelBits >> 24) & 0xFF;
    channelBytes[1] = (channelBits >> 16) & 0xFF;
    channelBytes[2] = (channelBits >> 8) & 0xFF;
    channelBytes[3] = channelBits & 0xFF;
    [section appendBytes:channelBytes length:4];

    // carrier_frequency (deprecated, set to 0)
    uint32_t carrierFreq = 0;
    [section appendBytes:&carrierFreq length:4];

    // channel_TSID
    uint16_t chTsid = CFSwapInt16HostToBig(transportStreamId);
    [section appendBytes:&chTsid length:2];

    // program_number
    uint16_t progNum = CFSwapInt16HostToBig(programNumber);
    [section appendBytes:&progNum length:2];

    // flags1: ETM_location (2) + access_controlled (1) + hidden (1) + path_select (1) + out_of_band (1) + hide_guide (1) + reserved (1)
    uint8_t flags1 = 0x00;  // all flags clear
    [section appendBytes:&flags1 length:1];

    // flags2: reserved (2) + service_type (6)
    uint8_t flags2 = 0x02;  // service_type = digital TV
    [section appendBytes:&flags2 length:1];

    // source_id
    uint16_t sourceId = CFSwapInt16HostToBig(programNumber);  // Use program number as source ID
    [section appendBytes:&sourceId length:2];

    // descriptors_length (no descriptors)
    uint16_t descLen = 0;
    [section appendBytes:&descLen length:2];

    // additional_descriptors_length (no additional descriptors)
    uint16_t addDescLen = 0;
    [section appendBytes:&addDescLen length:2];

    // Build TS packet with PSI header
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    // TS Header (PID = 0x1FFB for ATSC PSIP)
    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x40 | ((0x1FFB >> 8) & 0x1F);  // PUSI=1
    bytes[2] = 0x1FFB & 0xFF;
    bytes[3] = 0x10 | (cc & 0x0F);

    NSUInteger offset = 4;

    // Pointer field
    bytes[offset++] = 0x00;

    // Table ID (TVCT = 0xC8)
    bytes[offset++] = 0xC8;

    // Section length
    uint16_t sectionLength = 5 + (uint16_t)section.length + 4;  // header + data + CRC
    bytes[offset++] = 0xB0 | ((sectionLength >> 8) & 0x0F);
    bytes[offset++] = sectionLength & 0xFF;

    // transport_stream_id
    bytes[offset++] = (transportStreamId >> 8) & 0xFF;
    bytes[offset++] = transportStreamId & 0xFF;

    // reserved + version + current_next
    bytes[offset++] = 0xC0 | ((versionNumber & 0x1F) << 1) | 0x01;

    // section_number
    bytes[offset++] = 0x00;

    // last_section_number
    bytes[offset++] = 0x00;

    // Section data
    memcpy(bytes + offset, section.bytes, section.length);
    offset += section.length;

    // CRC32 (dummy)
    uint32_t crc = CFSwapInt32HostToBig(0x12345678);
    memcpy(bytes + offset, &crc, 4);
    offset += 4;

    // Fill rest with stuffing
    while (offset < TS_PACKET_SIZE_188) {
        bytes[offset++] = 0xFF;
    }

    return packet;
}

#pragma mark - TR 101 290 Test Utilities

+ (NSData *)createValidPacketWithPid:(uint16_t)pid
                   continuityCounter:(uint8_t)cc {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;  // Valid sync byte 0x47
    bytes[1] = (pid >> 8) & 0x1F;
    bytes[2] = pid & 0xFF;
    bytes[3] = 0x10 | (cc & 0x0F);  // Payload only

    // Fill with stuffing
    for (NSUInteger i = 4; i < TS_PACKET_SIZE_188; i++) {
        bytes[i] = 0xFF;
    }

    return packet;
}

+ (NSData *)createPacketWithCorruptedSyncByte:(uint8_t)corruptedSyncByte
                                          pid:(uint16_t)pid
                            continuityCounter:(uint8_t)cc {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    bytes[0] = corruptedSyncByte;  // Corrupted sync byte (not 0x47)
    bytes[1] = (pid >> 8) & 0x1F;
    bytes[2] = pid & 0xFF;
    bytes[3] = 0x10 | (cc & 0x0F);

    for (NSUInteger i = 4; i < TS_PACKET_SIZE_188; i++) {
        bytes[i] = 0xFF;
    }

    return packet;
}

+ (NSData *)createPsiPacketOnPid:(uint16_t)pid
                         tableId:(uint8_t)tableId
               continuityCounter:(uint8_t)cc {
    NSMutableData *packet = [NSMutableData dataWithLength:TS_PACKET_SIZE_188];
    uint8_t *bytes = packet.mutableBytes;

    // TS Header
    bytes[0] = TS_PACKET_HEADER_SYNC_BYTE;
    bytes[1] = 0x40 | ((pid >> 8) & 0x1F);  // PUSI=1
    bytes[2] = pid & 0xFF;
    bytes[3] = 0x10 | (cc & 0x0F);  // Payload only

    NSUInteger offset = 4;

    // Pointer field
    bytes[offset++] = 0x00;

    // Table ID
    bytes[offset++] = tableId;

    // Section length (minimal section - just 5 bytes of header + 4 CRC)
    uint16_t sectionLength = 9;
    bytes[offset++] = 0xB0 | ((sectionLength >> 8) & 0x0F);  // section_syntax_indicator=1
    bytes[offset++] = sectionLength & 0xFF;

    // Table ID extension
    bytes[offset++] = 0x00;
    bytes[offset++] = 0x01;

    // Version/current_next
    bytes[offset++] = 0xC1;  // reserved + version 0 + current_next=1

    // Section number
    bytes[offset++] = 0x00;

    // Last section number
    bytes[offset++] = 0x00;

    // CRC32 (dummy)
    uint32_t crc = CFSwapInt32HostToBig(0x12345678);
    memcpy(bytes + offset, &crc, 4);
    offset += 4;

    // Fill rest with stuffing
    while (offset < TS_PACKET_SIZE_188) {
        bytes[offset++] = 0xFF;
    }

    return packet;
}

@end
