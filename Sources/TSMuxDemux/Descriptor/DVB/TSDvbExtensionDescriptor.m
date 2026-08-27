//
//  TSDvbExtensionDescriptor.m
//  TSMuxDemux
//

#import "TSDvbExtensionDescriptor.h"
#import "../../TSLog.h"

@implementation TSDvbExtensionDescriptor

-(instancetype _Nullable)initWithTag:(uint8_t)tag
                             payload:(NSData * _Nullable)payload
                              length:(NSUInteger)length
{
    self = [super initWithTag:tag length:length];
    if (self) {
        if (length < 1 || payload.length < length) {
            TSLogWarn(@"DVB extension descriptor truncated: need %lu bytes, have %lu",
                      (unsigned long)MAX(length, 1), (unsigned long)payload.length);
            return nil;
        }

        const uint8_t *bytes = payload.bytes;
        _descriptorTagExtension = bytes[0];

        if (length > 1) {
            _extensionData = [[payload subdataWithRange:NSMakeRange(1, length - 1)] copy];
        }
    }
    return self;
}

-(BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    if ([self class] != [object class] || ![super isEqual:object]) {
        return NO;
    }
    TSDvbExtensionDescriptor *other = (TSDvbExtensionDescriptor *)object;
    return self.descriptorTagExtension == other.descriptorTagExtension
        && (self.extensionData == other.extensionData
            || [self.extensionData isEqualToData:other.extensionData]);
}

-(NSUInteger)hash
{
    return [super hash] ^ self.descriptorTagExtension ^ self.extensionData.hash;
}

-(NSString *)tagDescription
{
    if (self.descriptorTagExtension == TSExtensionDescriptorTagAc4) {
        return @"Extension: AC-4";
    }
    return [NSString stringWithFormat:@"Extension: 0x%02x", self.descriptorTagExtension];
}

@end
