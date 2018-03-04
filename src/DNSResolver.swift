//
//  DNSResolver.swift
//  Demo for macOS
//
//  Created by Purkylin King on 2018/3/4.
//  Copyright © 2018年 Purkylin King. All rights reserved.
//

import Foundation
import CocoaAsyncSocket
import CocoaLumberjackSwift

func after(_ interval: TimeInterval, task: @escaping ()->()) {
    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + interval) {
        task()
    }
}

public final class DNSResolver: NSObject {
    private var requestSocket: GCDAsyncUdpSocket!
    private var completions = [UInt16 : (String?) -> Void]()
    
    public static var shared = DNSResolver()
    private var server = "114.114.114.114"
    
    override init() {
        super.init()
        start()
    }
    
    private func start() {
        let requestQueue = DispatchQueue.global()
        requestSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: requestQueue)
        
        do {
            try requestSocket.bind(toPort: 0)
            try requestSocket.beginReceiving()
        } catch let e {
            DDLogError(e.localizedDescription)
        }
    }
    
    private func stop() {
        requestSocket.close()
    }
    
    /// sync resolve domain
    public func resolve(domain: String) -> String? {
        let semaphore = DispatchSemaphore.init(value: 0)
        var result: String?
        
        resolve(domain: domain) { (ip) in
            result = ip
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: DispatchTime.now() + 1000)
        return result
    }
    
    /// async resolve domain
    public func resolve(domain: String, completion: @escaping (String?) -> Void) {
        let query = Message(
            id: UInt16(truncatingIfNeeded: arc4random()),
            type: .query,
            recursionDesired: true,
            questions: [
                Question(name: domain, type: .host)
            ])
        
        do {
            let requestData = try query.serialize()
            completions[query.id] = completion
            after(0.2, task: {
                self.completions[query.id] = nil
            })
            
            requestSocket.send(requestData, toHost: server, port: 53, withTimeout: 1, tag: 100)
        } catch let e {
            DDLogError(e.localizedDescription)
        }
    }
}

extension DNSResolver: GCDAsyncUdpSocketDelegate {
    public func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        do {
            let response = try Message.init(deserialize: data)
            let completion = completions[response.id]
            if let record = response.answers.first as? HostRecord<IPv4> {
                let host = record.ip.presentation
                completion?(host)
            } else {
                completion?(nil)
            }
            
            DispatchQueue.main.async {
                self.completions[response.id] = nil
            }
        } catch let e {
            DDLogError(e.localizedDescription)
        }
    }
}
