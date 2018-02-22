//
//  KingSocksSession.swift
//  KingProxy
//
//  Created by Purkylin King on 2018/2/1.
//  Copyright © 2018年 Purkylin King. All rights reserved.
//

import Foundation
import CocoaAsyncSocket
import CocoaLumberjackSwift

// https://www.ietf.org/rfc/rfc1928.txt

internal protocol SocksSessionDelegate: class {
    func sessionDidDisconnect(session: SocksSession)
}

public class SocksSession: NSObject {
    
    enum AuthMethod: UInt8 {
        case none
        case gssapi
        case usernamePassword
        case unSupported
    }
    
    enum SocksState: UInt8 {
        case ready
        case readRequest
        case readConnect
        case readyProxy // ready for proxy
        case forward
    }
    
    enum SocksAddressType: UInt8 {
        case ipv4 = 1
        case domain = 3
        case ipv6 = 4
    }
    
    enum ReadTag: Int {
        case readVersion = 1000
        case readMethods
        case readConnect
        case readIpv4
        case readIpv6
        case readDomainLength
        case readDomain
        case readPort
        case readIncoming
        case readOutgoing
        case readAuthUserLen
        case readAuthUsername
        case readAuthPwdLen
        case readAuthPassword
        
        case readProxyVersion
        case readProxyConnect
        
        case readForwardVersion
    }
    
    enum WriteTag: Int {
        case writeVersion
        case readMethods
        case forwardHeader
        case others
    }
    
    private let connectTimeout: TimeInterval = 4
    private let writeTimeout: TimeInterval = 5
    private var forwardProxy: ForwardProxy?
    private var useProxy = false
    private var state: SocksState
    private var destinationHost: String = ""
    private var destinationPort: UInt16 = 80
    
    private var proxySocket: GCDAsyncSocket
    private var outgoingSocket: GCDAsyncSocket!
    
    private var connectData = Data()
    
    internal weak var delegate: SocksSessionDelegate?
    
    // Note Not support auth for simplize
    init(socket: GCDAsyncSocket, proxy: ForwardProxy?) {
        self.proxySocket = socket
        self.forwardProxy = proxy
        self.state = .ready
        super.init()
        
        if let proxy = forwardProxy {
            switch proxy.type {
            case .http:
                DDLogError("Not support forward to http proxy")
            case .socks5:
                useProxy = true
            case .shadowsocks:
                DDLogError("Not support forward to shadowsocks proxy")
                break
            }
        }
        
        let queue = DispatchQueue(label: "com.purkylin.kingproxy.socks.session.outgoing")
        outgoingSocket = GCDAsyncSocket(delegate: self, delegateQueue: queue)
        
        proxySocket.delegate = self
        outgoingSocket.delegate = self
        
        self.state = .readRequest
        proxySocket.readData(toLength: 2, withTimeout: -1, tag: ReadTag.readVersion.rawValue)
    }
    
    deinit {
        proxySocket.disconnectAfterWriting()
        outgoingSocket.disconnectAfterReading()
    }
}

extension SocksSession: GCDAsyncSocketDelegate {
    // MARK: Delegate
    
    public func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        guard let readTag = ReadTag(rawValue: tag) else { DDLogWarn("Unknowd read tag"); return }
        
