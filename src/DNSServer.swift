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
    
    private var servers: [String] = []
    private let fakeIP: String = "240.0.0.34"
    private var whiteList = [String]()
//    private let syncQueue = DispatchQueue(label: "sync")

    public func start(on port: UInt16, servers: [String] = ["114.114.114.114"]) {
        self.servers = servers
        lowadWhiteList()
        
        let queue = DispatchQueue(label: "dns")
        listenSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: queue)
        do {
            try listenSocket.bind(toPort: port)
            try listenSocket.beginReceiving()
            DDLogInfo("start dns server on \(port)")
        } catch let e {
            DDLogError(e.localizedDescription)
        }
    }
    
    public func stop() {
        listenSocket.close()
    }
    
    private func lowadWhiteList() {
        guard let path = Bundle(for: DNSServer.self).path(forResource: "gfwlist", ofType: "data") else { DDLogError("load gfwlist.data failed"); return}
        
        do {
            let content = try String(contentsOfFile: path)
            let lines = content.components(separatedBy: CharacterSet.newlines)
            whiteList = lines.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\t"))}.filter { $0.count > 0 }
            DDLogInfo("[dns] white list count: \(whiteList.count)")
        } catch let e {
            DDLogError(e.localizedDescription)
        }
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
    
    func isInWhiteList(domain: String) -> Bool {
        return whiteList.contains(where: { domain.hasSuffix($0) || $0 == ".\(domain)"})
    }
    
    func isChinaDomain(domain: String) -> Bool {
        return domain.hasSuffix(".cn")
    }
}

extension DNSServer: GCDAsyncUdpSocketDelegate {
    public func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        do {
            let response = try Message.init(deserialize: data)
            if response.type == .query { // request
                
                guard let domain = response.questions.first?.name.trimmingCharacters(in: CharacterSet(charactersIn: ".")) else { return }

                var result: String?
                
                if self.cache[domain] != nil {
                    result = self.cache[domain]
                } else if !isChinaDomain(domain: domain) && isInWhiteList(domain: domain) && !domain.contains("apple.com") {
                    result = fakeIP
                }

                if result != nil {
                    let answer = HostRecord(name: domain, ttl: 32, ip: IPv4(result!)!)
                    let message = Message(id: response.id, type: .response, operationCode: .query, authoritativeAnswer: true, truncation: false, recursionDesired: response.recursionDesired, recursionAvailable: true, returnCode: .noError, questions: response.questions, answers: [answer], authorities: [], additional: [])
                    let payload = try message.serialize()
                    listenSocket.send(payload, toAddress: address, withTimeout: -1, tag: 0)
                    DDLogInfo("dns: \(domain)")
                } else {
                    requestMap[response.id] = address
                    servers.forEach { listenSocket.send(data, toHost: $0, port: 53, withTimeout: -1, tag: 0)}
                }
            } else { // response
                // TODO: should have code lock
                if let ip = realIP(from: response) {
                    if let domain = response.questions.first?.name.trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
                        cache[domain] = ip
                    }
                }

                if let address = requestMap[response.id] {
                    listenSocket.send(data, toAddress: address, withTimeout: -1, tag: 0)
                    requestMap[response.id] = nil
                }
            }
        } catch let e {
            DDLogError(e.localizedDescription)
        }
    }
}

func realIP(from message: Message) -> String? {
    guard message.type == .response else { return nil }
    guard message.answers.count > 0 else { return nil }
    
    var recordName = ""
    
    // TODO: Other type
    for answer in message.answers {
        if type(of: answer) == HostRecord<IPv4>.self {
            if recordName == "" || recordName == answer.name {
                return (answer as! HostRecord<IPv4>).ip.presentation
            }
        } else if type(of: answer) == AliasRecord.self {
            recordName = (answer as! AliasRecord).canonicalName
        }
    }
    return nil
}
