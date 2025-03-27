//
//  TSConstants.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NSNumber *ProgramNumber;
typedef NSNumber *Pid; // NSNumber.unsignedShortValue (A PID is a 13-bit value in a uint16_t)

FOUNDATION_EXPORT uint32_t const TS_TIMESTAMP_TIMESCALE;

FOUNDATION_EXPORT uint8_t const TS_PACKET_SIZE;
FOUNDATION_EXPORT uint8_t const TS_PACKET_HEADER_SIZE;
FOUNDATION_EXPORT uint8_t const TS_PACKET_HEADER_SYNC_BYTE;
FOUNDATION_EXPORT uint8_t const TS_PACKET_MAX_PAYLOAD_SIZE;

FOUNDATION_EXPORT NSUInteger const TABLE_ID_PAT;
FOUNDATION_EXPORT NSUInteger const TABLE_ID_PMT;
FOUNDATION_EXPORT NSUInteger const TABLE_ID_DVB_SDT_ACTUAL_TS;
FOUNDATION_EXPORT NSUInteger const TABLE_ID_DVB_SDT_OTHER_TS;

FOUNDATION_EXPORT NSUInteger const PID_PAT;
FOUNDATION_EXPORT NSUInteger const PID_CAT;
FOUNDATION_EXPORT NSUInteger const PID_TSDT;
FOUNDATION_EXPORT NSUInteger const PID_IPMP;
FOUNDATION_EXPORT NSUInteger const PID_ASI;
// "Other" PIDs (range 16-8190) may be PMT, network PID, elementary PID, etc...
// https://en.wikipedia.org/wiki/MPEG_transport_stream#Packet_identifier_(PID)
FOUNDATION_EXPORT NSUInteger const PID_OTHER_START_INDEX; // Start-index for custom pids
// DVB
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
FOUNDATION_EXPORT NSUInteger const PID_DVB_SIT; // The last reserved/occupied pid in range "other"

// TODO ATSC



FOUNDATION_EXPORT NSUInteger const PID_OTHER_END_INDEX; // End-index for custom pids

FOUNDATION_EXPORT NSUInteger const PID_NULL_PACKET;

FOUNDATION_EXPORT NSUInteger const PROGRAM_NUMBER_NETWORK_INFO;

@interface PidUtil : NSObject
+(BOOL)isCustomPidInvalid:(uint16_t)pid;
+(BOOL)isReservedPid:(uint16_t)pid;
+(NSArray<NSNumber*>* _Nonnull)reservedPids;
@end
