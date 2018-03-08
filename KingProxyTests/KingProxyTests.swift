//
//  KingProxyTests.swift
//  KingProxyTests
//
//  Created by Purkylin King on 2018/3/7.
//  Copyright © 2018年 Purkylin King. All rights reserved.
//

import XCTest
import KingProxy

class KingProxyTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        let file = Bundle(for: ACL.self).path(forResource: "Surge", ofType: "conf")!
        ACL.shared?.load(configFile: file)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssert(ACL.shared!.useProxy(host: "baidu.com") == false)
        XCTAssert(ACL.shared!.useProxy(host: "sina.baidu.com") == true) // not exist
        XCTAssert(ACL.shared!.useProxy(host: "google.com") == true)
        XCTAssert(ACL.shared!.useProxy(host: "purkylin.com") == true)
        XCTAssert(ACL.shared!.useProxy(host: "www.purkylin.com") == true)
        XCTAssert(ACL.shared!.useProxy(host: "in.com") == true)
        XCTAssert(ACL.shared!.useProxy(host: "twitter.com") == true)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
