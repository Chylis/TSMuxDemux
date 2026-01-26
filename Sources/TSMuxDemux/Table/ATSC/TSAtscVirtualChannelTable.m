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
#import "../../TSBitReader.h"

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

        TSBitReader reader = TSBitReaderMake(data);

        // sectionDataExcludingCrc layout:
        // Bytes 0-1: transport_stream_id (accessed via psi.byte4And5)
        // Byte 2: reserved (2) + version_number (5) + current_next_indicator (1)
        // Byte 3: section_number
        // Byte 4: last_section_number
        // Byte 5: protocol_version (VCT-specific)
        // Byte 6: num_channels_in_section
        // Bytes 7+: channel loop

        // Skip to protocol_version at offset 5
        TSBitReaderSkip(&reader, 5);
        if (reader.error) {
            TSLogWarn(@"VCT: section data truncated before protocol_version");
            _channels = @[];
            return self;
        }

        // protocol_version (8 bits)
        TSBitReaderReadUInt8(&reader);  // Skip protocol version

        // num_channels_in_section (8 bits)
        uint8_t numChannels = TSBitReaderReadUInt8(&reader);
        if (reader.error) {
            TSLogWarn(@"VCT: section data truncated before num_channels");
            _channels = @[];
            return self;
        }

        NSMutableArray<TSAtscVirtualChannel*> *channels = [NSMutableArray arrayWithCapacity:numChannels];

        for (uint8_t i = 0; i < numChannels; i++) {
            // Each channel entry is at least 32 bytes (fixed part)
            if (TSBitReaderRemainingBytes(&reader) < 32) {
                TSLogWarn(@"VCT: insufficient data for channel %u", i);
                break;
            }

            TSAtscVirtualChannel *channel = [TSAtscVirtualChannel new];

            // short_name: 7 x 16-bit UTF-16BE characters (14 bytes)
            NSData *nameData = TSBitReaderReadData(&reader, 14);
            NSString *name = [[NSString alloc] initWithData:nameData encoding:NSUTF16BigEndianStringEncoding];
            // Trim to remove padded null chars, e.g. "XYZ\0\0\0\0" --> "XYZ".
            channel.shortName = [name stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\0"]] ?: @"";

            // 4 bytes containing major/minor channel numbers and modulation
            // Bits: rrrr(4) + major_channel_number(10) + minor_channel_number(10) + modulation_mode(8)
            TSBitReaderReadBits(&reader, 4);  // reserved
            channel.majorChannelNumber = TSBitReaderReadBits(&reader, 10);
            channel.minorChannelNumber = TSBitReaderReadBits(&reader, 10);
            TSBitReaderReadBits(&reader, 8);  // modulation_mode (unused)

            // carrier_frequency (32 bits) - deprecated, skip
            TSBitReaderSkip(&reader, 4);

            // channel_TSID (16 bits) - skip
            TSBitReaderSkip(&reader, 2);

            // program_number (16 bits)
            channel.programNumber = TSBitReaderReadUInt16BE(&reader);

            // Flags byte 1: ETM_location (2), access_controlled (1), hidden (1),
            //               path_select (1), out_of_band (1), hide_guide (1), reserved (1)
            TSBitReaderReadBits(&reader, 2);  // ETM_location
            channel.accessControlled = TSBitReaderReadBits(&reader, 1) != 0;
            channel.hidden = TSBitReaderReadBits(&reader, 1) != 0;
            TSBitReaderReadBits(&reader, 2);  // path_select, out_of_band
            channel.hideGuide = TSBitReaderReadBits(&reader, 1) != 0;
            TSBitReaderReadBits(&reader, 1);  // reserved

            // Flags byte 2: reserved (2), service_type (6)
            TSBitReaderReadBits(&reader, 2);  // reserved
            channel.serviceType = TSBitReaderReadBits(&reader, 6);

            // source_id (16 bits)
            channel.sourceId = TSBitReaderReadUInt16BE(&reader);

            // descriptors_length (6 reserved + 10 bits length)
            TSBitReaderReadBits(&reader, 6);  // reserved
            uint16_t descriptorsLength = TSBitReaderReadBits(&reader, 10);

            if (reader.error) {
                TSLogWarn(@"VCT: read error while parsing channel %u", i);
                break;
            }

            // Parse descriptors using a sub-reader
            if (descriptorsLength > 0 && TSBitReaderRemainingBytes(&reader) >= descriptorsLength) {
                TSBitReader descReader = TSBitReaderSubReader(&reader, descriptorsLength);

                while (TSBitReaderRemainingBytes(&descReader) >= 2) {
                    uint8_t descriptorTag = TSBitReaderReadUInt8(&descReader);
                    uint8_t descriptorLen = TSBitReaderReadUInt8(&descReader);

                    if (descReader.error || TSBitReaderRemainingBytes(&descReader) < descriptorLen) {
                        TSLogWarn(@"VCT: descriptor truncated for channel %u", i);
                        break;
                    }

                    NSData *descriptorPayload = descriptorLen > 0
                        ? TSBitReaderReadData(&descReader, descriptorLen)
                        : nil;

                    TSDescriptor *descriptor = [TSDescriptor makeWithTag:descriptorTag
                                                                  length:descriptorLen
                                                                    data:descriptorPayload];

                    if ([descriptor isKindOfClass:[TSAtscServiceLocationDescriptor class]]) {
                        channel.serviceLocation = (TSAtscServiceLocationDescriptor *)descriptor;
                    }
                }
            } else if (descriptorsLength > 0) {
                // Skip remaining if not enough data
                break;
            }

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
