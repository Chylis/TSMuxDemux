//
//  TSScte35CueIdentifierDescriptor.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSScte35CueIdentifierDescriptor.h"

@implementation TSScte35CueIdentifierDescriptor

-(instancetype _Nonnull)initWithTag:(uint8_t)tag
                            payload:(NSData* _Nonnull)payload
                             length:(NSUInteger)length
{
    self = [super initWithTag:tag length:length];
    if (self) {
        if (payload.length && length > 0) {
            NSUInteger offset = 0;
            NSUInteger remainingLength = length;
            
            uint8_t cueStreamType = 0x0;
            [payload getBytes:&cueStreamType range:NSMakeRange(offset, 1)];
            offset++;
            remainingLength--;
            _cueStreamType = cueStreamType;
        } else {
            NSLog(@"Received cue identifier description with no payload");
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
    TSScte35CueIdentifierDescriptor *other = (TSScte35CueIdentifierDescriptor*)object;
    return self.cueStreamType == other.cueStreamType;
}

-(NSUInteger)hash
{
    return [super hash] ^ self.cueStreamType;
}

-(NSString*)description
{
    return [self tagDescription];
}
-(NSString*)tagDescription
{
    return [NSString stringWithFormat:@"SCTE-35 CueId: %u", _cueStreamType];
}



@end
