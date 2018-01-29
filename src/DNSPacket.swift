//
//  DNSPacket.swift
//  PacketTunnel
//
//  Created by Purkylin King on 2017/12/18.
//  Copyright © 2017年 Purkylin King. All rights reserved.
//

import UIKit
import CocoaLumberjackSwift

class DNSPacket {
    var identifier: UInt16 = 0
    var flags: UInt16 = 0
    var count: UInt16 = 0 // 问题数
    var raw: Data
    var queryDomains = [String]()
    
    var anCount: UInt16 = 0 // 资源记录数
    var nsCount: UInt16 = 0 // 授权资源记录数
    var arCount: UInt16 = 0 // 额外资源记录数
    var results = [String]()
    
    var errCode: UInt8 = 0 // response error code
    
    var responseOffset = 12
    
    var isResponse: Bool {
        return (flags >> 15) == 1
    }
    
    init(data: Data) {
        self.raw = data
        
        data.withUnsafeRawPointer { pointer  in
            identifier = pointer.assumingMemoryBound(to: UInt16.self).pointee.bigEndian
            flags = pointer.advanced(by: 2).assumingMemoryBound(to: UInt16.self).pointee.bigEndian
            count = pointer.advanced(by: 4).assumingMemoryBound(to: UInt16.self).pointee.bigEndian
            anCount = pointer.advanced(by: 6).assumingMemoryBound(to: UInt16.self).pointee.bigEndian
            nsCount = pointer.advanced(by: 8).assumingMemoryBound(to: UInt16.self).pointee.bigEndian
            arCount = pointer.advanced(by: 10).assumingMemoryBound(to: UInt16.self).pointee.bigEndian
            
            errCode = UInt8(flags & 0x000f)
        }
        
        parseQuestions()
        parseAnswers2()
    }
    
    func fakeResponse(ip: String) -> Data {
        var data = raw // copy
        data[2] = data[2] | 0x80 // response
        data[2] = data[2] & 0b11011111 // 非权威
        // data[3] = data[2] | 0x80 // 递归
        data[3] = data[3] & (~0x80) // 非递归
        data[7] = 1
        data[11] = 0 // clear addition count
        data.count = responseOffset
        data.append(contentsOf: [0xc0, 0x0c, 0x00, 0x01, 0x00, 0x01])
        data.append(contentsOf: [0x00, 0x00, 0x06, 0xee]) // live time
        data.append(contentsOf: [0x00, 0x04]) // length
        data.append(contentsOf: toData(host: ip))
        return data
    }
    
    func parseQuestions() {
        guard count > 0 else { return }
        
        raw.withUnsafeRawPointer { pointer in
            var p = pointer.advanced(by: 12)
            var offset = 0
            
            for _ in 0..<count {
                var segments = [String]()
                
                while true {
                    let len = p.assumingMemoryBound(to: UInt8.self).pointee
                    if len == 0 {
                        p = p.advanced(by: 1)
                        offset += 1
                        break
                    }
                    
                    let data = Data(bytes: p.advanced(by: 1), count: Int(len))
                    segments.append(String(data: data, encoding: .utf8)!)
                    
                    p = p.advanced(by: Int(len) + 1)
                    offset += Int(len) + 1
                    
                    if len > 63 {
                        DDLogError("Invalid dns header")
                        break
                    }
                }
                queryDomains.append(segments.joined(separator: "."))
                p = p.advanced(by: 4)
                offset += 4
            }
            
            responseOffset += offset
        }
    }
    
    func toHost(address: Data) -> String? {
        guard address.count == 4 else { return nil }
        return address.map { "\($0)" }.joined(separator: ".")
    }
    
    func toData(host: String) -> Data {
        let arr = host.components(separatedBy: ".").map { UInt8($0)! }
        return Data(bytes: arr)
    }
    
    func parseAnswers() {
        guard isResponse else { return }
        
        if errCode > 0 {
            DDLogVerbose("[dns] response error: \(errCode)")
            return
        }
        
        guard anCount > 0 else { return }
        
        raw.withUnsafeRawPointer { pointer in
            var p = pointer.advanced(by: responseOffset)
            for _ in 0..<anCount {
                let mask = p.assumingMemoryBound(to: UInt32.self).pointee.bigEndian
                if 0xc00c == (mask >> 16) { // pointer
                    let data = Data(bytes: p.advanced(by: 12), count: 4)
                    let ip = toHost(address: data)!
                    results.append(ip)
                    DDLogInfo("[dns] \(ip)")
                } else {
                    DDLogWarn("Unsupport none pointer domain")
                }
                p = p.advanced(by: 16)
            }
        }
    }
    
