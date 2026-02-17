# TSMuxDemux

A MPEG-TS muxer and demuxer for iOS/tvOS written in Obj-C.

Supports both DVB and ATSC broadcast standards.

**Disclaimer:** The muxer and demuxer provide basic functionality and are not fully compliant with ITU-T H.222.

## Demuxer

### Supported Standards

The demuxer operates in one of two modes:

- **DVB** (`TSDemuxerModeDVB`): European Digital Video Broadcasting
  - SDT (Service Description Table): Implemented
  - DVB Descriptors: Tag 0x48 (Service) parsed
  - DVB String Encoding: ISO 6937, ISO 8859-x, UTF-8

- **ATSC** (`TSDemuxerModeATSC`): North American Advanced Television Systems Committee
  - VCT (Virtual Channel Table): Header parsing
  - Stream types 0x81/0x87: AC-3/E-AC-3

### Usage

1) Create a demuxer delegate conforming to `TSDemuxerDelegate`:
```objc
@interface DemuxerDelegate <TSDemuxerDelegate>

// Required callbacks (standard-agnostic)

-(void)demuxer:(TSDemuxer *)demuxer
  didReceivePat:(TSProgramAssociationTable *)pat
    previousPat:(TSProgramAssociationTable *)previousPat
{
    NSLog(@"Received PAT containing %lu programmes", (unsigned long)pat.programmes.count);
}

-(void)demuxer:(TSDemuxer *)demuxer
  didReceivePmt:(TSProgramMapTable *)pmt
    previousPmt:(TSProgramMapTable *)previousPmt
{
    NSLog(@"Received PMT for program %hu containing %lu tracks",
          pmt.programNumber, (unsigned long)pmt.elementaryStreams.count);
}

-(void)demuxer:(TSDemuxer *)demuxer didReceiveAccessUnit:(TSAccessUnit *)accessUnit
{
    switch (accessUnit.resolvedStreamType) {
        case TSResolvedStreamTypeAAC_ADTS:
            NSLog(@"Received AAC audio");
            break;
        case TSResolvedStreamTypeAC3:
            NSLog(@"Received AC-3 audio");
            break;
        case TSResolvedStreamTypeH264:
            NSLog(@"Received H.264 video");
            break;
        case TSResolvedStreamTypeH265:
            NSLog(@"Received H.265/HEVC video");
            break;
        default:
            NSLog(@"Received %@", accessUnit.resolvedStreamTypeDescription);
            break;
    }
}

// Optional DVB-specific callback (only called in TSDemuxerModeDVB)

-(void)demuxer:(TSDemuxer *)demuxer
  didReceiveSdt:(TSDvbServiceDescriptionTable *)sdt
    previousSdt:(TSDvbServiceDescriptionTable *)previousSdt
{
    NSLog(@"Received DVB SDT");
}

// Optional ATSC-specific callback (only called in TSDemuxerModeATSC)

-(void)demuxer:(TSDemuxer *)demuxer
  didReceiveVct:(TSAtscVirtualChannelTable *)vct
    previousVct:(TSAtscVirtualChannelTable *)previousVct
{
    NSLog(@"Received ATSC VCT");
}

@end
```

2) Create demuxer with desired mode:
```objc
// For DVB streams
self.demuxer = [[TSDemuxer alloc] initWithDelegate:self mode:TSDemuxerModeDVB];

// For ATSC streams
self.demuxer = [[TSDemuxer alloc] initWithDelegate:self mode:TSDemuxerModeATSC];
```

3) Feed demuxer with TS data:
```objc
-(void)didReceiveRawTsPacketData:(NSData *)tsData
{
    uint64_t arrivalTime = [TSTimeUtil nowHostTimeNanos];
    [self.demuxer demux:tsData dataArrivalHostTimeNanos:arrivalTime];
}
```

4) Access parsed state:
```objc
// Standard-agnostic state
TSProgramAssociationTable *pat = self.demuxer.pat;
NSDictionary<ProgramNumber, TSProgramMapTable*> *pmts = self.demuxer.pmts;

// DVB-specific state (only populated in DVB mode)
TSDvbServiceDescriptionTable *sdt = self.demuxer.dvb.sdt;

// ATSC-specific state (only populated in ATSC mode)
TSAtscVirtualChannelTable *vct = self.demuxer.atsc.vct;
```

