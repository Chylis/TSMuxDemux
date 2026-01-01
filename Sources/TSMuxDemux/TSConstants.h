//
//  TSConstants.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>

/// Demuxer operating mode - determines which broadcast standard's signaling tables are parsed.
/// - DVB: https://www.etsi.org/deliver/etsi_en/300400_300499/300468/01.17.01_60/en_300468v011701p.pdf
/// - ATSC: https://www.atsc.org/wp-content/uploads/2021/04/A65_2013.pdf
typedef NS_ENUM(NSUInteger, TSDemuxerMode) {
    /// European Digital Video Broadcasting standard.
    TSDemuxerModeDVB,
    /// North American Advanced Television Systems Committee standard.
    TSDemuxerModeATSC,
};

typedef NSNumber *ProgramNumber;
typedef NSNumber *Pid; // NSNumber.unsignedShortValue (A PID is a 13-bit value in a uint16_t)

FOUNDATION_EXPORT uint32_t const TS_TIMESTAMP_TIMESCALE;

FOUNDATION_EXPORT uint8_t const TS_PACKET_SIZE_188;
FOUNDATION_EXPORT uint8_t const TS_PACKET_SIZE_204;
FOUNDATION_EXPORT uint8_t const TS_RS_PARITY_SIZE;
FOUNDATION_EXPORT uint8_t const TS_PACKET_HEADER_SIZE;
FOUNDATION_EXPORT uint8_t const TS_PACKET_HEADER_SYNC_BYTE;
FOUNDATION_EXPORT uint8_t const TS_PACKET_MAX_PAYLOAD_SIZE;

// ISO/IEC 13818-1 MPEG-TS
FOUNDATION_EXPORT NSUInteger const TABLE_ID_PAT;
FOUNDATION_EXPORT NSUInteger const TABLE_ID_PMT;
FOUNDATION_EXPORT NSUInteger const PID_PAT;
FOUNDATION_EXPORT NSUInteger const PID_CAT;
FOUNDATION_EXPORT NSUInteger const PID_TSDT;
FOUNDATION_EXPORT NSUInteger const PID_IPMP;
FOUNDATION_EXPORT NSUInteger const PID_ASI;
// "Other" PIDs (range 16-8190) may be PMT, network PID, elementary PID, etc...
// https://en.wikipedia.org/wiki/MPEG_transport_stream#Packet_identifier_(PID)
FOUNDATION_EXPORT NSUInteger const PID_OTHER_START_INDEX;
FOUNDATION_EXPORT NSUInteger const PID_OTHER_END_INDEX;
FOUNDATION_EXPORT NSUInteger const PID_NULL_PACKET;
FOUNDATION_EXPORT NSUInteger const PROGRAM_NUMBER_NETWORK_INFO;

// DVB EN 300 468 Service Information (SI)
FOUNDATION_EXPORT NSUInteger const TABLE_ID_DVB_SDT_ACTUAL_TS;
FOUNDATION_EXPORT NSUInteger const TABLE_ID_DVB_SDT_OTHER_TS;
FOUNDATION_EXPORT NSUInteger const PID_DVB_NIT_ST;
FOUNDATION_EXPORT NSUInteger const PID_DVB_SDT_BAT_ST;
FOUNDATION_EXPORT NSUInteger const PID_DVB_EIT_ST_CIT;
FOUNDATION_EXPORT NSUInteger const PID_DVB_RST_ST;
FOUNDATION_EXPORT NSUInteger const PID_DVB_TDT_TOT_ST;
FOUNDATION_EXPORT NSUInteger const PID_DVB_NETWORK_SYNCHRONIZATION;
FOUNDATION_EXPORT NSUInteger const PID_DVB_RNT;
FOUNDATION_EXPORT NSUInteger const PID_DVB_RESERVED_1;
FOUNDATION_EXPORT NSUInteger const PID_DVB_RESERVED_2;
FOUNDATION_EXPORT NSUInteger const PID_DVB_RESERVED_3;
FOUNDATION_EXPORT NSUInteger const PID_DVB_RESERVED_4;
FOUNDATION_EXPORT NSUInteger const PID_DVB_RESERVED_5;
FOUNDATION_EXPORT NSUInteger const PID_DVB_INBAND_SIGNALLING;
FOUNDATION_EXPORT NSUInteger const PID_DVB_MEASURMENT;
FOUNDATION_EXPORT NSUInteger const PID_DVB_DIT;
FOUNDATION_EXPORT NSUInteger const PID_DVB_SIT;

// ATSC A/65:2013 Program and System Information Protocol (PSIP)
FOUNDATION_EXPORT NSUInteger const TABLE_ID_ATSC_MGT;   // Master Guide Table
FOUNDATION_EXPORT NSUInteger const TABLE_ID_ATSC_TVCT;  // Terrestrial Virtual Channel Table
FOUNDATION_EXPORT NSUInteger const TABLE_ID_ATSC_CVCT;  // Cable Virtual Channel Table
FOUNDATION_EXPORT NSUInteger const TABLE_ID_ATSC_RRT;   // Rating Region Table
FOUNDATION_EXPORT NSUInteger const TABLE_ID_ATSC_EIT;   // Event Information Table
FOUNDATION_EXPORT NSUInteger const TABLE_ID_ATSC_ETT;   // Extended Text Table
FOUNDATION_EXPORT NSUInteger const TABLE_ID_ATSC_STT;   // System Time Table
FOUNDATION_EXPORT NSUInteger const PID_ATSC_PSIP;       // PSIP base PID

// ETSI TR 101 290 - DVB Measurement guidelines for DVB systems
// https://www.etsi.org/deliver/etsi_tr/101200_101299/101290/01.05.01_60/tr_101290v010501p.pdf
FOUNDATION_EXPORT uint64_t const TR101290_PAT_PMT_INTERVAL_MS;  // PAT/PMT must occur every 500ms
FOUNDATION_EXPORT uint64_t const TR101290_PID_INTERVAL_MS;      // Video/audio PID must occur every 5s

@interface TSPidUtil : NSObject
+(BOOL)isCustomPidInvalid:(uint16_t)pid;
+(BOOL)isReservedPid:(uint16_t)pid;
+(NSArray<NSNumber*>* _Nonnull)reservedPids;
+(BOOL)isDvbReservedPid:(uint16_t)pid;
+(BOOL)isAtscReservedPid:(uint16_t)pid;
@end
