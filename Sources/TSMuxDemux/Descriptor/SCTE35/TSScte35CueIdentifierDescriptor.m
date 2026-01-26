//
//  TSScte35CueIdentifierDescriptor.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSScte35CueIdentifierDescriptor.h"
#import "../../TSBitReader.h"
#import "../../TSLog.h"

@implementation TSScte35CueIdentifierDescriptor

-(instancetype _Nullable)initWithTag:(uint8_t)tag
                             payload:(NSData *)payload
                              length:(NSUInteger)length
{
    self = [super initWithTag:tag length:length];
    if (self) {
        if (payload.length && length > 0) {
            TSBitReader reader = TSBitReaderMake(payload);
            _cueStreamType = TSBitReaderReadUInt8(&reader);
            if (reader.error) {
                TSLogWarn(@"Received cue identifier descriptor with insufficient data");
                return nil;
            }
        } else {
            TSLogWarn(@"Received cue identifier descriptor with no payload");
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
