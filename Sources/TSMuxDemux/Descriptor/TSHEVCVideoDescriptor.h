//
//  TSHEVCVideoDescriptor.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2025-12-18.
//  Copyright © 2025 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSDescriptor.h"

/// HEVC Video Descriptor (tag 0x38) as defined in ISO/IEC 13818-1 AMD3.
/// Provides HEVC stream signaling including profile/tier/level and scan type.
@interface TSHEVCVideoDescriptor: TSDescriptor

/// Profile space (2 bits)
@property(nonatomic, readonly) uint8_t profileSpace;

/// Tier flag: NO = Main tier, YES = High tier
@property(nonatomic, readonly) BOOL tierFlag;

/// Profile IDC (5 bits)
@property(nonatomic, readonly) uint8_t profileIDC;

/// Profile compatibility indication (32 bits)
@property(nonatomic, readonly) uint32_t profileCompatibilityIndication;

/// Progressive source flag
@property(nonatomic, readonly) BOOL progressiveSourceFlag;

/// Interlaced source flag
@property(nonatomic, readonly) BOOL interlacedSourceFlag;

/// Non-packed constraint flag
@property(nonatomic, readonly) BOOL nonPackedConstraintFlag;

/// Frame only constraint flag
@property(nonatomic, readonly) BOOL frameOnlyConstraintFlag;

/// Level IDC (8 bits)
@property(nonatomic, readonly) uint8_t levelIDC;

/// Temporal layer subset flag - indicates if temporal_id_min/max are present
@property(nonatomic, readonly) BOOL temporalLayerSubsetFlag;

/// HEVC still present flag
@property(nonatomic, readonly) BOOL HEVCStillPresentFlag;

/// HEVC 24-hour picture present flag
@property(nonatomic, readonly) BOOL HEVC24HrPicturePresentFlag;

/// Sub-picture HRD params not present flag
@property(nonatomic, readonly) BOOL subPicHrdParamsNotPresent;

/// HDR/WCG indicator (2 bits):
/// 0 = SDR, 1 = SDR+WCG, 2 = HDR+WCG, 3 = no indication
@property(nonatomic, readonly) uint8_t HDRWCGIdc;

/// Minimum temporal ID (3 bits) - only valid when temporalLayerSubsetFlag == YES
@property(nonatomic, readonly) uint8_t temporalIdMin;

/// Maximum temporal ID (3 bits) - only valid when temporalLayerSubsetFlag == YES
@property(nonatomic, readonly) uint8_t temporalIdMax;

-(instancetype _Nonnull)initWithTag:(uint8_t)tag
                            payload:(NSData* _Nonnull)payload
                             length:(NSUInteger)length;

@end
