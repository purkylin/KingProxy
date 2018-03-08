//
//  ACL.swift
//  Sock5Server
//
//  Created by Purkylin King on 2017/12/14.
//  Copyright © 2017年 Purkylin King. All rights reserved.
//

import Foundation
import MMDB
import CocoaLumberjackSwift

enum RuleType: String {
    case domain = "DOMAIN"
    case domainSuffix = "DOMAIN-SUFFIX"
    case domainKeyword = "DOMAIN-KEYWORD"
    case ip = "IP-CIDR"
    case geoip = "GEOIP"
    case final = "FINAL"
}

enum RuleAction: String {
    case direct = "DIRECT"
    case proxy = "Proxy"
    case reject = "REJECT"
}

class Rule {
    var type: RuleType
    var value: String?
    var action: RuleAction
    
    init(type: RuleType, value: String?, action: RuleAction) {
        self.type = type
        self.value = value
        self.action = action
    }
    
    var description: String {
        let t = value ?? ""
        return "\(action.rawValue) \(type.rawValue) \(t)"
    }
    
    var raw: String {
        if type == .final {
            return "\(type.rawValue),\(action.rawValue)"
        } else {
            return "\(type.rawValue),\(value!),\(action.rawValue)"
        }
    }
}

public class ACL {
    public static var shared = ACL()
    public let useDNS = true // whether use module dns
    
    private var db: MMDB
    var rules = [Rule]()
    private var defaultAction: RuleAction = .proxy
    
    public var isEmpty: Bool { return rules.count == 0 }
    
    public init?() {
        guard let db = MMDB() else {
            DDLogError("Init mmdb failed")
            return nil
        }
        
        self.db = db
    }
    
    /// Load rule file, only support local file
    public func load(configFile: String) {
        do {
            DDLogVerbose("[acl] Load rule file...")
            let raw = try String(contentsOfFile: configFile)
            rules = parseConfig(raw: raw)
            DDLogVerbose("[acl] Load rule ok, count:\(rules.count)")
        } catch let e {
            DDLogError("[acl] Load config file failed:\(e.localizedDescription)")
        }
    }
    
    func test() {
        if let country = db.lookup("35.194.108.236") {
            print(country.isoCode)
        }
    }
    
    private func useProxyWithoutDNS(host: String) -> Bool {
        var ip = ""
        if !validIP(ip: host) {
            ip = toIP(from: host)
        }
        
        for rule in rules {
            switch rule.type {
            case .domain:
                if rule.value! == host.lowercased() {
                    DDLogInfo("use rule: \(rule.description)")
                    return rule.action == .proxy
                }
            case .domainKeyword:
                if host.lowercased().contains(rule.value!) {
                    DDLogInfo("use rule: \(rule.description)")
                    return rule.action == .proxy
                }
            case .domainSuffix:
                if host.lowercased().hasSuffix(rule.value!) {
                    DDLogInfo("use rule: \(rule.description)")
                    return rule.action == .proxy
                }
            case .ip:
                if match(ip: ip, ipSegment: rule.value!) {
                    DDLogInfo("use rule: \(rule.description)")
                    return rule.action == .proxy
                }
            case .geoip:
                if let country = db.lookup(ip) {
                    if country.isoCode.lowercased() == rule.value! {
                        DDLogInfo("country \(country.isoCode), \(rule.value ?? "")")
                        DDLogInfo("use rule: \(rule.description)")
                        return rule.action == .proxy
                    }
                }
            default:
                break
            }
        }
        
        DDLogInfo("use rule: final")
        return defaultAction == .proxy
    }
    
