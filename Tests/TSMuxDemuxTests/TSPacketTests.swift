//
//  TSPacketTests.swift
//  TSMuxDemuxTests
//
//  Created by Magnus Eriksson on 2021-04-10.
//

import XCTest
final class TSPacketTests: XCTestCase {
    
    let tsPacketSize = 188
    let tsPacketHeaderSize = 4
    let maxPayloadSize = 182 // 188 - 4 bytes header - 2 bytes adaptation field (currently always included)
    
    static var allTests = [
        ("testPayloadDataToTsPacketData_Sizing", test_payloadDataToTsPacketData_Sizing),
        ("testPayloadDataToTsPacketData_Contents", test_payloadDataToTsPacketData_Contents),
        ("test_packetHeaderToData_Contents", test_packetHeaderToData_Contents),
    ]
    
    func test_payloadDataToTsPacketData_Sizing() {
        for payloadSize in [0, 1, 187, 188, 189, 5000, 15000] {
            var packetData = [Data]()
            TSPacket.packetizePayload(Data(count: payloadSize),
                                      track: TSElementaryStream(pid: 256, streamType: TSStreamType.H264),
                                      forcePusi: false) { tsPacketData in
                packetData.append(tsPacketData)
            }
            
            let expectedNumberOfPackets = Int(ceil(Double(payloadSize) / Double(tsPacketSize - tsPacketHeaderSize - 2)))
            XCTAssertEqual(expectedNumberOfPackets, packetData.count)
            
            for packet in packetData {
                XCTAssertEqual(tsPacketSize, packet.count)
            }
        }
    }
    
    func test_payloadDataToTsPacketData_Contents() {
        let payloadByte: UInt8 = 0x00
        let adaptationStuffingByte: UInt8 = 0xFF
        let packetIdentifier: UInt16 = 7777
        let numberOfPackets = 32
        // Add some extra payload bytes so we don't get an 188-aligned size, thus forcing adaptation field padding in the final packet.
        // E.g. 18 extra payload bytes should result in 188 - 4 - 1 = 165 adaptation field stuffing bytes
        let extraPayloadBytes = 18
        let expectedNumberOfAdaptationStuffingBytes = 188 - tsPacketHeaderSize - 2 - extraPayloadBytes
        let numberOfPayloadBytes = (numberOfPackets * maxPayloadSize) + extraPayloadBytes
        
        var packets = [Data]()
        TSPacket.packetizePayload(Data(repeating: payloadByte, count: numberOfPayloadBytes),
                                  track: TSElementaryStream(pid: packetIdentifier, streamType: TSStreamType.H264),
                                  forcePusi: false) { packets.append($0) }
        
        XCTAssertEqual(numberOfPackets + 1, packets.count)
        
        for (index, packet) in packets.enumerated() {
            XCTAssertEqual(tsPacketSize, packet.count)
            
            guard let tsPacket = TSPacket.initWithTsPacketData(packet) else {
                return XCTFail("Failed creating ts packet from raw data")
            }
            
            let header = tsPacket.header
            assertHeader(header)
            XCTAssertEqual(header.payloadUnitStartIndicator, index == 0)
            XCTAssertEqual(header.continuityCounter, UInt8(index % 16))
            
            
            // Assert adaptation header + stuffing bytes
            let adaptationLen = packet[4]
            assertAdaptationField(TSAdaptationField(adaptationFieldLength: adaptationLen,
                                                    numberOfStuffedBytes: UInt(adaptationLen - 1)))
            
            let adaptationFieldHasStuffing = adaptationLen > 1
            let adaptationFieldShouldHaveStuffing = index == numberOfPackets
            XCTAssertEqual(adaptationFieldShouldHaveStuffing, adaptationFieldHasStuffing)
            
            if (adaptationFieldHasStuffing) {
                // + 1 for the metadata-byte after the adaptation field length
                XCTAssertEqual(Int(adaptationLen), 1 + expectedNumberOfAdaptationStuffingBytes)
                
                let adaptationData = packet.subdata(in: tsPacketHeaderSize+2..<Int(tsPacketHeaderSize+1+Int(adaptationLen)))
                XCTAssertEqual(adaptationData, Data(repeating: adaptationStuffingByte,
                                                    count: Int(expectedNumberOfAdaptationStuffingBytes)))
            }
            
            XCTAssertEqual(packet[5], 0)
            
            
            
            
            // Assert payload
            let payloadOffset = Int(tsPacketHeaderSize + 1 + Int(adaptationLen))
            let payloadSize = packet.count - Int(payloadOffset)
            let payloadData = packet.subdata(in: payloadOffset..<packet.count)
            XCTAssertEqual(payloadData, Data(repeating: payloadByte, count: payloadSize))
            XCTAssertLessThanOrEqual(payloadSize, maxPayloadSize)
            XCTAssertEqual(tsPacketHeaderSize + 1 + Int(adaptationLen) + payloadSize, tsPacketSize)
        }
    }
    
