//
//  TSContinuityChecker.m
//  TSMuxDemux
//
//  Validates TS packet continuity counter per ITU-T H.222.0 §2.4.3.3
//

#import "TSContinuityChecker.h"
#import "TSPacket.h"

@implementation TSContinuityChecker
{
    BOOL _hasLastCC;
    uint8_t _lastContinuityCounter;
}

-(TSContinuityCheckResult)checkPacket:(TSPacket * _Nonnull)packet
{
    TSContinuityCheckResult result = TSContinuityCheckResultOK;

    // Per ITU-T H.222.0 §2.4.3.3:
    // - CC increments only when packet contains payload (not adaptation-only)
    // - Discontinuity flag allows CC to be discontinuous
    // - Duplicate packets (same CC) are allowed for retransmission

    BOOL isExpectingIncrementedCC =
        packet.header.adaptationMode != TSAdaptationModeReserved &&
        packet.header.adaptationMode != TSAdaptationModeAdaptationOnly;

    if (_hasLastCC && !packet.adaptationField.discontinuityFlag) {
        BOOL isDuplicate = (packet.header.continuityCounter == _lastContinuityCounter);
        uint8_t expectedNextCC = (_lastContinuityCounter + 1) & 0x0F;

        if (isExpectingIncrementedCC) {
            // Packet has payload: expect incremented CC or duplicate (retransmission)
            BOOL isExpectedNext = (packet.header.continuityCounter == expectedNextCC);
            if (isDuplicate) {
                result = TSContinuityCheckResultDuplicate;
            } else if (!isExpectedNext) {
                result = TSContinuityCheckResultGap;
            }
        } else {
            // Adaptation only (no payload): CC should not change
            if (!isDuplicate) {
                result = TSContinuityCheckResultGap;
            } else {
                result = TSContinuityCheckResultDuplicate;
            }
        }
    }

    _hasLastCC = YES;
    _lastContinuityCounter = packet.header.continuityCounter;

    return result;
}

@end
