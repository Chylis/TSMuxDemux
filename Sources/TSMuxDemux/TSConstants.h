//
//  TSConstants.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NSNumber *ProgramNumber;
typedef NSNumber *PmtPid; // NSNumber.unsignedShortValue (A PID is a 13-bit value in a uint16_t)

FOUNDATION_EXPORT uint32_t const TS_TIMESTAMP_TIMESCALE;

FOUNDATION_EXPORT uint8_t const TS_PACKET_SIZE;
FOUNDATION_EXPORT uint8_t const TS_PACKET_HEADER_SIZE;
FOUNDATION_EXPORT uint8_t const TS_PACKET_HEADER_SYNC_BYTE;
FOUNDATION_EXPORT uint8_t const TS_PACKET_MAX_PAYLOAD_SIZE;

FOUNDATION_EXPORT NSUInteger const TABLE_ID_PAT;
FOUNDATION_EXPORT NSUInteger const TABLE_ID_PMT;

// In transport streams, PSI is classified into six table structures/sections (PAT, PMT, NIT, CAT, TSDT, IPMP).
// While these structures may be thought of as simple tables, they shall be segmented into sections and inserted in transport stream packets, some with predetermined PIDs and others with user selectable PIDs:
FOUNDATION_EXPORT NSUInteger const PID_PAT;
FOUNDATION_EXPORT NSUInteger const PID_CAT;
FOUNDATION_EXPORT NSUInteger const PID_TSDT;
FOUNDATION_EXPORT NSUInteger const PID_IPMP;
FOUNDATION_EXPORT NSUInteger const PID_ASI;

// "Other" PIDs (range 16-8190) may be PMT, network PID, elementary PID, etc...
// https://en.wikipedia.org/wiki/MPEG_transport_stream#Packet_identifier_(PID)
FOUNDATION_EXPORT NSUInteger const PID_OTHER_START_INDEX; // Start-index for custom pids
FOUNDATION_EXPORT NSUInteger const PID_NIT_ST;
FOUNDATION_EXPORT NSUInteger const PID_SDT_BAT_ST;
FOUNDATION_EXPORT NSUInteger const PID_EIT_ST_CIT;
FOUNDATION_EXPORT NSUInteger const PID_RST_ST;
FOUNDATION_EXPORT NSUInteger const PID_TDT_TOT_ST;
FOUNDATION_EXPORT NSUInteger const PID_NETWORK_SYNCHRONIZATION;
FOUNDATION_EXPORT NSUInteger const PID_RNT;
FOUNDATION_EXPORT NSUInteger const PID_RESERVED_1;
FOUNDATION_EXPORT NSUInteger const PID_RESERVED_2;
FOUNDATION_EXPORT NSUInteger const PID_RESERVED_3;
FOUNDATION_EXPORT NSUInteger const PID_RESERVED_4;
FOUNDATION_EXPORT NSUInteger const PID_RESERVED_5;
FOUNDATION_EXPORT NSUInteger const PID_INBAND_SIGNALLING;
FOUNDATION_EXPORT NSUInteger const PID_MEASURMENT;
FOUNDATION_EXPORT NSUInteger const PID_DIT;
FOUNDATION_EXPORT NSUInteger const PID_SIT; // The last reserved/occupied pid in range "other"
FOUNDATION_EXPORT NSUInteger const PID_OTHER_END_INDEX; // End-index for custom pids

FOUNDATION_EXPORT NSUInteger const PID_NULL_PACKET;

FOUNDATION_EXPORT NSUInteger const PROGRAM_NUMBER_NETWORK_INFO;

@interface PidUtil : NSObject
+(BOOL)isCustomPidInvalid:(uint16_t)pid;
+(BOOL)isReservedPid:(uint16_t)pid;
+(NSArray<NSNumber*>* _Nonnull)reservedPids;
@end
