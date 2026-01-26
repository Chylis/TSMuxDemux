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
#import "../TSBitReader.h"

@implementation TSRegistrationDescriptor

-(instancetype _Nullable)initWithTag:(uint8_t)tag
                             payload:(NSData *)payload
                              length:(NSUInteger)length
{
    self = [super initWithTag:tag length:length];
    if (self) {
        if (payload.length && length > 0) {
            TSBitReader reader = TSBitReaderMake(payload);

            _formatIdentifier = TSBitReaderReadUInt32BE(&reader);
            if (reader.error) {
                TSLogWarn(@"Registration descriptor truncated: need 4 bytes, have %lu",
                          (unsigned long)payload.length);
                return nil;
            }

            NSUInteger remaining = TSBitReaderRemainingBytes(&reader);
            if (remaining > 0) {
                _additionalIdentificationInfo = [TSBitReaderReadData(&reader, remaining) copy];
            }
        } else {
            TSLogWarn(@"Received registration descriptor with no payload");
            return nil;
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
