//
//  TSTr101290AnalyzeContext.m
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2025-12-04.
//

#import "TSTr101290AnalyzeContext.h"

@implementation TSTr101290AnalyzeContext

-(instancetype _Nonnull)initWithPat:(TSProgramAssociationTable* _Nullable)pat
                               pmts:(NSDictionary<PmtPid, TSProgramMapTable*>* _Nullable)pmts
                              nowMs:(uint64_t)nowMs
                  completedSections:(NSArray<TSTr101290CompletedSection*>* _Nonnull)completedSections
{
    self = [super init];
    if (self) {
        _pat = pat;
        _pmts = pmts;
        _nowMs = nowMs;
        _completedSections = completedSections;
    }
    return self;
}

-(instancetype _Nonnull)initWithPat:(TSProgramAssociationTable* _Nullable)pat
                               pmts:(NSDictionary<PmtPid, TSProgramMapTable*>* _Nullable)pmts
                              nowMs:(uint64_t)nowMs
{
    return [self initWithPat:pat pmts:pmts nowMs:nowMs completedSections:@[]];
}

@end
