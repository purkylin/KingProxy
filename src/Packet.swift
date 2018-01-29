//
//  Packet.swift
//  PacketTunnel
//
//  Created by Purkylin King on 2017/12/5.
//  Copyright © 2017年 Purkylin King. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift

extension Data {
    func withUnsafeRawPointer<ResultType>(_ body: (UnsafeRawPointer) throws -> ResultType) rethrows -> ResultType {
        return try self.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> ResultType in
            try body(UnsafeRawPointer(ptr))
        }
    }
}

class BinaryScanner {
    var position: Int = 0
    var data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    func skip(length: UInt32) {
        position += Int(length)
    }
    
    func readNumber<T: Numeric>() -> T {
        let value = data.withUnsafeBytes { (pointer: UnsafePointer<T>) in
            UnsafeRawPointer(pointer).advanced(by: position).assumingMemoryBound(to: T.self).pointee
        }
        position += MemoryLayout<T>.size
        return value
    }
    
    func read8() -> UInt8 {
        return readNumber()
    }
    
    func read16() -> UInt16 {
        return readNumber()
    }
    
    func read32() -> UInt32 {
        return readNumber()
    }
    
    func read64() -> UInt64 {
        return readNumber()
    }
    
    func read(length: UInt32) -> Data {
        let value = data.advanced(by: position)
        position += Int(length)
        return value
    }
}

func toIPV4(_ num: UInt32) -> String {
    var arr:[UInt32] = [0, 0, 0, 0]
    arr[0] = num >> 24 & 0xff
    arr[1] = num >> 16 & 0xff
    arr[2] = num >> 8  & 0xff
    arr[3] = num >> 0  & 0xff
    return arr.map {"\($0)"}.joined(separator: ".")
}

protocol ProtocolPacket {
    var payload: Data? { get set }
    var sourcePort: UInt16 { get set }
    var dstPort: UInt16 { get set }
}

class TCPPacket: ProtocolPacket {
    var payload: Data?
    var sourcePort: UInt16 = 0
    var dstPort: UInt16 = 0
    
    init(data: Data) {
        var sPort: UInt16 = 0
        var dPort: UInt16 = 0
        var payloadData: Data!
        
        data.withUnsafeRawPointer { pointer in
            sPort = pointer.assumingMemoryBound(to: UInt16.self).pointee.bigEndian
            dPort = pointer.advanced(by: 2).assumingMemoryBound(to: UInt16.self).pointee.bigEndian
            var dataOffset = pointer.advanced(by: 12).assumingMemoryBound(to: UInt8.self).pointee >> 4
            dataOffset = dataOffset * 4
            
            payloadData = Data(bytes: pointer.advanced(by: Int(dataOffset)), count: data.count - Int(dataOffset))
        }
        
        self.sourcePort = sPort
        self.dstPort = dPort
        self.payload = payloadData
    }
}

class UDPPacket: ProtocolPacket {
    var payload: Data?
    var sourcePort: UInt16 = 0
    var dstPort: UInt16 = 0
    
    init(data: Data) {
        var sPort: UInt16 = 0
        var dPort: UInt16 = 0
        var payloadData: Data?
        
        data.withUnsafeRawPointer { pointer in
            sPort = pointer.assumingMemoryBound(to: UInt16.self).pointee.bigEndian
            dPort = pointer.advanced(by: 2).assumingMemoryBound(to: UInt16.self).pointee.bigEndian
            let payloadLen = pointer.advanced(by: 4).assumingMemoryBound(to: UInt16.self).pointee.bigEndian
            if payloadLen > 0 {
                payloadData = Data(bytes: pointer.advanced(by: 8), count: Int(payloadLen) - 8)
            } else {
                DDLogWarn("udp payload is nil")
            }
        }
        
        self.sourcePort = sPort
        self.dstPort = dPort
        self.payload = payloadData
    }
}

class IPPacket {
    enum IPVersion: UInt8 {
        case ipv4 = 4, ipv6 = 6
    }
    
    enum TransportProtocol: UInt8 {
        case icmp = 1, tcp = 6, udp = 17
    }
    
    var version: IPVersion
    var proto: TransportProtocol
    var sourceAddress: String
    var dstAddress: String

    var payload: Data
    var protocolPacket: ProtocolPacket?
    
    init?(data: Data) {
        var versionNum: UInt8 = 0
        var headerLength: UInt8 = 0
        var protoNum: UInt8 = 0
//        var payloadLen: UInt16 = 0
        
        var sourceIPNum: UInt32 = 0
        var dstIPNum: UInt32 = 0
        var payloadData: Data!
        
        if data.count < 20 {
            DDLogInfo("Invalid ip packet")
            return nil
        }
        
        data.withUnsafeRawPointer { pointer in
            let num = pointer.assumingMemoryBound(to: UInt8.self).pointee
            versionNum = num >> 4 & 0x0f
            headerLength = num & 0x0f * 4
            if headerLength % 4 > 0 {
                DDLogError("IP packet header length % 4 != 0")
            }
            protoNum = pointer.advanced(by: 9).assumingMemoryBound(to: UInt8.self).pointee
//            payloadLen = pointer.advanced(by: 2).assumingMemoryBound(to: UInt16.self).pointee.bigEndian - UInt16(headerLength)
            payloadData = data.advanced(by: Int(headerLength))
            
            sourceIPNum = pointer.advanced(by: 12).assumingMemoryBound(to: UInt32.self).pointee.bigEndian
            dstIPNum = pointer.advanced(by: 16).assumingMemoryBound(to: UInt32.self).pointee.bigEndian
        }

        guard let version = IPVersion(rawValue: versionNum) else {
            DDLogError("Invalid packet version")
            return nil
        }
        self.version = version
        
        guard let proto = TransportProtocol(rawValue: protoNum) else {
            DDLogError("Invalid packet protocol")
            return nil
        }
        self.proto = proto
        
        self.sourceAddress = toIPV4(sourceIPNum)
        self.dstAddress = toIPV4(dstIPNum)
        self.payload = payloadData
        
        if proto == .tcp {
            self.protocolPacket = TCPPacket(data: payload)
        } else if proto == .udp {
            self.protocolPacket = UDPPacket(data: payload)
        }
    }
}
