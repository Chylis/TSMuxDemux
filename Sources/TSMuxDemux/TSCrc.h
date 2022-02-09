//
//  TSCrc.h
//  
//
//  Created by Magnus G Eriksson on 2021-04-19.
//

#import <Foundation/Foundation.h>

@interface TSCrc : NSObject

+(uint32_t)crc32:(const uint8_t *)pData length:(NSUInteger)length;

@end
