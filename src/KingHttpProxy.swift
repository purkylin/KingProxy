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
    
    private var address: String
    private var port: UInt16
    
    private var sessions = Set<HttpSession>()
    private var listenSocket: GCDAsyncSocket!
    
    /// Init server with listen host and port
    public init(address: String, port: UInt16) {
        self.address = address
        self.port = port
        super.init()
        
        let queue = DispatchQueue(label: "com.purkylin.http")
        let sockQueue = DispatchQueue(label: "com.purkylin.http.sock", qos: .background, attributes: [.concurrent], autoreleaseFrequency: .inherit, target: nil)
        listenSocket = GCDAsyncSocket(delegate: self, delegateQueue: queue, socketQueue: sockQueue)
    }
    
    
    /// Start proxy server
    public func start() {
        do {
#if os(macOS)
        try listenSocket.accept(onPort: port)
#else
        try listenSocket.accept(onInterface: address, port: port)
#endif
            DDLogInfo("[http] Start http proxy on port:\(port) ok")
        } catch let e {
            DDLogError("[http] Start http proxy failed: \(e.localizedDescription)")
        }
    }
    
    /// Stop proxy server
    public func stop() {
        listenSocket.disconnectAfterWriting()
        DDLogInfo("[http] Stop http proxy server")
    }
}

extension KingHttpProxy: GCDAsyncSocketDelegate, HttpSessionDelegate {
    public func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        let session = HttpSession(socket: newSocket, proxy: forwardProxy)
        sessions.insert(session)
        session.delegate = self
        DDLogInfo("[http] New session, count:\(sessions.count)")
    }
    
    public func sessionDidDisconnect(session: HttpSession) {
        if sessions.contains(session) {
            sessions.remove(session)
        }
        DDLogInfo("[http] Disconnect session, count:\(sessions.count)")
    }
}

