//
//  TSTr101290Statistics.m
//  
//
//  Created by Magnus Eriksson on 2023-03-01.
//

#import "TSTr101290Statistics.h"

#pragma mark - TSTr10129Prio1

@implementation TSTr10129Prio1

-(instancetype)init
{
    self = [super init];
    if (self) {
        _tsSyncLoss = 0;
        _syncByteError = 0;
        _patError = 0;
        _ccError = 0;
        _pmtError = 0;
        _pidError = 0;
    }
    return self;
}

-(NSString*)description
{
    return [NSString stringWithFormat:@"tsSyncLoss: %llu\nsyncByteError: %llu\npatError: %llu\npmtError: %llu\nccError: %llu\npidError: %llu",
            _tsSyncLoss,
            _syncByteError,
            _patError,
            _pmtError,
            _ccError,
            _pidError
    ];
}
@end

#pragma mark - TSTr10129Statistics


@implementation TSTr101290Statistics

-(instancetype)init
{
    self = [super init];
    if (self) {
        _prio1 = [TSTr10129Prio1 new];
    }
    return self;
}
@end
