//
//  KingSocksProxy.swift
//  KingProxy
//
//  Created by Purkylin King on 2018/2/1.
//  Copyright © 2018年 Purkylin King. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift
import CocoaAsyncSocket

public class KingSocksProxy: NSObject {
    /// Set forward proxy
    public var forwardProxy: ForwardProxy?
    
    private var address: String
    private var port: UInt16
    
    private var sessions = Set<SocksSession>()
    private var listenSocket: GCDAsyncSocket!
    
    /// Init server with listen host and port
    public init(address: String, port: UInt16) {
        self.address = address
        self.port = port
        super.init()
        
        let queue = DispatchQueue(label: "com.purkylin.kingproxy.socks")
        let socketQueue = DispatchQueue(label: "com.purkylin.kingproxy.socks.socket", qos: .background, attributes: [.concurrent], autoreleaseFrequency: .inherit, target: nil)
        listenSocket = GCDAsyncSocket(delegate: self, delegateQueue: queue, socketQueue: socketQueue)
    }
    
    /// Start proxy server
    public func start() {
        do {
            #if os(macOS)
                try listenSocket.accept(onPort: port)
            #else
                try listenSocket.accept(onInterface: address, port: port)
            #endif
            DDLogInfo("[http] Start socks proxy on port:\(port) ok")
        } catch let e {
            DDLogError("[http] Start socks proxy failed: \(e.localizedDescription)")
        }
    }
    
    /// Stop proxy server
    public func stop() {
        listenSocket.disconnectAfterWriting()
        DDLogInfo("[http] Stop http proxy server")
    }
}

extension KingSocksProxy: GCDAsyncSocketDelegate, SocksSessionDelegate {
    public func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        let session = SocksSession(socket: newSocket, proxy: forwardProxy)
        sessions.insert(session)
        session.delegate = self
        DDLogInfo("[socks] New session, count:\(sessions.count)")
    }
    
    func sessionDidDisconnect(session: SocksSession) {
        if sessions.contains(session) {
            sessions.remove(session)
        }
        DDLogInfo("[socks] Disconnect session, count:\(sessions.count)")
    }
}