    func test_packetHeaderToData_Contents() {
        for expectedAdaptationMode in [TSAdaptationMode.adaptationAndPayload,
                                       TSAdaptationMode.payloadOnly,
                                       TSAdaptationMode.adaptationOnly] {
            for boolValue in [true, false] {
                let expectedTei = boolValue
                let expectedPusi = boolValue
                let expectedPrio = boolValue
                let expectedPid: UInt16 = 777
                let expectedScrambled = boolValue
                let expectedCc: UInt8 = 7
                
                assertHeader(TSPacketHeader(tei: expectedTei,
                                            pusi: expectedPusi,
                                            transportPriority: expectedPrio,
                                            pid: expectedPid,
                                            isScrambled: expectedScrambled,
                                            adaptationMode: expectedAdaptationMode,
                                            continuityCounter: expectedCc))
            }
        }
    }
    
    
    
    func test_AdaptationFieldToData_Contents() {
        let numberOfBytesToStuff: UInt8 = 183
        assertAdaptationField(TSAdaptationField(adaptationFieldLength: numberOfBytesToStuff + 1,
                                                numberOfStuffedBytes: UInt(numberOfBytesToStuff)))
    }
    
    
    
    
    
    
    
    
    private func assertHeader(_ header: TSPacketHeader) {
        let expectedSyncByte: UInt8 = 0x47
        let data = header.getBytes()
        let syncByte =            data[0]
        let tei =                ((data[1] & 0b10000000) >> 7) == 0x01
        let pusi =               ((data[1] & 0b01000000) >> 6) == 0x01
        let prio =               ((data[1] & 0b00100000) >> 5) == 0x01
        let pid =          (UInt16(data[1] & 0b00011111) << 8) | UInt16(data[2])
        let scrambling =         ((data[3] & 0b11000000) >> 6) == 0x01
        let adaptation =         TSAdaptationMode(rawValue: (data[3] & 0b00110000) >> 4)
        let cc =                  data[3] & 0b00001111
        
        XCTAssertEqual(syncByte, expectedSyncByte)
        XCTAssertEqual(tei, header.transportErrorIndicator)
        XCTAssertEqual(pusi, header.payloadUnitStartIndicator)
        XCTAssertEqual(prio, header.transportPriority)
        XCTAssertEqual(pid, header.pid)
        XCTAssertEqual(scrambling, header.isScrambled)
        XCTAssertEqual(adaptation, header.adaptationMode)
        XCTAssertEqual(cc, header.continuityCounter)
    }
    
    private func assertAdaptationField(_ adaptationField: TSAdaptationField) {
        let data = adaptationField.getBytes()
        
        // FIXME: Parse remaining fields and test...
        
        XCTAssertEqual(adaptationField.adaptationFieldLength, data[0])
        XCTAssertEqual(adaptationField.numberOfStuffedBytes, UInt(data.count) - UInt(TS_PACKET_ADAPTATION_HEADER_SIZE))
        
        let stuffingByte: UInt8 = 0xFF
        XCTAssertEqual(Data(repeating: stuffingByte, count: Int(adaptationField.numberOfStuffedBytes)),
                       data.subdata(in: Int(TS_PACKET_ADAPTATION_HEADER_SIZE)..<data.count))
        
        //FIXME MG: Test the below
        // When the adaptation_field_control value is '11 - both', the value of the adaptation_field_length shall be in the range 0 to 182.
        // When the adaptation_field_control value is '10 - adaptation only', the value of the adaptation_field_length shall be 183.
    }
    
}
