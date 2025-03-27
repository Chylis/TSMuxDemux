//
//  TSCueIdentifierDescriptor.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSCueIdentifierDescriptor.h"

@implementation TSCueIdentifierDescriptor

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

-(NSString*)description
{
    return [self tagDescription];
}
-(NSString*)tagDescription
{
    return [NSString stringWithFormat:@"SCTE-35 CueId: %u", _cueStreamType];
}



@end
