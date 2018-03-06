//
//  Util.swift
//  KingProxy-iOS
//
//  Created by Purkylin King on 2018/1/30.
//  Copyright © 2018年 Purkylin King. All rights reserved.
//

import Foundation

extension Data {
    var utf8: String? {
        return String(data: self, encoding: .utf8)
    }
    
    var json: [String : Any]? {
        do {
            let obj = try JSONSerialization.jsonObject(with: self, options: [])
            return obj as? [String : Any]
        } catch let e {
            print(e.localizedDescription)
            return nil
        }
    }
}

func validIP(ip: String) -> Bool {
    let regex = try! NSRegularExpression(pattern: "\\d{1,3}.\\d{1,3}.\\d{1,3}.\\d{1,3}", options: [])
    let range = NSRange(location: 0, length: ip.count)
    return regex.matches(in: ip, options: [], range: range).count > 0
}

func isFakeIP(ip: String) -> Bool {
    return ip == "240.0.0.34"
}
