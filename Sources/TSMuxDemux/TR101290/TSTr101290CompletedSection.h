//
//  TSTr101290CompletedSection.h
//  TSMuxDemux
//
//  Created by Magnus G Eriksson on 2025-12-08.
//

#import <Foundation/Foundation.h>
@class TSProgramSpecificInformationTable;

/// Represents a completed PSI section for TR101290 analysis
@interface TSTr101290CompletedSection : NSObject

/// The completed PSI section
@property(nonatomic, strong, readonly, nonnull) TSProgramSpecificInformationTable *section;

/// The PID on which the section was completed
@property(nonatomic, readonly) uint16_t pid;

-(instancetype _Nonnull)initWithSection:(TSProgramSpecificInformationTable* _Nonnull)section
                                    pid:(uint16_t)pid;

@end
