//
//  TSTestUtils.h
//  TSMuxDemuxTests
//
//  Shared test utilities for creating TS packets.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
@import TSMuxDemux;

NS_ASSUME_NONNULL_BEGIN

@interface TSTestUtils : NSObject

/// Creates valid TS packet data with proper sync bytes and null packet PID (0x1FFF).
+ (NSData *)createNullPackets:(NSUInteger)count packetSize:(NSUInteger)size;

/// Creates a single TS packet with the given payload. PUSI is set.
+ (TSPacket *)createPacketWithPid:(uint16_t)pid
                          payload:(NSData *)payload
                             pusi:(BOOL)pusi
                continuityCounter:(uint8_t)cc;

/// Creates a TS packet with adaptation field containing PCR.
+ (TSPacket *)createPacketWithPid:(uint16_t)pid
                          pcrBase:(uint64_t)pcrBase
                           pcrExt:(uint16_t)pcrExt
                continuityCounter:(uint8_t)cc;

/// Creates a TS packet containing a complete PSI section.
+ (TSPacket *)createPsiPacketWithPid:(uint16_t)pid
                             tableId:(uint8_t)tableId
                    tableIdExtension:(uint16_t)tableIdExtension
                       versionNumber:(uint8_t)versionNumber
                       sectionNumber:(uint8_t)sectionNumber
                   lastSectionNumber:(uint8_t)lastSectionNumber
                             payload:(nullable NSData *)payload
                   continuityCounter:(uint8_t)cc;

/// Creates a TS packet with PUSI=1 containing the given PES payload.
+ (TSPacket *)createPacketWithPesPayload:(NSData *)payload;

#pragma mark - PAT/PMT Utilities

/// Creates raw TS data containing a PAT packet.
/// @param pmtPid The PID where the PMT will be found.
+ (NSData *)createPatDataWithPmtPid:(uint16_t)pmtPid;

/// Creates raw TS data containing a PMT packet.
/// @param pmtPid The PID for this PMT packet.
/// @param pcrPid The PID carrying PCR.
/// @param elementaryStreamPid The PID for the elementary stream.
/// @param streamType The stream type (e.g., kRawStreamTypeH264).
+ (NSData *)createPmtDataWithPmtPid:(uint16_t)pmtPid
                             pcrPid:(uint16_t)pcrPid
                 elementaryStreamPid:(uint16_t)elementaryStreamPid
                          streamType:(uint8_t)streamType;

/// Creates raw TS data containing PES packets for the given access unit payload.
/// @param track The elementary stream (continuity counter is maintained across calls).
/// @param payload The compressed data payload.
/// @param pts Presentation timestamp (pass kCMTimeInvalid for none).
+ (NSData *)createPesDataWithTrack:(TSElementaryStream *)track
                           payload:(NSData *)payload
                               pts:(CMTime)pts;

/// Creates a single TS packet with specific continuity counter for testing CC handling.
/// @param pid The packet PID.
/// @param payload Raw payload data (not PES wrapped).
/// @param pusi Payload unit start indicator.
/// @param cc The specific continuity counter value (0-15).
+ (NSData *)createRawPacketDataWithPid:(uint16_t)pid
                               payload:(NSData *)payload
                                  pusi:(BOOL)pusi
                     continuityCounter:(uint8_t)cc;

/// Creates a TS packet with adaptation field containing discontinuity flag.
/// @param pid The packet PID.
/// @param discontinuityFlag Set to YES to signal discontinuity.
/// @param hasPayload Set to YES to include payload data.
/// @param cc The continuity counter value (0-15).
+ (NSData *)createPacketWithAdaptationFieldPid:(uint16_t)pid
                             discontinuityFlag:(BOOL)discontinuityFlag
                                    hasPayload:(BOOL)hasPayload
                             continuityCounter:(uint8_t)cc;

/// Creates raw TS data containing PES packets with explicit starting CC.
/// @param track The elementary stream (continuity counter is set before packetization).
/// @param payload The compressed data payload.
/// @param pts Presentation timestamp (pass kCMTimeInvalid for none).
/// @param startCC The starting continuity counter value (track's CC is set to this - 1).
+ (NSData *)createPesDataWithTrack:(TSElementaryStream *)track
                           payload:(NSData *)payload
                               pts:(CMTime)pts
                           startCC:(uint8_t)startCC;

/// Creates raw TS data containing a PMT packet with multiple elementary streams.
/// @param pmtPid The PID for this PMT packet.
/// @param pcrPid The PID carrying PCR.
/// @param streams Array of TSElementaryStream objects.
/// @param versionNumber PMT version (0-31).
/// @param cc Continuity counter value.
+ (NSData *)createPmtDataWithPmtPid:(uint16_t)pmtPid
                             pcrPid:(uint16_t)pcrPid
                            streams:(NSArray<TSElementaryStream *> *)streams
                      versionNumber:(uint8_t)versionNumber
                  continuityCounter:(uint8_t)cc;

