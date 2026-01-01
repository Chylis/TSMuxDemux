//
//  TSConstants.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSConstants.h"

uint32_t const TS_TIMESTAMP_TIMESCALE = 90000;

uint8_t const TS_PACKET_SIZE_188 = 188;
uint8_t const TS_PACKET_SIZE_204 = 204;
uint8_t const TS_RS_PARITY_SIZE = 16;
uint8_t const TS_PACKET_HEADER_SIZE = 4;
uint8_t const TS_PACKET_HEADER_SYNC_BYTE = 0x47;
uint8_t const TS_PACKET_MAX_PAYLOAD_SIZE = TS_PACKET_SIZE_188 - TS_PACKET_HEADER_SIZE;

// ISO/IEC 13818-1 MPEG-TS
NSUInteger const TABLE_ID_PAT = 0x00;
NSUInteger const TABLE_ID_PMT = 0x02;
NSUInteger const PID_PAT = 0x00;  // Program association table
NSUInteger const PID_CAT = 0x01;  // Conditional access table
NSUInteger const PID_TSDT = 0x02; // Transport stream description table
NSUInteger const PID_IPMP = 0x03; // IPMP control information table
NSUInteger const PID_ASI = 0x04;  // Adaptive streaming information (not a table), defined in 5.10.3.3.5 of ISO/IEC 23009-1.
NSUInteger const PID_OTHER_START_INDEX = 0x10;
NSUInteger const PID_OTHER_END_INDEX = 0x1FFE;
NSUInteger const PID_NULL_PACKET = 0x1FFF;
NSUInteger const PROGRAM_NUMBER_NETWORK_INFO = 0x00;

// DVB EN 300 468 Service Information (SI)
NSUInteger const TABLE_ID_DVB_SDT_ACTUAL_TS = 0x42;
NSUInteger const TABLE_ID_DVB_SDT_OTHER_TS = 0x46;
NSUInteger const PID_DVB_NIT_ST = 0x10;
NSUInteger const PID_DVB_SDT_BAT_ST = 0x11;
NSUInteger const PID_DVB_EIT_ST_CIT = 0x12;
NSUInteger const PID_DVB_RST_ST = 0x13;
NSUInteger const PID_DVB_TDT_TOT_ST = 0x14;
NSUInteger const PID_DVB_NETWORK_SYNCHRONIZATION = 0x15;
NSUInteger const PID_DVB_RNT = 0x16;
NSUInteger const PID_DVB_RESERVED_1 = 0x17;
NSUInteger const PID_DVB_RESERVED_2 = 0x18;
NSUInteger const PID_DVB_RESERVED_3 = 0x19;
NSUInteger const PID_DVB_RESERVED_4 = 0x1A;
NSUInteger const PID_DVB_RESERVED_5 = 0x1B;
NSUInteger const PID_DVB_INBAND_SIGNALLING = 0x1C;
NSUInteger const PID_DVB_MEASURMENT = 0x1D;
NSUInteger const PID_DVB_DIT = 0x1E;
NSUInteger const PID_DVB_SIT = 0x1F;

// ATSC A/65:2013 Program and System Information Protocol (PSIP)
NSUInteger const TABLE_ID_ATSC_MGT  = 0xC7;
NSUInteger const TABLE_ID_ATSC_TVCT = 0xC8;
NSUInteger const TABLE_ID_ATSC_CVCT = 0xC9;
NSUInteger const TABLE_ID_ATSC_RRT  = 0xCA;
NSUInteger const TABLE_ID_ATSC_EIT  = 0xCB;
NSUInteger const TABLE_ID_ATSC_ETT  = 0xCC;
NSUInteger const TABLE_ID_ATSC_STT  = 0xCD;
NSUInteger const PID_ATSC_PSIP = 0x1FFB;

// ETSI TR 101 290 - DVB Measurement guidelines for DVB systems
uint64_t const TR101290_PAT_PMT_INTERVAL_MS = 500;
uint64_t const TR101290_PID_INTERVAL_MS = 5000;

@implementation TSPidUtil

+(BOOL)isCustomPidInvalid:(uint16_t)pid
{
    return [TSPidUtil isReservedPid:pid] || pid < PID_OTHER_START_INDEX || pid > PID_OTHER_END_INDEX;
}

+(BOOL)isReservedPid:(uint16_t)pid
{
    return [[TSPidUtil reservedPids] containsObject:@(pid)];
}

+(NSArray<NSNumber*>*)reservedPids
{
    static NSArray<NSNumber*> *cachedPids = nil;
    if (cachedPids) return cachedPids;
    cachedPids = @[
        @(PID_PAT),
        @(PID_CAT),
        @(PID_TSDT),
        @(PID_IPMP),
        @(PID_ASI),
        // 0x05-0x0F reserved for future use (ISO/IEC 13818-1)
        @(0x05), @(0x06), @(0x07), @(0x08), @(0x09), @(0x0A), @(0x0B),
        @(0x0C), @(0x0D), @(0x0E), @(0x0F),

        // DVB
        @(PID_DVB_NIT_ST),
        @(PID_DVB_SDT_BAT_ST),
        @(PID_DVB_EIT_ST_CIT),
        @(PID_DVB_RST_ST),
        @(PID_DVB_TDT_TOT_ST),
        @(PID_DVB_NETWORK_SYNCHRONIZATION),
        @(PID_DVB_RNT),
        @(PID_DVB_RESERVED_1),
        @(PID_DVB_RESERVED_2),
        @(PID_DVB_RESERVED_3),
        @(PID_DVB_RESERVED_4),
        @(PID_DVB_RESERVED_5),
        @(PID_DVB_INBAND_SIGNALLING),
        @(PID_DVB_MEASURMENT),
        @(PID_DVB_DIT),
        @(PID_DVB_SIT),

        // ATSC
        @(PID_ATSC_PSIP),

        @(PID_NULL_PACKET),
    ];
    return cachedPids;
}

+(BOOL)isDvbReservedPid:(uint16_t)pid
{
    return pid >= PID_DVB_NIT_ST && pid <= PID_DVB_SIT;
}

+(BOOL)isAtscReservedPid:(uint16_t)pid
{
    return pid == PID_ATSC_PSIP;
}

@end
