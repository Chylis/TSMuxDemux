//
//  TSTr101290AnalyzeContext.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2025-12-04.
//

#import <Foundation/Foundation.h>
@class TSProgramAssociationTable;
@class TSProgramMapTable;
@class TSTr101290CompletedSection;

typedef NSNumber* PmtPid;

@interface TSTr101290AnalyzeContext : NSObject

/// Current PAT (for determining PMT PIDs)
@property(nonatomic, strong, readonly, nullable) TSProgramAssociationTable *pat;

/// Current PMTs (for determining elementary streams per program)
@property(nonatomic, strong, readonly, nullable) NSDictionary<PmtPid, TSProgramMapTable*> *pmts;

/// Current timestamp in milliseconds
@property(nonatomic, readonly) uint64_t nowMs;

/// PSI sections that were just completed (if any). Used for interval and tableId checks.
/// A single packet can complete multiple sections.
@property(nonatomic, strong, readonly, nonnull) NSArray<TSTr101290CompletedSection*> *completedSections;

/// Elementary stream PID whitelist. nil means no whitelist: all ES PIDs are
/// monitored. An empty set excludes all ES PIDs. Used to exclude
/// whitelisted-out PIDs from PID_error interval checks - their packets never
/// reach the analyzer, so they would otherwise raise false PID errors.
@property(nonatomic, strong, readonly, nullable) NSSet<NSNumber*> *esPidWhitelist;

-(instancetype _Nonnull)initWithPat:(TSProgramAssociationTable* _Nullable)pat
                               pmts:(NSDictionary<PmtPid, TSProgramMapTable*>* _Nullable)pmts
                              nowMs:(uint64_t)nowMs
                  completedSections:(NSArray<TSTr101290CompletedSection*>* _Nonnull)completedSections
                        esPidWhitelist:(NSSet<NSNumber*>* _Nullable)esPidWhitelist;

@end
