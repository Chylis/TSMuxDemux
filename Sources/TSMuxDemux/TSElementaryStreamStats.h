//
//  TSElementaryStreamStats.h
//  
//
//  Created by Magnus Eriksson on 2023-02-24.
//

#import <Foundation/Foundation.h>

@interface TSContinuityCountError: NSObject
@property(nonatomic, readonly) uint8_t receivedCC;
@property(nonatomic, readonly) uint8_t expectedCC;
@property(nonatomic, readonly, nonnull) NSString *message;
@property(nonatomic, readonly, nonnull) NSDate *timestamp;

-(instancetype _Nonnull)initWithReceived:(uint8_t)receivedCC
                                expected:(uint8_t)expectedCC
                                 message:(NSString* _Nonnull)message;
@end

@interface TSElementaryStreamStats: NSObject
@property(nonatomic) NSUInteger discardedPacketCount;
@property(nonatomic, nonnull) NSMutableArray<TSContinuityCountError*> *ccErrors;
@end
