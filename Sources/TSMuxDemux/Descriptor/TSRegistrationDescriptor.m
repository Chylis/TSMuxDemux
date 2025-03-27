//
//  TSRegistrationDescriptor.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSRegistrationDescriptor.h"
#import "../TSFourCharCodeUtil.h"

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
            NSLog(@"Received registration description with no payload");
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
    return [NSString stringWithFormat:@"Registration: %@",
            [TSFourCharCodeUtil toString:_formatIdentifier]];
}


@end