5) Access TR 101 290 statistics:
```objc
TSTr101290Statistics *stats = [self.demuxer statistics];
NSLog(@"Sync byte errors: %llu", stats.prio1.syncByteError);
NSLog(@"PAT errors: %llu", stats.prio1.patError);
NSLog(@"Continuity errors: %llu", stats.prio1.ccError);
```

### Resolved Stream Types

The demuxer resolves raw PMT stream types and descriptors into `TSResolvedStreamType`:

| Resolved Type | Description |
|---------------|-------------|
| `TSResolvedStreamTypeH264` | AVC / H.264 video |
| `TSResolvedStreamTypeH265` | HEVC / H.265 video |
| `TSResolvedStreamTypeAAC_ADTS` | AAC with ADTS transport |
| `TSResolvedStreamTypeAAC_LATM` | AAC with LATM transport |
| `TSResolvedStreamTypeAC3` | Dolby Digital |
| `TSResolvedStreamTypeEAC3` | Dolby Digital Plus |
| `TSResolvedStreamTypeMPEG1Audio` | MPEG-1 Audio |
| `TSResolvedStreamTypeMPEG2Audio` | MPEG-2 Audio |
| `TSResolvedStreamTypeSCTE35` | SCTE-35 splice info |
| `TSResolvedStreamTypeTeletext` | DVB Teletext |
| `TSResolvedStreamTypeSubtitles` | DVB Subtitles |

## Muxer

A "single program" muxer. Supports VBR and CBR modes.

### Usage

1) Create a muxer delegate conforming to `TSMuxerDelegate`:
```objc
@interface MuxerDelegate <TSMuxerDelegate>

-(void)muxer:(TSMuxer *)muxer didMuxTSPacketData:(NSData *)tsPacketData
{
    // Received 188 bytes of raw TS data
}

@end
```

2) Configure settings (all properties are required):
```objc
TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
settings.pmtPid = 4096;
settings.videoPid = 200;
settings.audioPid = 210;
settings.pcrPid = 200;              // Typically same as videoPid
settings.psiIntervalMs = 250;       // TR 101 290 requires <= 500ms
settings.pcrIntervalMs = 30;        // ISO 13818-1 recommends <= 40ms
settings.targetBitrateKbps = 35000; // 0 = VBR, > 0 = CBR with null-packet stuffing
settings.maxNumQueuedAccessUnits = 300; // 0 = unlimited
```

3) Create muxer:
```objc
uint64_t (^clock)(void) = ^{ return [TSTimeUtil nowHostTimeNanos]; };
self.muxer = [[TSMuxer alloc] initWithSettings:settings wallClockNanos:clock delegate:self];
```

4) Enqueue access units and call tick to emit packets:
```objc
// Enqueue — does NOT emit any packets
[self.muxer enqueueAccessUnit:au];

// Tick — emits packets up to current wall-clock time
// VBR: flushes all queued AUs immediately.
// CBR: paces output with null-packet stuffing to maintain target bitrate.
[self.muxer tick];
```

The caller is responsible for calling `tick` at a regular interval (e.g. every 10ms) to keep CBR output paced. In VBR mode, calling `tick` right after each `enqueueAccessUnit:` is sufficient.

## Notes and Limitations

- The muxer and demuxer are **not thread safe**. Ensure `enqueueAccessUnit:` and `tick` are called from the same serial queue/thread.
- The muxer produces a single-program transport stream.

## References

### Specifications
- ISO/IEC 13818-1: MPEG-2 Transport Stream
- DVB EN 300 468: https://www.etsi.org/deliver/etsi_en/300400_300499/300468/01.17.01_60/en_300468v011701p.pdf
- ATSC A/65:2013: https://www.atsc.org/wp-content/uploads/2021/04/A65_2013.pdf
- TR 101 290: https://www.etsi.org/deliver/etsi_tr/101200_101299/101290/01.05.01_60/tr_101290v010501p.pdf

### TR 101 290 Implementation References
- https://github.com/VitaliyKononovich/iptv-analyzer/blob/master/ts/ts_stat.py
- https://github.com/Cinegy/TsAnalyser/blob/master/Cinegy.TsAnalyzer/Program.cs
- https://cdn.rohde-schwarz.com/pws/dl_downloads/dl_application/application_notes/7bm55/7BM55_0E.pdf
- https://www.tek.com/en/documents/technical-brief/laymans-guide-pcr-measurements
