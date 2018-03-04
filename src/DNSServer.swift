//
//  DNSServer.swift
//  Demo for macOS
//
//  Created by Purkylin King on 2018/3/3.
//  Copyright © 2018年 Purkylin King. All rights reserved.
//

import Foundation
import CocoaAsyncSocket
import CocoaLumberjackSwift

public final class DNSServer: NSObject {
    public static var `default` = DNSServer()
    
    private var listenSocket: GCDAsyncUdpSocket!
    private var requestMap = [UInt16 : Data]() // (id, address)
    public var cache = [String : String]() // (domain ip)
    
    private let server: String = "114.114.114.114"
    private let foreignServer: String = "8.8.8.8"

    public func start(on port: UInt16) {
        let queue = DispatchQueue.global()
        listenSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: queue)
        do {
            try listenSocket.bind(toPort: port)
            try listenSocket.beginReceiving()
            DDLogInfo("start dns server on \(port)")
        } catch let e {
            print(e.localizedDescription)
        }
    }
    
    public func stop() {
        listenSocket.close()
    }
    
    // reverse find ip, return domain
    public func reverse(ip: String) -> String? {
        for (k, v) in cache {
            if v == ip {
                return k
            }
        }
        return nil
    }
}

extension DNSServer: GCDAsyncUdpSocketDelegate {
    public func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        do {
            let response = try Message.init(deserialize: data)
            if response.type == .query { // request
                guard let domain = response.questions.first?.name else { return }
                if let ip = cache[domain] {
                    let answer = HostRecord(name: domain, ttl: 32, ip: IPv4(ip)!)
                    let message = Message(id: response.id, type: .response, operationCode: .query, authoritativeAnswer: true, truncation: false, recursionDesired: response.recursionDesired, recursionAvailable: true, returnCode: .noError, questions: response.questions, answers: [answer], authorities: [], additional: [])
                    let payload = try message.serialize()
                    listenSocket.send(payload, toAddress: address, withTimeout: -1, tag: 0)
                } else {
                    requestMap[response.id] = address
                    let requestServer = ACL.shared!.useForeignDNS(domain: domain) ? foreignServer : server
                    listenSocket.send(data, toHost: requestServer, port: 53, withTimeout: -1, tag: 100)
                }
            } else { // response
                if let record = response.answers.first as? HostRecord<IPv4> {
                    let host = record.ip.presentation
                    if let domain = response.questions.first?.name {
                        cache[domain] = host
                    }
                }

                if let address = requestMap[response.id] {
                    listenSocket.send(data, toAddress: address, withTimeout: -1, tag: 0)
                }
            }
        } catch let e {
            DDLogError(e.localizedDescription)
        }
    }
}
