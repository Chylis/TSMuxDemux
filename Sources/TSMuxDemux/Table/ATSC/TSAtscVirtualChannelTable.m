//
//  TSAtscVirtualChannelTable.m
//  TSMuxDemux
//
//  ATSC A/65 Virtual Channel Table (VCT) - Full implementation
//

#import "TSAtscVirtualChannelTable.h"
#import "../TSProgramSpecificInformationTable.h"
#import "../../TSConstants.h"
#import "../../Descriptor/TSDescriptor.h"
#import "../../Descriptor/ATSC/TSAtscServiceLocationDescriptor.h"
#import "../../TSLog.h"

#pragma mark - TSAtscVirtualChannel

@interface TSAtscVirtualChannel()
@property(nonatomic, readwrite, nonnull) NSString *shortName;
@property(nonatomic, readwrite) uint16_t majorChannelNumber;
@property(nonatomic, readwrite) uint16_t minorChannelNumber;
@property(nonatomic, readwrite) uint16_t programNumber;
@property(nonatomic, readwrite) TSAtscServiceType serviceType;
@property(nonatomic, readwrite) uint16_t sourceId;
@property(nonatomic, readwrite) BOOL accessControlled;
@property(nonatomic, readwrite) BOOL hidden;
@property(nonatomic, readwrite) BOOL hideGuide;
@property(nonatomic, readwrite, nullable) TSAtscServiceLocationDescriptor *serviceLocation;
@end

@implementation TSAtscVirtualChannel

-(NSString*)channelNumberString
{
    return [NSString stringWithFormat:@"%u.%u", self.majorChannelNumber, self.minorChannelNumber];
}

-(BOOL)isEqual:(id)object
{
    if (self == object) return YES;
    if (![object isKindOfClass:[TSAtscVirtualChannel class]]) return NO;
    TSAtscVirtualChannel *other = (TSAtscVirtualChannel *)object;
    return self.majorChannelNumber == other.majorChannelNumber
        && self.minorChannelNumber == other.minorChannelNumber
        && self.programNumber == other.programNumber
        && self.sourceId == other.sourceId
        && self.serviceType == other.serviceType
        && self.accessControlled == other.accessControlled
        && self.hidden == other.hidden
        && self.hideGuide == other.hideGuide
        && [self.shortName isEqualToString:other.shortName]
        && (self.serviceLocation == other.serviceLocation ||
            [self.serviceLocation isEqual:other.serviceLocation]);
}

-(NSUInteger)hash
{
    return self.programNumber ^ (self.majorChannelNumber << 16) ^ (self.minorChannelNumber << 8);
}

-(NSString*)description
{
    return [NSString stringWithFormat:@"%@ \"%@\" (prog:%u, src:%u, svc:%u)%@%@%@%@",
            [self channelNumberString],
            self.shortName,
            self.programNumber,
            self.sourceId,
            self.serviceType,
            self.hidden ? @" [hidden]" : @"",
            self.hideGuide ? @" [hideGuide]" : @"",
            self.accessControlled ? @" [CA]" : @"",
            self.serviceLocation ? @" [SLD]" : @""];
}

@end

#pragma mark - TSAtscVirtualChannelTable

@implementation TSAtscVirtualChannelTable