    public func useProxy(host: String) -> Bool {
        if isEmpty {
            DDLogInfo("[acl] global mode or no rules")
            return true // default rule
        }
        
        if !useDNS { // without dns module
            return useProxyWithoutDNS(host:host)
        }
        
        var ip = ""
        var domain = ""
        
        if !validIP(ip: host) {
            ip = toIP(from: host)
            if isFakeIP(ip: ip) {
                DDLogInfo("[acl] fake ip: host")
                return true
            }
            domain = host
        } else {
            domain = DNSServer.default.reverse(ip: ip) ?? ""
        }
        
        // apply domain rule
        for rule in rules {
            switch rule.type {
            case .domain:
                if rule.value! == domain.lowercased() {
                    DDLogInfo("use rule: \(rule.description)")
                    return rule.action == .proxy
                }
            case .domainKeyword:
                if domain.lowercased().contains(rule.value!) {
                    DDLogInfo("use rule: \(rule.description)")
                    return rule.action == .proxy
                }
            case .domainSuffix:
                if domain.lowercased().hasSuffix(rule.value!) {
                    let trimedString = domain.dropLast(rule.value!.count)
                    if trimedString.hasSuffix(".") || trimedString == "" {
                        DDLogInfo("use rule: \(rule.description)")
                        return rule.action == .proxy
                    }
                }
            case .ip:
                if match(ip: ip, ipSegment: rule.value!) {
                    DDLogInfo("use rule: \(rule.description)")
                    return rule.action == .proxy
                }
            case .geoip:
                if let country = db.lookup(ip) {
                    if country.isoCode.lowercased() == rule.value! {
                        DDLogInfo("country \(country.isoCode), \(rule.value ?? "")")
                        DDLogInfo("use rule: \(rule.description)")
                        return rule.action == .proxy
                    }
                }
            default:
                break
            }
        }
        
        return defaultAction == .proxy
    }
    
    /// 废弃
    func toIP(from domain: String) -> String {
        if validIP(ip: domain) {
            return domain
        }
        
        let host = CFHostCreateWithName(nil,domain as CFString).takeRetainedValue()
        CFHostStartInfoResolution(host, .addresses, nil)
        var success: DarwinBoolean = false
        if let addresses = CFHostGetAddressing(host, &success)?.takeUnretainedValue() as NSArray? {
            for case let theAddress as NSData in addresses {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(theAddress.bytes.assumingMemoryBound(to: sockaddr.self), socklen_t(theAddress.length),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let numAddress = String(cString: hostname)
                    DDLogVerbose(numAddress)
                    return numAddress
                }
            }
        }
        
        return ""
    }
    
    private func validIP(ip: String) -> Bool {
        let regex = try! NSRegularExpression(pattern: "\\d{1,3}.\\d{1,3}.\\d{1,3}.\\d{1,3}", options: [])
        let range = NSRange(location: 0, length: ip.count)
        return regex.matches(in: ip, options: [], range: range).count > 0
    }
    
    private func match(ip: String, ipSegment: String) -> Bool {
        if ip.count == 0 {
            return false
        }
        
        let arr = ipSegment.components(separatedBy: "/")
        guard arr.count == 2 else { return false }
        
        let mask = Int(arr[1])!
        let sourceIP = toNumber(ipv4: arr[0])
        let dstIP = toNumber(ipv4: ip)
        return (dstIP & (0xff << mask)) == sourceIP
    }
    
    private func toNumber(ipv4: String) -> UInt32 {
        let arr = ipv4.components(separatedBy: ".")
        guard arr.count == 4 else { return 0 }
        let items = arr.map { UInt32($0) ?? 0 }
        
        var result: UInt32 = 0
        result += items[0] << 24
        result += items[1] << 16
        result += items[2] << 8
        result += items[3] << 0
        return result
    }
    
    private func parseConfig(raw: String) -> [Rule] {
        let lines = raw.components(separatedBy: CharacterSet(charactersIn: "\n")).map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " \r\t"))
        }
        
        enum State {
            case initial, general, rule
        }
        
        var rules = [Rule]()
        var state: State = .initial
        
        for i in 0..<lines.count {
            let line = lines[i].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if line == "" || line.starts(with: "#") {
                continue
            } else if line == "[General]" {
                state = .general
                continue
            } else if line == "[Rule]" {
                state = .rule
                continue
            }
            
            if state == .rule {
                let items = line.components(separatedBy: CharacterSet(charactersIn: ","))
                if items.count == 2 { // Final
                    guard let action = RuleAction(rawValue: items[1]) else { continue }
                    defaultAction = action
                } else if items.count == 3 {
                    if let type = RuleType(rawValue: items[0]), let action = RuleAction(rawValue: items[2]) {
                        rules.append(Rule(type: type, value: items[1].lowercased(), action: action))
                    } else {
                        print("Error: Invalid item \(line)")
                    }
                }
            }
        }
        
        return rules
    }
}
