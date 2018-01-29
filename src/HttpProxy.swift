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

//public enum ProxyType {
//    case http, socks5
//}

public struct ForwardProxy {
    let type: ProxyType
    let port: UInt16
    let host: String
}

public class HttpProxy: NSObject {
    public var forwardProxy: ForwardProxy?
    
    private var address: String
    private var port: UInt16
    
    private var sessions = Set<HttpSession>()
    
    init(address: String, port: UInt16) {
        self.address = address
        self.port = port
        super.init()
        
        let queue = DispatchQueue(label: "com.purkylin.http")
        let sockQueue = DispatchQueue(label: "com.purkylin.http.sock1", qos: .background, attributes: [.concurrent], autoreleaseFrequency: .inherit, target: nil)
        listenSocket = GCDAsyncSocket(delegate: self, delegateQueue: queue, socketQueue: sockQueue)
    }
    
    private var listenSocket: GCDAsyncSocket!
    
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
    
    public func stop() {
        listenSocket.disconnectAfterWriting()
        DDLogInfo("[http] Stop http proxy server")
    }
}

extension HttpProxy: GCDAsyncSocketDelegate, HttpSessionDelegate {
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

