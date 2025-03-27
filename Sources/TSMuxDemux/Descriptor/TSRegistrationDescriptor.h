//
//  TSRegistrationDescriptor.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSDescriptor.h"

@interface TSRegistrationDescriptor: TSDescriptor
@property(nonatomic, readonly) uint32_t formatIdentifier;
@property(nonatomic, readonly, nullable) NSData* additionalIdentificationInfo;

-(instancetype _Nonnull)initWithTag:(uint8_t)tag
                            payload:(NSData* _Nonnull)payload
                             length:(NSUInteger)length;

@end
