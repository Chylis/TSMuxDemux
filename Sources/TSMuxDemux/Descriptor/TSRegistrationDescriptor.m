//
//  TSRegistrationDescriptor.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSRegistrationDescriptor.h"
#import "../TSFourCharCodeUtil.h"
#import "../TSLog.h"

@implementation TSRegistrationDescriptor

-(instancetype _Nonnull)initWithTag:(uint8_t)tag
                            payload:(NSData* _Nonnull)payload
                             length:(NSUInteger)length
{
    self = [super initWithTag:tag length:length];
    if (self) {
        if (payload.length && length > 0) {
            NSUInteger offset = 0;
            NSUInteger remainingLength = length;
            
            uint32_t formatIdentifier = 0x0;
            [payload getBytes:&formatIdentifier range:NSMakeRange(offset, 4)];
            offset+=4;
            remainingLength-=4;
            _formatIdentifier = CFSwapInt32BigToHost(formatIdentifier);

            if (remainingLength > 0) {
                _additionalIdentificationInfo = [payload subdataWithRange:NSMakeRange(offset, remainingLength)];
                offset+=remainingLength;
                remainingLength=0;
            }
        } else {
            TSLogWarn(@"Received registration descriptor with no payload");
        }
    }
    
    return self;
}

-(BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    if ([self class] != [object class]) {
        return NO;
    }
    if (![super isEqual:object]) {
        return NO;
    }
    TSRegistrationDescriptor *other = (TSRegistrationDescriptor*)object;
    if (self.formatIdentifier != other.formatIdentifier) {
        return NO;
    }
    if (self.additionalIdentificationInfo != other.additionalIdentificationInfo &&
        ![self.additionalIdentificationInfo isEqualToData:other.additionalIdentificationInfo]) {
        return NO;
    }
    return YES;
}

-(NSUInteger)hash
{
    return [super hash] ^ self.formatIdentifier ^ self.additionalIdentificationInfo.hash;
}

-(NSString*)description
{
    return [self tagDescription];
}
-(NSString*)tagDescription
{
    return [NSString stringWithFormat:@"Registration: %@",
            [TSFourCharCodeUtil toString:_formatIdentifier]];
}


@end
