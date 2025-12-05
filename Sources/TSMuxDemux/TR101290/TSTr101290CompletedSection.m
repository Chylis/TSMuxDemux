//
//  TSTr101290CompletedSection.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2025-12-08.
//

#import "TSTr101290CompletedSection.h"

@implementation TSTr101290CompletedSection

-(instancetype _Nonnull)initWithSection:(TSProgramSpecificInformationTable* _Nonnull)section
                                    pid:(uint16_t)pid
{
    self = [super init];
    if (self) {
        _section = section;
        _pid = pid;
    }
    return self;
}

@end
