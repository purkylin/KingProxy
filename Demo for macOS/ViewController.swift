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

class ViewController: NSViewController {
    let server = KingHttpProxy(address: "127.0.0.1", port: 8889)
    let socksServer = KingSocksProxy(address: "127.0.0.1", port: 2222)

    override func viewDidLoad() {
        super.viewDidLoad()
        
        DDLog.add(DDTTYLogger.sharedInstance) // TTY = Xcode console

        let queue = DispatchQueue(label: "abc")
        queue.async {
            print("do")
        }
        
        DispatchQueue.concurrentPerform(iterations: 3) { (n) in
            print("hello \(n)")
        }

    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    @IBAction func btnClicked(_ sender: Any) {
//        server.forwardProxy = ForwardProxy(type: .socks5, host: "127.0.0.1", port: 1086)
//        server.start()
        
        socksServer.forwardProxy = ForwardProxy(type: .socks5, host: "127.0.0.1", port: 1086)
        socksServer.start()

    }
    
}