    func parseAnswers2() {
        guard isResponse else { return }
        
        if errCode > 0 {
            DDLogVerbose("[dns] response error: \(errCode)")
            return
        }
        
        guard anCount > 0 else { return }
        
        raw.withUnsafeRawPointer { pointer in
            var p = pointer.advanced(by: responseOffset)
            for _ in 0..<anCount {
                let mask = p.assumingMemoryBound(to: UInt8.self).pointee
                var qtype: UInt16 = 0
                var qclass: UInt16 = 0
                
                var resultLen = 0
                var resultOffset = 0
                if mask == 0xc0  { // zip
                    let domainOffset = p.assumingMemoryBound(to: UInt16.self).pointee.bigEndian & 0x3fff
                    let (domainSegments, _) = readNames(pointer: pointer.advanced(by: Int(domainOffset)), source: pointer)
                    // DDLogInfo(domainSegments.joined(separator: "."))
                    qtype = p.advanced(by: 2).assumingMemoryBound(to: UInt16.self).pointee.bigEndian
                    qclass = p.advanced(by: 4).assumingMemoryBound(to: UInt16.self).pointee.bigEndian

                    let len = p.advanced(by: 10).assumingMemoryBound(to: UInt16.self).pointee.bigEndian
                    resultLen = Int(len)
                    resultOffset = 12
                } else {
                    let (segments, namesLen) = readNames(pointer: p, source: pointer)
                    // DDLogInfo(segments.joined(separator: "."))
                    
                    qtype = p.advanced(by: namesLen + 0).assumingMemoryBound(to: UInt16.self).pointee.bigEndian
                    qclass = p.advanced(by: namesLen + 2).assumingMemoryBound(to: UInt16.self).pointee.bigEndian
                    
                    let len = p.advanced(by: namesLen + 8).assumingMemoryBound(to: UInt16.self).pointee.bigEndian
                    resultLen = Int(len)
                    resultOffset = namesLen + 10
                }
                
                if qtype == 1 { // a record
                    if resultLen == 4 { // ipv4
                        let data = Data(bytes: p.advanced(by: 12), count: 4)
                        let ip = toHost(address: data)!
                        results.append(ip)
                        DDLogInfo("[dns] \(ip)")
                    } else if resultLen == 6 { // ipv6
                        DDLogInfo("[dns] ipv6")
                    }
                } else {
                    let (segments, offset) = readNames(pointer: p.advanced(by: resultOffset), source: pointer)
                    guard offset == resultLen else { return }
                    DDLogInfo(segments.joined(separator: "."))
                }
                p = p.advanced(by: resultOffset + resultLen)

            }
        }
    }
    
    func readNames(pointer: UnsafeRawPointer, source: UnsafeRawPointer) -> ([String], Int) {
        var p = pointer
        var segments = [String]()
        var offset = 0
        while true {
            let len = p.assumingMemoryBound(to: UInt8.self).pointee
            if len == 0 {
                p = p.advanced(by: 1)
                offset += 1
                break
            }
            
            if len > 63 { // pointer
                let dstOffset = p.assumingMemoryBound(to: UInt16.self).pointee.bigEndian & 0x3fff
                let dstPointer = source.advanced(by: Int(dstOffset))
                let (subSegments, _) = readNames(pointer: dstPointer, source: source)
                segments.append(contentsOf: subSegments)
                return (segments, offset + 2)
            }
            
            let data = Data(bytes: p.advanced(by: 1), count: Int(len))
            if let str = String(data: data, encoding: .utf8) {
                segments.append(str)
            } else {
                DDLogError("[dns] invalid string")
            }
            
            p = p.advanced(by: Int(len) + 1)
            offset += Int(len) + 1
        }
        
        return (segments, offset)
    }
    
    func parseNSAnswers() {
        guard nsCount > 0 else { return }
        
//        raw.withUnsafeRawPointer { pointer in
//            var p = pointer.advanced(by: responseOffset)
//            for _ in 0..<nsCount {
//                let mask = p.assumingMemoryBound(to: UInt32.self).pointee.bigEndian
//                if 0xc00c == (mask >> 16) { // pointer
//                    let data = Data(bytes: p.advanced(by: 12), count: 4)
//                    resultIP = toHost(address: data)
//                    DDLogInfo("[dns2] \(resultIP!)")
//                } else {
//                    DDLogWarn("Unsupport none pointer domain")
//                }
//                p = p.advanced(by: 16)
//            }
//        }
//
//        responseOffset += Int(nsCount) * 16
    }
}
