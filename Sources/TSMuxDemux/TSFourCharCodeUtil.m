//
//  TSFourCharCodeUtil
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2021-04-06.
//  Copyright © 2021 Magnus Makes Software. All rights reserved.
//

#import "TSFourCharCodeUtil.h"

// Usage example
// Print c-string: NSLog(@"%s", FourCC2Str(code));
// Print NSString: NSLog(@"%@", @(FourCC2Str(code)));

@implementation TSFourCharCodeUtil

+(NSString*)toString:(FourCharCode)code
{
    return [NSString stringWithFormat:@"%@", @(FourCC2Str(code))];
}

@end
