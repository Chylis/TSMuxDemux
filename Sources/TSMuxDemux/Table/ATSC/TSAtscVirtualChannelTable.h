//
//  TSAtscVirtualChannelTable.h
//  TSMuxDemux
//
//  ATSC A/65 Virtual Channel Table (VCT)
//  TVCT (Table ID 0xC8) - Terrestrial Virtual Channel Table
//  CVCT (Table ID 0xC9) - Cable Virtual Channel Table
//

#import <Foundation/Foundation.h>

@class TSProgramSpecificInformationTable;
@class TSAtscServiceLocationDescriptor;

/// ATSC service type values (A/65 Table 6.7)
typedef NS_ENUM(uint8_t, TSAtscServiceType) {
    TSAtscServiceTypeAnalogTV       = 0x01,
    TSAtscServiceTypeDigitalTV      = 0x02,
    TSAtscServiceTypeAudio          = 0x03,
    TSAtscServiceTypeData           = 0x04,
    TSAtscServiceTypeSoftware       = 0x05,
};

/// A single channel entry in the VCT
@interface TSAtscVirtualChannel : NSObject

/// Channel short name (up to 7 UTF-16 characters)
@property(nonatomic, readonly, nonnull) NSString *shortName;

/// Major channel number (e.g., 5 in "5.1")
@property(nonatomic, readonly) uint16_t majorChannelNumber;

/// Minor channel number (e.g., 1 in "5.1")
@property(nonatomic, readonly) uint16_t minorChannelNumber;

/// MPEG program_number that this channel maps to
@property(nonatomic, readonly) uint16_t programNumber;

/// Service type (analog TV, digital TV, audio, data, etc.)
@property(nonatomic, readonly) TSAtscServiceType serviceType;

/// Source ID for linking to EIT/ETT
@property(nonatomic, readonly) uint16_t sourceId;

/// YES if channel is access controlled (encrypted)
@property(nonatomic, readonly) BOOL accessControlled;

/// YES if channel should be hidden from user
@property(nonatomic, readonly) BOOL hidden;

/// YES if channel should be hidden from guide
@property(nonatomic, readonly) BOOL hideGuide;

/// Service location descriptor (provides A/V PID mappings), or nil if not present
@property(nonatomic, readonly, nullable) TSAtscServiceLocationDescriptor *serviceLocation;

/// Formatted channel number string (e.g., "5.1")
-(NSString* _Nonnull)channelNumberString;

@end

/// ATSC Virtual Channel Table - contains channel name/number mappings
@interface TSAtscVirtualChannelTable : NSObject

/// The underlying PSI table
@property(nonatomic, readonly, nonnull) TSProgramSpecificInformationTable *psi;

/// Table ID (0xC8 for TVCT, 0xC9 for CVCT)
@property(nonatomic, readonly) uint8_t tableId;

/// YES if this is a Terrestrial VCT (TVCT), NO if Cable VCT (CVCT)
@property(nonatomic, readonly) BOOL isTerrestrial;

/// Transport stream ID
@property(nonatomic, readonly) uint16_t transportStreamId;

/// Channels in this VCT section
@property(nonatomic, readonly, nonnull) NSArray<TSAtscVirtualChannel*> *channels;

/// Find channel by program number
-(TSAtscVirtualChannel* _Nullable)channelForProgramNumber:(uint16_t)programNumber;

-(instancetype _Nullable)initWithPSI:(TSProgramSpecificInformationTable* _Nonnull)psi;

-(BOOL)isEqual:(id _Nullable)object;

@end
