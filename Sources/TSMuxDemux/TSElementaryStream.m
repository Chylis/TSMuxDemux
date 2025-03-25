//
//  TSElementaryStream.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSElementaryStream.h"

#pragma mark - TSElementaryStream

@implementation TSElementaryStream

-(instancetype)initWithPid:(uint16_t)pid
                streamType:(TSStreamType)streamType
             descriptorTag:(uint8_t)descriptorTag
{
    self = [super init];
    if (self) {
        _pid = pid;
        _streamType = streamType;
        _descriptorTag = descriptorTag;
        _continuityCounter = 0;
    }
    return self;
}

-(void)setContinuityCounter:(uint8_t)continuityCounter
{
    static const NSUInteger MAX_VALUE = 16;
    _continuityCounter = continuityCounter % MAX_VALUE;
    //NSLog(@"CC for pid %hu is %hhu", self.pid, _continuityCounter);
}

-(BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[TSElementaryStream class]]) {
        return NO;
    }
    return [self isEqualToElementaryStream:(TSElementaryStream*)object];
}

-(BOOL)isEqualToElementaryStream:(TSElementaryStream*)es
{
    return self.pid == es.pid && self.streamType == es.streamType && self.descriptorTag == es.descriptorTag;
}

-(NSUInteger)hash
{
    return [@(self.pid) hash];
}

-(BOOL)isAudioStreamType
{
    return [TSAccessUnit isAudioStreamType:self.streamType descriptorTag:self.descriptorTag];
}
-(BOOL)isVideoStreamType
{
    return [TSAccessUnit isVideoStreamType:self.streamType];
}


@end