        switch readTag {
        case .readVersion:
            data.withUnsafeBytes({ (pointer: UnsafePointer<UInt8>) in
                let version = pointer.pointee
                guard version == 5 else {
                    DDLogWarn("Unsupport socks version: \(version)")
                    proxySocket.write(Data(bytes: [0x00, 0xff]), withTimeout: -1, tag: 0)
                    proxySocket.disconnectAfterWriting()
                    return
                }
                let methodCnt = pointer.advanced(by: 1).pointee
                proxySocket.readData(toLength: UInt(methodCnt), withTimeout: -1, tag: ReadTag.readMethods.rawValue)
            })
        case .readMethods:
            let methods = [UInt8](data)
            guard methods[0] == 0 else {
                DDLogError("Doesn't support auth socks proxy")
                proxySocket.write(Data(bytes: [0x05, 0xff]), withTimeout: -1, tag: 0)
                proxySocket.disconnectAfterWriting()
                return
            }
            
            state = .readConnect
            proxySocket.write(Data(bytes: [0x05, 0x00]), withTimeout: -1, tag: 0)
            proxySocket.readData(toLength: 4, withTimeout: -1, tag: ReadTag.readConnect.rawValue)
        case .readConnect:
            data.withUnsafeBytes({ (pointer: UnsafePointer<UInt8>)  in
                guard let addressType = SocksAddressType(rawValue: pointer.advanced(by: 3).pointee) else { return }
                
                let cmd = pointer.advanced(by: 1).pointee
                if cmd != 1 {
                    DDLogError("Error: unsupport cmd: \(cmd)")
                    proxySocket.disconnect()
                    return
                }
                
                if addressType == .ipv4 {
                    proxySocket.readData(toLength: 4, withTimeout: -1, tag: ReadTag.readIpv4.rawValue)
                } else if addressType == .ipv6 {
                    proxySocket.readData(toLength: 16, withTimeout: -1, tag: ReadTag.readIpv6.rawValue)
                } else if addressType == .domain {
                    proxySocket.readData(toLength: 1, withTimeout: -1, tag: ReadTag.readDomainLength.rawValue)
                }
            })
            connectData.append(data)
        case .readIpv4:
            var address = Data(count: Int(INET_ADDRSTRLEN))
            _ = data.withUnsafeBytes({ (ptr:UnsafePointer<Int8>) in
                address.withUnsafeMutableBytes({ (addr_ptr) in
                    inet_ntop(AF_INET, UnsafeRawPointer(ptr), addr_ptr, socklen_t(INET_ADDRSTRLEN))
                })
            })
            
            destinationHost = String(data: address, encoding: .utf8)!.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            proxySocket.readData(toLength: 2, withTimeout: -1, tag: ReadTag.readPort.rawValue)
            connectData.append(data)
        case .readIpv6:
            var address = Data(count: Int(INET6_ADDRSTRLEN))
            _ = data.withUnsafeBytes({ (ptr:UnsafePointer<Int8>) in
                address.withUnsafeMutableBytes({ (addr_ptr) in
                    inet_ntop(AF_INET6, UnsafeRawPointer(ptr), addr_ptr, socklen_t(INET6_ADDRSTRLEN))
                })
            })
            destinationHost = String(data: address, encoding: .utf8)!
            proxySocket.readData(toLength: 2, withTimeout: -1, tag: ReadTag.readPort.rawValue)
            connectData.append(data)
        case .readDomainLength:
            data.withUnsafeBytes({ (pointer: UnsafePointer<UInt8>) in
                let size = pointer.pointee
                if size == 0 {
                    DDLogError("Invalid domain")
                    proxySocket.disconnect()
                    return
                }
                proxySocket.readData(toLength: UInt(size), withTimeout: -1, tag: ReadTag.readDomain.rawValue)
            })
            connectData.append(data)
        case .readDomain:
            destinationHost = String(data: data, encoding: .utf8)!
            proxySocket.readData(toLength: 2, withTimeout: -1, tag: ReadTag.readPort.rawValue)
            DDLogInfo("Read domain: \(destinationHost)")
            connectData.append(data)
        case .readPort:
            data.withUnsafeBytes({ (pointer: UnsafePointer<UInt16>) in
                destinationPort = NSSwapHostShortToBig(pointer.pointee)
            })
            DDLogInfo("Connect remote \(destinationHost):\(destinationPort)")
            connectData.append(data)
            
            if ACL.shared!.useProxy(host: destinationHost) { // use rule
                DDLogInfo("use proxy: \(destinationHost)")
                state = .readyProxy
                try! outgoingSocket.connect(toHost: forwardProxy!.host, onPort: forwardProxy!.port)
            } else {
                DDLogInfo("direct: \(destinationHost)")
                state = .forward
                try! outgoingSocket.connect(toHost: destinationHost, onPort: destinationPort)
            }
            
        case .readProxyVersion:
            data.withUnsafeBytes({ (pointer: UnsafePointer<UInt8>) in
                let version = pointer.pointee
                let method = pointer.advanced(by: 1).pointee
                guard version == 5, method == 0 else {
                    DDLogWarn("Unsupport socks proxy")
                    proxySocket.disconnectAfterWriting()
                    outgoingSocket.disconnect()
                    return
                }
                
                // TODO opticalize
                outgoingSocket.write(connectData, withTimeout: -1, tag: 0)
                outgoingSocket.readData(toLength: 10, withTimeout: -1, tag: ReadTag.readProxyConnect.rawValue)
            })
        case .readProxyConnect:
            // TODO Deal with
            state = .forward
            proxySocket.readData(withTimeout: -1, tag: ReadTag.readIncoming.rawValue)
        case .readIncoming:
            self.outgoingSocket.write(data, withTimeout: -1, tag: 0)
            self.outgoingSocket.readData(withTimeout: -1, tag: ReadTag.readOutgoing.rawValue)
            self.proxySocket.readData(withTimeout: -1, tag: ReadTag.readIncoming.rawValue)
        case .readOutgoing:
            self.proxySocket.write(data, withTimeout: -1, tag: 0)
            self.outgoingSocket.readData(withTimeout: -1, tag: ReadTag.readOutgoing.rawValue)
            self.proxySocket.readData(withTimeout: -1, tag: ReadTag.readIncoming.rawValue)
        default:
            break
        }
    }
    
    public func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        /*
         +----+-----+-------+------+----------+----------+
         |VER | REP |  RSV  | ATYP | BND.ADDR | BND.PORT |
         +----+-----+-------+------+----------+----------+
         | 1  |  1  | X'00' |  1   | Variable |    2     |
         +----+-----+-------+------+----------+----------+
         */
        var data = Data()
        #if TUN2SOCK_PROXY
            data.append(contentsOf: [0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        #else
            data.append(contentsOf: [0x05, 0x00, 0x00, 0x03, UInt8(host.count)])
            data.append(host.data(using: .utf8)!) // host
            
            var mPort: UInt16 = port.bigEndian
            let portData = Data(bytes: &mPort,
                                count: MemoryLayout.size(ofValue: port))
            data.append(portData)
        #endif

        if state == .readyProxy {
            proxySocket.write(data, withTimeout: -1, tag: 0)
            
            outgoingSocket.write(Data(bytes: [0x05, 0x01, 0x00]), withTimeout: -1, tag: 0)
            outgoingSocket.readData(toLength: 2, withTimeout: -1, tag: ReadTag.readProxyVersion.rawValue)
            return
        } else {
            proxySocket.write(data, withTimeout: -1, tag: 0)
            proxySocket.readData(withTimeout: -1, tag: ReadTag.readIncoming.rawValue)
        }
    }
    
    public func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        if let error = err {
            if error.code != 7 || error.domain != "GCDAsyncSocketErrorDomain" {
                if error.code == 3 {
                    DDLogInfo("[http disconnect] Connection timeout")
                } else {
                    // DDLogInfo("[http disconnect] \(error.localizedDescription)")
                }
            }
        }
        
        if sock === proxySocket {
            outgoingSocket.delegate = nil
            outgoingSocket.disconnect()
            
            DispatchQueue.main.async {
                self.delegate?.sessionDidDisconnect(session: self)
            }
        } else {
            proxySocket.disconnectAfterWriting()
        }
    }
}
