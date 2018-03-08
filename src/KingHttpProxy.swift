//
//  HttpServer.swift
//  Sock5Server
//
//  Created by Purkylin King on 2017/12/13.
//  Copyright © 2017年 Purkylin King. All rights reserved.
//

import Foundation
import CocoaAsyncSocket
import CocoaLumberjackSwift

public enum ProxyType: String {
    case http = "Http"
    case socks5 = "Socks5"
    case shadowsocks = "Shadowsocks"
}

public struct ForwardProxy {
    public let type: ProxyType
    public let host: String
    public let port: UInt16
    
    public init(type: ProxyType, host: String, port: UInt16) {
        self.type = type
        self.host = host
        self.port = port
    }
}

public class KingHttpProxy: NSObject {
    /// Set forward proxy
    public var forwardProxy: ForwardProxy?
    public var isRunning = false
    
    private var address: String = "127.0.0.1"
    private var port: UInt16 = 0
    
    private var sessions = Set<HttpSession>()
    private var listenSocket: GCDAsyncSocket!
    
    private var syncQueue = DispatchQueue(label: "com.purkylin.kingproxy.sync.http")
    
    public override init() {
        super.init()
        let queue = DispatchQueue(label: "com.purkylin.kingproxy.http", qos: .default, attributes: .concurrent)
        listenSocket = GCDAsyncSocket(delegate: self, delegateQueue: queue)
    }
    
    /// Init server with listen host and port
    public convenience init(address: String) {
        self.init(address: address)
        self.address = address
    }
    
    /// Start server, return lister port if succes else return 0
    public func start(on port: UInt16) -> UInt16 {
        do {
            if isRunning {
                DDLogError("[http] Error: Server is running")
                return 0
            }
            
#if os(macOS)
        try listenSocket.accept(onPort: port)
#else
        try listenSocket.accept(onInterface: address, port: port)
#endif
            isRunning = true
            self.port = listenSocket.localPort
            DDLogInfo("[http] Start http proxy on port:\(port) ok")
            return self.port
        } catch let e {
            DDLogError("[http] Start http proxy failed: \(e.localizedDescription)")
            self.port = 0
            return self.port
        }
    }
    
    public func start() -> UInt16{
        return start(on: 0)
    }
    
    /// Stop proxy server
    public func stop() {
        listenSocket.disconnectAfterWriting()
        DDLogInfo("[http] Stop http proxy server")
    }
}

extension KingHttpProxy: GCDAsyncSocketDelegate, HttpSessionDelegate {
    public func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        syncQueue.async {
            let session = HttpSession(socket: newSocket, proxy: self.forwardProxy)
            self.sessions.insert(session)
            session.delegate = self
            DDLogInfo("[http] New session, count:\(self.sessions.count)")
        }
    }
    
    public func sessionDidDisconnect(session: HttpSession) {
        session.delegate = nil
        
        syncQueue.async {
            if self.sessions.contains(session) {
                self.sessions.remove(session)
                let interval = (CFAbsoluteTimeGetCurrent() - session.time) / 1000.0
                DDLogInfo("[http] Disconnect session count:\(self.sessions.count), live:\(interval) host:")
            }
        }
    }
}

