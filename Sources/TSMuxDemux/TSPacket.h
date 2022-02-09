//
//  TSPacket.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-07.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TSElementaryStream;

/// See "Rec. ITU-T H.222.0 (03/2017)"
/// section "2.4.3.2 Transport stream packet layer" page 24

#pragma mark - TSPacketHeader

typedef NS_ENUM(uint8_t, TSAdaptationMode) {
    TSAdaptationModeReserved = 0x00,
    TSAdaptationModePayloadOnly = 0x01,
    TSAdaptationModeAdaptationOnly = 0x02,
    TSAdaptationModeAdaptationAndPayload = 0x03,
};

@interface TSPacketHeader : NSObject

@property(nonatomic, readonly) BOOL transportErrorIndicator;
@property(nonatomic, readonly) BOOL payloadUnitStartIndicator;
@property(nonatomic, readonly) BOOL transportPriority;
@property(nonatomic, readonly) BOOL isScrambled;
@property(nonatomic, readonly) TSAdaptationMode adaptationMode;

/// A 13-bit value indicating the type of the data stored in the packet payload.
@property(nonatomic, readonly) uint16_t pid;

/// A 4-bit (per pid) packet counter.
@property(nonatomic, readonly) uint8_t continuityCounter;

-(instancetype _Nonnull)initWithTei:(BOOL)tei
                      pusi:(BOOL)pusi
         transportPriority:(BOOL)transportPriority
                       pid:(uint16_t)pid
               isScrambled:(BOOL)isScrambled
            adaptationMode:(TSAdaptationMode)adaptationMode
         continuityCounter:(uint8_t)continuityCounter;

// Returns the byte representation of the TSPacketHeader.
-(NSData* _Nonnull)getBytes;

@end

#pragma mark - TSPacketAdaptationField

@interface TSAdaptationField : NSObject

/// Specifies the number of bytes in the adaptation_field immediately following the adaptation_field_length
@property(nonatomic, readonly) uint8_t adaptationFieldLength;
@property(nonatomic, readonly) NSUInteger numberOfStuffedBytes;


@property(nonatomic, readonly) uint64_t pcrBase;
@property(nonatomic, readonly) uint16_t pcrExt;

+(instancetype _Nonnull)initWithPcrBase:(uint64_t)pcrBase
                                 pcrExt:(uint16_t)pcrExt
                            remainingPayloadSize:(NSUInteger)remainingPayloadSize;


-(instancetype _Nonnull)initWithAdaptationFieldLength:(uint8_t)adaptationFieldLength
                                              pcrBase:(uint64_t)pcrBase
                                               pcrExt:(uint16_t)pcrExt
                        numberOfStuffedBytes:(NSUInteger)numberOfStuffedBytes;

// Returns the byte representation of the TSAdaptationField.
-(NSData* _Nonnull)getBytes;

@end


#pragma mark - TSPacket

typedef void (^OnTsPacketDataCallback)(NSData * _Nonnull);

@interface TSPacket: NSObject

@property(nonatomic, nonnull, readonly) TSPacketHeader *header;
@property(nonatomic, nullable, readonly) TSAdaptationField *adaptationField;
@property(nonatomic, nullable, readonly) NSData *payload;

/// Creates TSPackets from the received raw ts packet data
+(NSArray<TSPacket*>* _Nonnull)packetsFromChunkedTsData:(NSData* _Nonnull)chunk;

/// Packetizes the received payload in N 188-byte long raw ts-data chunks and passes each chunk individually to the callback.
+(void)packetizePayload:(NSData* _Nonnull)payload
                  track:(TSElementaryStream* _Nonnull)track
              forcePusi:(BOOL)forcePusi
                pcrBase:(uint64_t)pcrBase
                 pcrExt:(uint16_t)pcrExt
         onTsPacketData:(OnTsPacketDataCallback _Nonnull)onTsPacketDataCb;
@end
