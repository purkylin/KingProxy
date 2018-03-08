//
//  ViewController.swift
//  Demo for macOS
//
//  Created by Purkylin King on 2018/1/31.
//  Copyright © 2018年 Purkylin King. All rights reserved.
//

import Cocoa
import KingProxy
import CocoaLumberjackSwift
import CocoaAsyncSocket

class ViewController: NSViewController {
    let httpServer = KingHttpProxy()
    let socksServer = KingSocksProxy()
    let dnsServer = DNSServer.default

    override func viewDidLoad() {
        super.viewDidLoad()
        
        DDLog.add(DDTTYLogger.sharedInstance) // TTY = Xcode console

//        let queue = DispatchQueue(label: "abc")
//        queue.async {
//            print("do")
//        }
//
//        DispatchQueue.concurrentPerform(iterations: 3) { (n) in
//            print("hello \(n)")
//        }
        dnsServer.start(on: 5544)
    }

    @IBAction func btnClicked(_ sender: Any) {
        httpServer.forwardProxy = ForwardProxy(type: .http, host: "127.0.0.1", port: 8888)
        _ = httpServer.start(on: 8900)
//        let file = Bundle(for: KingHttpProxy.self).path(forResource: "Surge", ofType: "conf")
//        ACL.shared?.load(configFile: file!)
//        guard httpServer.start(on: 8898) > 0 else { return }
//        httpServer.forwardProxy = ForwardProxy(type: .socks5, host: "127.0.0.1", port: 8899)
//
//        socksServer.forwardProxy = ForwardProxy(type: .socks5, host: "127.0.0.1", port: 1086)
//        _ = socksServer.start(on: 8899)
        
//        DNSServer.shared.resolve(domain: "baidu.com")
//        let domain = "oschina.net"
//        DNSResolver.shared.resolve(domain: domain) { (ip) in
//            if let ip = ip {
//                print("\(domain):\(ip)")
//            } else {
//                print("resolve failed")
//            }
//        }
        
        
        
        
//        if let myip = DNSResolver.shared.resolve(domain: "googleads.g.doubleclick.net") {
//            print(myip)
//        }
    }
}



