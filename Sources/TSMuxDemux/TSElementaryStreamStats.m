//
//  TSElementaryStreamStats.m
//  
//
//  Created by Magnus Eriksson on 2023-02-24.
//

#import "TSElementaryStreamStats.h"

#pragma mark - TSContinuityCountError

@implementation TSContinuityCountError
-(instancetype _Nonnull)initWithReceived:(uint8_t)receivedCC
                                expected:(uint8_t)expectedCC
                                 message:(NSString*)message
{
    self = [super init];
    if (self) {
        _receivedCC = receivedCC;
        _expectedCC = expectedCC;
        _message = message;
        _timestamp = [NSDate date];
    }
    return self;
}
@end

#pragma mark - TSElementaryStreamStats
@implementation TSElementaryStreamStats

-(instancetype _Nonnull)init
{
    self = [super init];
    if (self) {
        _discardedPacketCount = 0;
        _ccErrors = [[NSMutableArray alloc] initWithCapacity:3000];
    }
    return self;
}
@end


