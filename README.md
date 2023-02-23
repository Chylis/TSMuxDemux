# TSMuxDemux

A MPEG-TS muxer and demuxer for iOS written in Obj-C.

*\*Disclaimer\**
The muxer and demuxer provide basic functionality and are not fully compliant with ITU-T H.222.

## Muxer
A "single program" muxer.

### Usage

1) Create a muxer delegate that will receive raw ts data by conforming to the `TSMuxerDelegate` protocol
```
@interface MuxerDelegate <TSMuxerDelegate>

-(void)muxer:(TSMuxer * _Nonnull)muxer didMuxTSPacketData:(NSData* _Nonnull)tsPacketData
{
    // Got 188-bytes of raw ts data
}

@end
```

2. *\*Optional\** Configure desired settings
```
TSMuxerSettings *settings = [[TSMuxerSettings alloc] init];
settings.pmtPid = 4096;
settings.psiIntervalMs = 500;
```

3. Create muxer
```
self.muxer = [[TSMuxer alloc] initWithSettings:settings delegate:self];
```

4. Feed muxer
```
-(void)didReceiveH264:(H264*)aSample
{
  TSAccessUnit *au = [[TSAccessUnit alloc] initWithPid:aSample.pid
                                                 pts:aSample.pts
                                                 dts:aSample.dts
                                          streamType:TSStreamTypeH264
                                      compressedData:aSample.data];
  [self.muxer mux:au];
}
```

## Demuxer

### Usage

1) Create a demuxer delegate that will receive PSI-tables and elementary stream access units by conforming to the `TSMuxerDelegate` protocol
```
@interface DemuxerDelegate <TSDemuxerDelegate>

-(void)demuxer:(TSDemuxer * _Nonnull)muxer didReceivePat:(TSProgramAssociationTable * _Nonnull)pat
{
    NSLog(@"Received PAT containing %lu programmes", (unsigned long)pat.programmes.count);
}

-(void)demuxer:(TSDemuxer * _Nonnull)muxer didReceivePmt:(TSProgramMapTable * _Nonnull)pmt
{
    NSLog(@"Received PMT for program %hu containing %lu tracks", pmt.programNumber, (unsigned long)pmt.elementaryStreams.count);
}

-(void)demuxer:(TSDemuxer * _Nonnull)muxer didReceiveAccessUnit:(TSAccessUnit * _Nonnull)accessUnit
{
  switch (accessUnit.streamType) {
    case TSStreamTypeADTSAAC:
      NSLog(@"Received audio");
      break;
      
    case TSStreamTypeH264:
      NSLog(@"Received H264");
      break;
      
    case TSStreamTypeH265:
      NSLog(@"Received H265/HEVC");
      break;
  }
}

@end
```

2. Create demuxer
```
self.demuxer = [[TSDemuxer alloc] initWithDelegate:self];
```

3. Feed demuxer
```
-(void)didReceiveRawTsPacketData:(NSData*)aRawTsPacketData
{
  [self.demuxer demux:aRawTsPacketData];
}
```

## Notes, Todos and Limitations
- The muxer and demuxer are (currently) not thread safe - i.e. it is the responsibility of the client to ensure that calls are performed from the same thread.


Resources:

- https://books.google.se/books?id=5kVUfnt1QQYC&lpg=PA181&ots=VvZoiOi3jm&dq=ts_sync_loss&pg=PA181#v=onepage&q=ts_sync_loss&f=false

# TR101290
https://github.com/VitaliyKononovich/iptv-analyzer/blob/master/ts/ts_stat.py
https://github.com/Cinegy/TsAnalyser/blob/master/Cinegy.TsAnalyzer/Program.cs
https://github.com/tengym/tsparse/blob/master/tscheck/src/TsErrorCheck_TwoLevel.c#L482
https://github.com/easyice/libeasyice/tree/master/libtr101290/src
https://cdn.rohde-schwarz.com/pws/dl_downloads/dl_application/application_notes/7bm55/7BM55_0E.pdf page 9
https://www.tek.com/en/documents/technical-brief/laymans-guide-pcr-measurements
