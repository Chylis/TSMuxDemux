//
//  TSStringEncodingUtil.h
//  TSMuxDemux
//

#import <Foundation/Foundation.h>

@interface TSStringEncodingUtil : NSObject


// DVB ETSI-EN-300-468 Annex A.2 Selection of character table - Table A.3: Character coding tables
+(NSString*)dvbStringFromCharData:(NSData*)data;


@end
