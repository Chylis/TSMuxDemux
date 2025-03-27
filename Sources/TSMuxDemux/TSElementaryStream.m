//
//  TSElementaryStream.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSElementaryStream.h"
#import "Descriptor/TSDescriptor.h"

#pragma mark - TSElementaryStream

@implementation TSElementaryStream

-(instancetype)initWithPid:(uint16_t)pid
                streamType:(TSStreamType)streamType
               descriptors:(NSArray<TSDescriptor *> *_Nullable)descriptors
{
    self = [super init];
    if (self) {
        _pid = pid;
        _streamType = streamType;
        _descriptors = descriptors;
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
    if (self.pid != es.pid) {
        return NO;
    }
    if (self.streamType != es.streamType) {
        return NO;
    }
    if (self.descriptors.count != es.descriptors.count) {
        return NO;
    }
    for (NSUInteger i=0; i < self.descriptors.count; ++i) {
        TSDescriptor *d1 = self.descriptors[i];
        TSDescriptor *d2 = es.descriptors[i];
        if (d1.descriptorTag != d2.descriptorTag) {
            return NO;
        }
    }
    
    return YES;
}

-(NSUInteger)hash
{
    return [@(self.pid) hash];
}

-(BOOL)isAudioStreamType
{
    return [TSAccessUnit isAudioStreamType:self.streamType descriptors:self.descriptors];
}
-(BOOL)isVideoStreamType
{
    return [TSAccessUnit isVideoStreamType:self.streamType];
}

-(NSString*)description
{
    NSMutableString *desc = [NSMutableString stringWithFormat:@"Pid: %hu, %@",
                             self.pid,
                             [TSAccessUnit streamTypeDescription:self.streamType]];
    
    if (self.descriptors.count > 0) {
        [desc appendString:@", Tags: "];
        BOOL first = YES;
        for (TSDescriptor *d in self.descriptors) {
            if (!first) {
                [desc appendString:@", "];
            }
            [desc appendString:[NSString stringWithFormat:@"%@", [d tagDescription]]];
            first = NO;
        }
    }
    
    return desc;
}


@end
