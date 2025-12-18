//
//  TSElementaryStream.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSElementaryStream.h"
#import "TSStreamType.h"
#import "Descriptor/TSDescriptor.h"
#import "Descriptor/TSRegistrationDescriptor.h"
#import "Descriptor/TSISO639LanguageDescriptor.h"
#import "Descriptor/TSHEVCVideoDescriptor.h"
#import "Descriptor/SCTE35/TSScte35CueIdentifierDescriptor.h"

#pragma mark - TSElementaryStream

@implementation TSElementaryStream

-(instancetype)initWithPid:(uint16_t)pid
                streamType:(uint8_t)streamType
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
        if (![d1 isEqual:d2]) {
            return NO;
        }
    }

    return YES;
}

-(NSUInteger)hash
{
    NSUInteger descriptorsHash = 0;
    for (TSDescriptor *d in self.descriptors) {
        descriptorsHash ^= d.hash;
    }
    return self.pid ^ (self.streamType << 16) ^ descriptorsHash;
}

-(TSResolvedStreamType)resolvedStreamType
{
    return [TSStreamType resolveStreamType:self.streamType descriptors:self.descriptors];
}

-(BOOL)isAudio
{
    return [TSStreamType isAudio:[self resolvedStreamType]];
}

-(BOOL)isVideo
{
    return [TSStreamType isVideo:[self resolvedStreamType]];
}

-(NSString*)description
{
    NSMutableString *desc = [NSMutableString stringWithFormat:@"Pid: %hu, %@",
                             self.pid,
                             [TSStreamType descriptionForResolvedStreamType:[self resolvedStreamType]]];

    if (self.descriptors.count > 0) {
        [desc appendString:@", Tags: "];
        BOOL first = YES;
        for (TSDescriptor *d in self.descriptors) {
            if (!first) {
                [desc appendString:@", "];
            }
            [desc appendString:[d tagDescription]];
            first = NO;
        }
    }

    return desc;
}

#pragma mark - Util - Implemented/Parsed Descriptor Accessors

-(NSArray<TSRegistrationDescriptor*>*)registrationDescriptors
{
    NSMutableArray *result = [NSMutableArray array];
    for (TSDescriptor *d in self.descriptors) {
        if ([d isKindOfClass:[TSRegistrationDescriptor class]]) {
            [result addObject:d];
        }
    }
    return result;
}

-(NSArray<TSISO639LanguageDescriptor*>*)languageDescriptors
{
    NSMutableArray *result = [NSMutableArray array];
    for (TSDescriptor *d in self.descriptors) {
        if ([d isKindOfClass:[TSISO639LanguageDescriptor class]]) {
            [result addObject:d];
        }
    }
    return result;
}

-(NSArray<TSHEVCVideoDescriptor*>*)hevcVideoDescriptors
{
    NSMutableArray *result = [NSMutableArray array];
    for (TSDescriptor *d in self.descriptors) {
        if ([d isKindOfClass:[TSHEVCVideoDescriptor class]]) {
            [result addObject:d];
        }
    }
    return result;
}

-(NSArray<TSScte35CueIdentifierDescriptor*>*)scte35CueIdentifierDescriptors
{
    NSMutableArray *result = [NSMutableArray array];
    for (TSDescriptor *d in self.descriptors) {
        if ([d isKindOfClass:[TSScte35CueIdentifierDescriptor class]]) {
            [result addObject:d];
        }
    }
    return result;
}

@end
