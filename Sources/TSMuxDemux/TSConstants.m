//
//  TSConstants.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSConstants.h"

uint32_t const TS_TIMESTAMP_TIMESCALE = 90000;

uint8_t const TS_PACKET_SIZE = 188;
uint8_t const TS_PACKET_HEADER_SIZE = 4;
uint8_t const TS_PACKET_HEADER_SYNC_BYTE = 0x47;
uint8_t const TS_PACKET_MAX_PAYLOAD_SIZE = TS_PACKET_SIZE - TS_PACKET_HEADER_SIZE;

NSUInteger const TABLE_ID_PAT = 0x00;
NSUInteger const TABLE_ID_PMT = 0x02;

NSUInteger const PID_PAT = 0x00; // Program association table
NSUInteger const PID_CAT = 0x01; // Conditional access table
NSUInteger const PID_TSDT = 0x02; // Transport stream description table
NSUInteger const PID_IPMP = 0x03; // IPMP control information table
NSUInteger const PID_ASI = 0x04; // Adaptive streaming information

NSUInteger const PID_OTHER_START_INDEX = 0x10;
NSUInteger const PID_NIT_ST = 0x10;
NSUInteger const PID_SDT_BAT_ST = 0x11;
NSUInteger const PID_EIT_ST_CIT = 0x12;
NSUInteger const PID_RST_ST = 0x13;
NSUInteger const PID_TDT_TOT_ST = 0x14;
NSUInteger const PID_NETWORK_SYNCHRONIZATION = 0x15;
NSUInteger const PID_RNT = 0x16;
NSUInteger const PID_RESERVED_1 = 0x17;
NSUInteger const PID_RESERVED_2 = 0x18;
NSUInteger const PID_RESERVED_3 = 0x19;
NSUInteger const PID_RESERVED_4 = 0x1A;
NSUInteger const PID_RESERVED_5 = 0x1B;
NSUInteger const PID_INBAND_SIGNALLING = 0x1C;
NSUInteger const PID_MEASURMENT = 0x1D;
NSUInteger const PID_DIT = 0x1E;
NSUInteger const PID_SIT = 0x1F;
NSUInteger const PID_OTHER_END_INDEX = 0x1FFE;

NSUInteger const PID_NULL_PACKET = 0x1FFF;

NSUInteger const PROGRAM_NUMBER_NETWORK_INFO = 0x00;


@implementation PidUtil

+(BOOL)isCustomPidInvalid:(uint16_t)pid
{
    return [[PidUtil reservedPids] containsObject:@(pid)] || pid < PID_OTHER_START_INDEX || pid > PID_OTHER_END_INDEX;
}

+(NSArray<NSNumber*>*)reservedPids
{
    return @[
        @(PID_PAT),
        @(PID_CAT),
        @(PID_TSDT),
        @(PID_IPMP),
        @(PID_NIT_ST),
        @(PID_SDT_BAT_ST),
        @(PID_EIT_ST_CIT),
        @(PID_RST_ST),
        @(PID_TDT_TOT_ST),
        @(PID_NETWORK_SYNCHRONIZATION),
        @(PID_RNT),
        @(PID_RESERVED_1),
        @(PID_RESERVED_2),
        @(PID_RESERVED_3),
        @(PID_RESERVED_4),
        @(PID_RESERVED_5),
        @(PID_INBAND_SIGNALLING),
        @(PID_MEASURMENT),
        @(PID_DIT),
        @(PID_SIT),
    ];
}


@end