-(instancetype _Nullable)initWithPSI:(TSProgramSpecificInformationTable* _Nonnull)psi
{
    NSData *data = psi.sectionDataExcludingCrc;
    if (!data || data.length < 2) {
        TSLogWarn(@"VCT received PSI with insufficient data");
        return nil;
    }

    self = [super init];
    if (self) {
        _psi = psi;
        _tableId = psi.tableId;
        _isTerrestrial = (psi.tableId == TABLE_ID_ATSC_TVCT);
        _transportStreamId = [psi byte4And5];

        const uint8_t *bytes = data.bytes;
        NSUInteger length = data.length;

        // sectionDataExcludingCrc layout:
        // Bytes 0-1: transport_stream_id (accessed via psi.byte4And5)
        // Byte 2: reserved (2) + version_number (5) + current_next_indicator (1)
        // Byte 3: section_number
        // Byte 4: last_section_number
        // Byte 5: protocol_version (VCT-specific)
        // Byte 6: num_channels_in_section
        // Bytes 7+: channel loop

        // protocol_version (8 bits) at offset 5
        if (length < 7) {
            _channels = @[];
            return self;
        }
        // uint8_t protocolVersion = bytes[5];

        // num_channels_in_section (8 bits) at offset 6
        uint8_t numChannels = bytes[6];
        NSUInteger offset = 7;

        NSMutableArray<TSAtscVirtualChannel*> *channels = [NSMutableArray arrayWithCapacity:numChannels];

        for (uint8_t i = 0; i < numChannels; i++) {
            // Each channel entry is at least 32 bytes (fixed part)
            if (offset + 32 > length) {
                TSLogWarn(@"VCT: insufficient data for channel %u at offset %lu", i, (unsigned long)offset);
                break;
            }

            TSAtscVirtualChannel *channel = [TSAtscVirtualChannel new];

            // short_name: 7 x 16-bit UTF-16BE characters (14 bytes)
            // If the channel name is shorter the remaining positions are padded with null characters.
            NSData *nameData = [NSData dataWithBytes:&bytes[offset] length:14];
            NSString *name = [[NSString alloc] initWithData:nameData encoding:NSUTF16BigEndianStringEncoding];
            // Trim to remove padded null chars, e.g. "XYZ\0\0\0\0" --> "XYZ".
            channel.shortName = [name stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\0"]] ?: @"";
            offset += 14;

            // 4 bytes containing major/minor channel numbers and modulation
            // Bits: rrrr_mmmm_mmmm_mm nn_nnnn_nnnn_MMMM_MMMM
            // r = reserved (4 bits)
            // m = major_channel_number (10 bits)
            // n = minor_channel_number (10 bits)
            // M = modulation_mode (8 bits)
            uint32_t channelBits = ((uint32_t)bytes[offset] << 24) |
                                   ((uint32_t)bytes[offset + 1] << 16) |
                                   ((uint32_t)bytes[offset + 2] << 8) |
                                   (uint32_t)bytes[offset + 3];
            channel.majorChannelNumber = (channelBits >> 18) & 0x3FF;
            channel.minorChannelNumber = (channelBits >> 8) & 0x3FF;
            // uint8_t modulationMode = channelBits & 0xFF;
            offset += 4;

            // carrier_frequency (32 bits) - deprecated, set to 0
            offset += 4;

            // channel_TSID (16 bits)
            offset += 2;

            // program_number (16 bits)
            channel.programNumber = ((uint16_t)bytes[offset] << 8) | bytes[offset + 1];
            offset += 2;

            // Flags byte 1: ETM_location (2), access_controlled (1), hidden (1),
            //               path_select (1), out_of_band (1), hide_guide (1), reserved (1)
            uint8_t flags1 = bytes[offset];
            channel.accessControlled = (flags1 & 0x20) != 0;
            channel.hidden = (flags1 & 0x10) != 0;
            channel.hideGuide = (flags1 & 0x02) != 0;
            offset += 1;

            // Flags byte 2: reserved (2), service_type (6)
            uint8_t flags2 = bytes[offset];
            channel.serviceType = flags2 & 0x3F;
            offset += 1;

            // source_id (16 bits)
            channel.sourceId = ((uint16_t)bytes[offset] << 8) | bytes[offset + 1];
            offset += 2;

            // descriptors_length (10 bits, upper 6 bits reserved)
            if (offset + 2 > length) {
                break;
            }
            uint16_t descriptorsLength = (((uint16_t)bytes[offset] & 0x03) << 8) | bytes[offset + 1];
            offset += 2;

            // Parse descriptors
            NSUInteger descriptorsEnd = offset + descriptorsLength;
            while (offset + 2 <= descriptorsEnd && offset + 2 <= length) {
                uint8_t descriptorTag = bytes[offset];
                uint8_t descriptorLen = bytes[offset + 1];
                offset += 2;

                if (offset + descriptorLen > length) {
                    break;
                }

                NSData *descriptorPayload = descriptorLen > 0
                    ? [NSData dataWithBytes:&bytes[offset] length:descriptorLen]
                    : nil;

                TSDescriptor *descriptor = [TSDescriptor makeWithTag:descriptorTag
                                                              length:descriptorLen
                                                                data:descriptorPayload];

                if ([descriptor isKindOfClass:[TSAtscServiceLocationDescriptor class]]) {
                    channel.serviceLocation = (TSAtscServiceLocationDescriptor *)descriptor;
                }

                offset += descriptorLen;
            }

            // Ensure we're at the end of descriptors
            offset = MIN(descriptorsEnd, length);

            [channels addObject:channel];
        }

        _channels = [channels copy];
    }
    return self;
}

-(TSAtscVirtualChannel*)channelForProgramNumber:(uint16_t)programNumber
{
    for (TSAtscVirtualChannel *channel in self.channels) {
        if (channel.programNumber == programNumber) {
            return channel;
        }
    }
    return nil;
}

#pragma mark - Overridden

-(BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[TSAtscVirtualChannelTable class]]) {
        return NO;
    }
    return [self isEqualToVct:(TSAtscVirtualChannelTable*)object];
}

-(BOOL)isEqualToVct:(TSAtscVirtualChannelTable*)vct
{
    return self.tableId == vct.tableId
        && self.psi.versionNumber == vct.psi.versionNumber
        && [self.psi.sectionDataExcludingCrc isEqualToData:vct.psi.sectionDataExcludingCrc];
}

-(NSUInteger)hash
{
    return self.tableId ^ (self.psi.versionNumber << 8);
}

-(NSString*)description
{
    NSMutableString *channelList = [NSMutableString string];
    for (TSAtscVirtualChannel *ch in self.channels) {
        [channelList appendFormat:@"\n    %@", ch];
    }
    return [NSString stringWithFormat:
            @"{ %@ v%u, tsid: %u, channels: [%@\n] }",
            self.isTerrestrial ? @"TVCT" : @"CVCT",
            self.psi.versionNumber,
            self.transportStreamId,
            channelList];
}

@end