/// Creates raw TS data containing a PMT packet with specified program number.
/// @param pmtPid The PID for this PMT packet.
/// @param programNumber The program number for this PMT.
/// @param pcrPid The PID carrying PCR.
/// @param streams Array of TSElementaryStream objects.
/// @param versionNumber PMT version (0-31).
/// @param cc Continuity counter value.
+ (NSData *)createPmtDataWithPmtPid:(uint16_t)pmtPid
                      programNumber:(uint16_t)programNumber
                             pcrPid:(uint16_t)pcrPid
                            streams:(NSArray<TSElementaryStream *> *)streams
                      versionNumber:(uint8_t)versionNumber
                  continuityCounter:(uint8_t)cc;

#pragma mark - DVB SDT Utilities

/// Creates raw TS data containing a DVB SDT packet.
/// @param transportStreamId The transport stream ID.
/// @param originalNetworkId The original network ID.
/// @param serviceId The service ID for the single service entry.
/// @param versionNumber SDT version (0-31).
/// @param cc Continuity counter value.
+ (NSData *)createSdtDataWithTransportStreamId:(uint16_t)transportStreamId
                             originalNetworkId:(uint16_t)originalNetworkId
                                     serviceId:(uint16_t)serviceId
                                 versionNumber:(uint8_t)versionNumber
                             continuityCounter:(uint8_t)cc;

#pragma mark - Extended PAT Utilities

/// Creates raw TS data containing a PAT packet with multiple programs.
/// @param programmes Dictionary mapping program numbers to PMT PIDs.
/// @param versionNumber PAT version (0-31).
/// @param cc Continuity counter value.
+ (NSData *)createPatDataWithProgrammes:(NSDictionary<NSNumber *, NSNumber *> *)programmes
                          versionNumber:(uint8_t)versionNumber
                      continuityCounter:(uint8_t)cc;

#pragma mark - Edge Case Utilities

/// Creates a TS packet with the Transport Error Indicator (TEI) flag set.
/// @param pid The packet PID.
/// @param cc Continuity counter value.
+ (NSData *)createPacketWithTeiSetForPid:(uint16_t)pid
                       continuityCounter:(uint8_t)cc;

/// Creates a TS packet with an invalid sync byte.
/// @param syncByte The invalid sync byte to use (not 0x47).
/// @param pid The packet PID.
+ (NSData *)createPacketWithInvalidSyncByte:(uint8_t)syncByte
                                        pid:(uint16_t)pid;

/// Creates a TS packet with scrambling control set (indicating scrambled content).
/// @param pid The packet PID.
/// @param cc Continuity counter value.
+ (NSData *)createScrambledPacketWithPid:(uint16_t)pid
                       continuityCounter:(uint8_t)cc;

/// Creates a TS packet with adaptation_field_control = 00 (reserved, no payload).
/// @param pid The packet PID.
/// @param cc Continuity counter value.
+ (NSData *)createPacketWithNoPayloadNorAdaptationForPid:(uint16_t)pid
                                       continuityCounter:(uint8_t)cc;

#pragma mark - ATSC VCT Utilities

/// Creates raw TS data containing an ATSC TVCT packet.
/// @param transportStreamId The transport stream ID.
/// @param channelName Short channel name (max 7 chars).
/// @param majorChannel Major channel number.
/// @param minorChannel Minor channel number.
/// @param programNumber Program number.
/// @param versionNumber VCT version (0-31).
/// @param cc Continuity counter value.
+ (NSData *)createTvctDataWithTransportStreamId:(uint16_t)transportStreamId
                                    channelName:(NSString *)channelName
                                   majorChannel:(uint16_t)majorChannel
                                   minorChannel:(uint16_t)minorChannel
                                  programNumber:(uint16_t)programNumber
                                  versionNumber:(uint8_t)versionNumber
                              continuityCounter:(uint8_t)cc;

#pragma mark - TR 101 290 Test Utilities

/// Creates a valid TS packet for sync acquisition (proper 0x47 sync byte).
/// @param pid The packet PID.
/// @param cc Continuity counter value.
+ (NSData *)createValidPacketWithPid:(uint16_t)pid
                   continuityCounter:(uint8_t)cc;

/// Creates a TS packet with a corrupted sync byte for sync loss testing.
/// @param corruptedSyncByte The invalid sync byte value.
/// @param pid The packet PID.
/// @param cc Continuity counter value.
+ (NSData *)createPacketWithCorruptedSyncByte:(uint8_t)corruptedSyncByte
                                          pid:(uint16_t)pid
                            continuityCounter:(uint8_t)cc;

/// Creates a PSI section packet on a specific PID with a specific table ID.
/// Used for testing PAT error when wrong table_id appears on PID 0x0000.
/// @param pid The packet PID.
/// @param tableId The table ID for the section.
/// @param cc Continuity counter value.
+ (NSData *)createPsiPacketOnPid:(uint16_t)pid
                         tableId:(uint8_t)tableId
               continuityCounter:(uint8_t)cc;

@end

NS_ASSUME_NONNULL_END
