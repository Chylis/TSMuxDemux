//
//  TSCueIdentifierDescriptor.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSDescriptor.h"

typedef NS_ENUM(uint8_t, TSScte35CueStreamType) {
    TSScte35CueStreamTypeSpliceInsertOrNullOrSchedule = 0x00,
    TSScte35CueStreamTypeAllCommands = 0x01,
    TSScte35CueStreamTypeSegmentation = 0x02,
    TSScte35CueStreamTypeTieredSplicing = 0x03,
    TSScte35CueStreamTypeTieredSegmentation = 0x04,
    // 0x05 - 0x7f = reserved
    // 0x80 - 0xff = user defined
};

// This descriptor is defined in ANSI/SCTE 35 - Digital Program Insertion Cueing Message
@interface TSCueIdentifierDescriptor: TSDescriptor

@property(nonatomic, readonly) uint8_t cueStreamType;

-(instancetype _Nonnull)initWithTag:(uint8_t)tag
                            payload:(NSData* _Nonnull)payload
                             length:(NSUInteger)length;

@end
