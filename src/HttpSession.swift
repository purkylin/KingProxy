//
//  HttpSession.swift
//  Sock5Server
//
//  Created by Purkylin King on 2017/12/14.
//  Copyright © 2017年 Purkylin King. All rights reserved.
//

import Foundation
import CocoaAsyncSocket
import CocoaLumberjackSwift

extension Error {
    var code: Int { return (self as NSError).code }
    var domain: String { return (self as NSError).domain }
}

internal protocol HttpSessionDelegate: class {
    func sessionDidDisconnect(session: HttpSession)
}

public class HttpSession: NSObject {
    
    private enum Status {
        case initial
        case readyForward
        case forwarding
        case disconnect
    }
    
    private enum Tag: Int {
        case initial = 100, readRequest, readResponse, writeRequest, writeResponse
        case readSocksProtocol, readSocksConnect
    }
    
    private let connectTimeout: TimeInterval = 15
    private let writeTimeout: TimeInterval = 8
    private let readTimeout: TimeInterval = 8

    private var forwardProxy: ForwardProxy?
    
    private var proxySocket: GCDAsyncSocket
    private var forwardSocket: GCDAsyncSocket!
    
    private let termData = "\r\n\r\n".data(using: .utf8)!
    private let successData = "HTTP/1.1 200 Connection Established\r\n\r\n".data(using: String.Encoding.utf8)!
    
    private var status: Status = .initial
    private var isSecure = false
    private var hasProxy = false
    
    private var receviedData: Data?
    private var header: HttpHeader!
    
    var time: CFTimeInterval = CFAbsoluteTimeGetCurrent()
    
    internal weak var delegate: HttpSessionDelegate?
    
    init(socket: GCDAsyncSocket, proxy: ForwardProxy?) {
        forwardProxy = proxy
        proxySocket = socket
        
        super.init()
        
        if let proxy = forwardProxy {
            switch proxy.type {
            case .http:
                hasProxy = true
            case .socks5:
                hasProxy = true
            case .shadowsocks:
                DDLogError("Not support forward to shadowsocks proxy")
                break
            }
        }
        
        proxySocket.delegate = self
        let queue = DispatchQueue.global()
//        let queue = DispatchQueue(label: "com.purkylin.kingproxy.httpsession.sock")
        forwardSocket = GCDAsyncSocket(delegate: self, delegateQueue: queue)
        proxySocket.readData(to: termData, withTimeout: readTimeout, tag: Tag.initial.rawValue)
    }
    
    func useProxy(rule: String) -> Bool {
        let result = ACL.shared!.useProxy(host: rule)
        DDLogVerbose("[acl] \(rule) use proxy:\(result)")
        return result
    }
}

extension HttpSession: GCDAsyncSocketDelegate {
    public func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        guard let tag = Tag(rawValue: tag) else { return }
        
