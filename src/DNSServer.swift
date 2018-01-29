//
//  DNSServer.swift
//  PacketTunnel
//
//  Created by Purkylin King on 2017/12/18.
//  Copyright © 2017年 Purkylin King. All rights reserved.
//

import UIKit
import NetworkExtension
import CocoaLumberjackSwift
import CocoaAsyncSocket

class DNSServer: NSObject {
    private var listenSocket: GCDAsyncUdpSocket!
    private var chinaSession: NWUDPSession?
    private var foregnSession: NWUDPSession?
    
    private var queryDict = [UInt16 : Data]()
    public var cache = [String : String]() // (domain, ip)
    
    weak var provider: PacketTunnelProvider?
    
    private func useForeignDNS(domain: String) -> Bool {
        guard let acl = ACL.shared else { return true }
        
        for rule in acl.rules {
            if rule.type == .domain || rule.type == .domainKeyword || rule.type == .domainSuffix {
                if domain.contains(rule.value!) {
                    return rule.action == .proxy
                }
            }
        }
        
        return false
    }
    
    private func loadHosts() {
        // TODO Read file
        let hosts: [String : String] = [:]
        
        for (k, v) in hosts {
            cache[k] = v
        }
    }
    
    public func start(port: UInt16) {
        loadHosts()
        
        let queue = DispatchQueue(label: "dns")
        listenSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: queue)
        
        let chinaEndpoint = NWHostEndpoint(hostname: "114.114.114.114", port: "53")
        let foreignEndpoint = NWHostEndpoint(hostname: "8.8.8.8", port: "53")
        chinaSession = provider?.createUDPSession(to: chinaEndpoint, from: nil)
        foregnSession = provider?.createUDPSession(to: foreignEndpoint, from: nil)
        
        chinaSession?.setReadHandler({ (datas, error) in
            if let err = error {
                DDLogError("[dns] \(err.localizedDescription)")
                return
            }
            
            self.dealwithResponse(datas: datas)
        }, maxDatagrams: Int.max)
        
        foregnSession?.setReadHandler({ (datas, error) in
            if let err = error {
                DDLogError("[dns] \(err.localizedDescription)")
                return
            }
            
            self.dealwithResponse(datas: datas)
        }, maxDatagrams: Int.max)
        
        
        foregnSession?.addObserver(self, forKeyPath: "state", options: [.initial, .new], context: nil)
        chinaSession?.addObserver(self, forKeyPath: "state", options: [.initial, .new], context: nil)
        
        do {
            try listenSocket.bind(toPort: port)
            try listenSocket.beginReceiving()
        } catch let e {
            DDLogError(e.localizedDescription)
        }
    }
    
    private func dealwithResponse(datas: [Data]?) {
        if let datas = datas, datas.count > 0 {
            for data in datas {
                let dnsPacket = DNSPacket(data: data)
                if dnsPacket.results.count > 0 {
                    cache[dnsPacket.queryDomains[0]] = dnsPacket.results[0];
                    DDLogVerbose("[dns] cache count:\(cache.count)")
                }
                
                if let address = self.queryDict[dnsPacket.identifier] {
                    self.listenSocket.send(data, toAddress: address, withTimeout: 10, tag: 0)
                    queryDict.removeValue(forKey: dnsPacket.identifier)
                }
            }
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let kp = keyPath, kp == "state" {
            if chinaSession!.state == .ready && foregnSession!.state == .ready {
                DDLogInfo("UDPSession is ready")
            }
            
            if chinaSession!.state == .cancelled || chinaSession!.state == .failed {
                DDLogError("[dns] session is invalid")
            }
        }
    }
}

extension DNSServer: GCDAsyncUdpSocketDelegate {
    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        let dnsPacket = DNSPacket(data: data)
        queryDict[dnsPacket.identifier] = address
        
        let domain = dnsPacket.queryDomains.first!
        DDLogVerbose("[dns] query domain: \(domain)")
        if let ip = cache[domain] {
            if let address = self.queryDict[dnsPacket.identifier] {
                DDLogVerbose("[dns] hit \(domain)")
                self.listenSocket.send(dnsPacket.fakeResponse(ip: ip), toAddress: address, withTimeout: 10, tag: 0)
                queryDict.removeValue(forKey: dnsPacket.identifier)
                return
            }
        }
        
        if !useForeignDNS(domain: domain) {
            chinaSession?.writeDatagram(data, completionHandler: { (error) in
                if let err = error {
                    DDLogError("[dns] \(err.localizedDescription)")
                }
            })
        } else {
            foregnSession?.writeDatagram(data, completionHandler: { (error) in
                if let err = error {
                    DDLogError("[dns] \(err.localizedDescription)")
                }
            })
        }
    }
}