        switch tag {
        case .initial:
            do {
                header = try HttpHeader(data: data)
                receviedData = header.data
            } catch let e {
                DDLogError(e.localizedDescription)
                DDLogError("[http] Invalid http header")
                sock.disconnect()
                return
            }

            if header.isConnect { // https
                isSecure = true
                if self.forwardProxy != nil && useProxy(rule: header.host) {
                    guard let proxy = self.forwardProxy else { return }
                    do {
                        DDLogInfo("[connect] \(proxy.host):\(proxy.port)")
                        try forwardSocket.connect(toHost: proxy.host, onPort: proxy.port, withTimeout: connectTimeout)
                    } catch let e {
                        DDLogError("[http] Connect to host failed: \(e.localizedDescription)")
                    }
                } else {
                    hasProxy = false
                    do {
                        DDLogInfo("[connect] \(header.host):\(header.port)")
                        try forwardSocket.connect(toHost: header.host, onPort: header.port, withTimeout: connectTimeout)
                    } catch let e {
                        DDLogError("[http] Connect to host failed: \(e.localizedDescription)")
                    }
                }
            } else { // http
                isSecure = false
                if self.forwardProxy != nil && useProxy(rule: header.host) {
                    guard let proxy = self.forwardProxy else { return }
                    do {
                        DDLogInfo("[connect] \(proxy.host):\(proxy.port)")
                        try forwardSocket.connect(toHost: proxy.host, onPort: proxy.port, withTimeout: connectTimeout)
                    } catch let e {
                        DDLogError("[http] Connect to host failed: \(e.localizedDescription)")
                    }
                } else {
                    hasProxy = false
                    do {
                        DDLogInfo("[connect] \(header.host):\(header.port)")
                        try forwardSocket.connect(toHost: header.host, onPort: header.port, withTimeout: connectTimeout)
                    } catch let e {
                        DDLogError("[http] Connect to host failed: \(e.localizedDescription)")
                    }
                }
            }
        case .readRequest:
            forwardSocket.write(data, withTimeout: writeTimeout, tag: Tag.writeRequest.rawValue)
            proxySocket.readData(withTimeout: -1, tag: Tag.readRequest.rawValue)
        case .readResponse:
            proxySocket.write(data, withTimeout: writeTimeout, tag: Tag.writeResponse.rawValue)
            forwardSocket.readData(withTimeout: -1, tag: Tag.readResponse.rawValue)
        case .readSocksProtocol:
            let byteArr = [UInt8](data)
            if byteArr[0] != 5 {
                proxySocket.disconnect()
                DDLogError("[http] Invalid version")
                return
            }
            
            if byteArr[1] != 0 {
                proxySocket.disconnect()
                DDLogError("[http] Invalid auth method")
                return
            }
            
            let domainLength = UInt8(header.host.count)
            var sendData = Data(bytes: [0x05, 0x01, 0x00, 0x03, domainLength])
            sendData.append(header.host.data(using: .utf8)!)
            var port: UInt16 = header.port.bigEndian
            let portData = Data(bytes: &port,
                                count: MemoryLayout.size(ofValue: port))
            
            sendData.append(portData)
            forwardSocket.write(sendData, withTimeout: writeTimeout, tag: 0)
            forwardSocket.readData(withTimeout: readTimeout, tag: Tag.readSocksConnect.rawValue)
        case .readSocksConnect:
            let byteArr = [UInt8](data)
            if byteArr[0] != 5 {
                DDLogError("Invalid version")
                proxySocket.disconnect()
                return
            }
            
            if byteArr[1] != 0 {
                DDLogError("Connect failed")
                proxySocket.disconnect()
                return
            }
            status = .forwarding
            
            if isSecure {
                proxySocket.write(successData, withTimeout: writeTimeout, tag: 0)
            } else {
                forwardSocket.write(receviedData!, withTimeout: writeTimeout, tag: 0)
            }
            proxySocket.readData(withTimeout: readTimeout, tag: Tag.readRequest.rawValue)
            forwardSocket.readData(withTimeout: readTimeout, tag: Tag.readResponse.rawValue)
        default:
            DDLogError("[http] Invalid http tag")
            break
        }
    }
    
    public func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
        // Do nothing
    }
    
    public func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        if let proxy = self.forwardProxy, hasProxy {
            if proxy.type == .http {
                status = .forwarding
                DDLogInfo("[http] forward http to http proxy")
                forwardSocket.write(receviedData!, withTimeout: writeTimeout, tag: Tag.writeRequest.rawValue)
                proxySocket.readData(withTimeout: -1, tag: Tag.readRequest.rawValue)
                forwardSocket.readData(withTimeout: -1, tag: Tag.readResponse.rawValue)
            } else { // socks5
                DDLogInfo("[http] forward http\(isSecure ? "s" : "") to socks5 proxy")
                forwardSocket.write(Data(bytes: [0x05, 0x01, 0x00]), withTimeout: writeTimeout, tag: 0)
                forwardSocket.readData(toLength: 2, withTimeout: -1, tag: Tag.readSocksProtocol.rawValue)
            }
        } else {
            DDLogInfo("[http] forward https(s) no proxy")
            if (isSecure) {
                proxySocket.write(successData, withTimeout: writeTimeout, tag: 0)
            } else {
                
                forwardSocket.write(header.data, withTimeout: writeTimeout, tag: 0)
            }
            
            status = .forwarding
            proxySocket.readData(withTimeout: -1, tag: Tag.readRequest.rawValue)
            forwardSocket.readData(withTimeout: -1, tag: Tag.readResponse.rawValue)
        }
    }
    
    public func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        if let error = err {
            if error.code != 7 || error.domain != "GCDAsyncSocketErrorDomain" {
                if error.code == 3 {
                    DDLogInfo("[http disconnect] Connection timeout")
                }
            }
        }
        
        if sock === proxySocket {
            forwardSocket.delegate = nil
            forwardSocket.disconnect()
            self.delegate?.sessionDidDisconnect(session: self)
        } else {
            proxySocket.disconnectAfterWriting()
        }
    }
}
