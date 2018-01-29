//
//  HttpHeader.swift
//  Assistant
//
//  Created by Purkylin King on 2017/7/28.
//  Copyright © 2017年 Purkylin King. All rights reserved.
//

import Foundation

extension String {
    func substring(range: NSRange) -> String {
        let start = self.index(self.startIndex, offsetBy: range.lowerBound)
        let end = self.index(self.startIndex, offsetBy: range.upperBound)
        let sub = self[start..<end]
        return String(sub)
    }
}

func relativePath(source: String) -> String {
    let pattern = "https?://[^/]+(/.*)?"
    let regex = try! NSRegularExpression(pattern: pattern, options: [])
    if let result = regex.firstMatch(in: source, options: [], range: NSRange(location: 0, length: source.count)) {
        let range = result.range(at: 1)
        return source.substring(range: range)
    } else {
        return "/"
    }
}

open class HttpHeader: CustomStringConvertible {
    var method: String
    var isConnect: Bool = false
    var path: String
    var httpVersion: String
    var contentLength: UInt = 0
    var host: String = ""
    var port: UInt16 = 80
    
    var isBinaryData = false
    var isSecure: Bool = false
    var isExpect: Bool = false
    
    public var headers = [(String, String)]()
    
    var rawData: Data
    var firstLine: String? = nil
    
    enum HttpHeaderError: Error {
        case invalidHeader, invaldConnection, invalidHost, illegalEncoding
    }
    
    init(data: Data) throws {
        rawData = data
        
        if let raw = String(data: data, encoding: .utf8) {
            let lines = raw.components(separatedBy: "\r\n")
            firstLine = lines[0]
            print("[header] \(lines[0])")
            print("[header] \(lines[1])")
            let requestLine = lines[0]
            let request = requestLine.components(separatedBy: " ")
            guard  request.count == 3 else {
                throw HttpHeaderError.invalidHeader
            }
            
            method = request[0]
            path = request[1]
            if request[0] != "CONNECT" && !request[1].hasPrefix("/") {
                if let url = URL(string: path) {
                    port = UInt16(url.port ?? 80)
                } else {
                    port = UInt16(80)
                }
                path = relativePath(source: request[1])
            }
            
            httpVersion = request[2]
            firstLine = "\(method) \(path) HTTP/1.1"
            
            if method.uppercased() == "CONNECT" {
                isConnect = true
                let urlInfo = path.components(separatedBy: ":")
                guard urlInfo.count == 2 else {
                    throw HttpHeaderError.invaldConnection
                }
                
                host = urlInfo[0]
                port = UInt16(urlInfo[1])!
            }
            
            // Others
            for line in lines[1..<lines.count-2] {
                let header = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard header.count == 2 else {
                    throw HttpHeaderError.invalidHeader
                }
                
                let k = String(header[0]).trimmingCharacters(in: CharacterSet.whitespaces)
                var v = String(header[1]).trimmingCharacters(in: CharacterSet.whitespaces)
                if (k == "Connection") {
                    v = "close"
                }
                headers.append((k, v))
            }
            
            if let host = getValue("Host") {
                if host.contains(":") {
                    self.host = host.components(separatedBy: ":")[0]
                    if let port = UInt16(host.components(separatedBy: ":")[1]) {
                        self.port = port
                    } else {
                        throw HttpHeaderError.invalidHost
                    }
                } else {
                    self.host = host
                }
            } else {
                throw HttpHeaderError.invalidHost
            }
            
            if let expect = getValue("Expect"), expect.contains("100-continue") {
                isExpect = true
            }
            
            if isExists("Connection") {
                update(key: "Connection", newValue: "close")
            } else {
                add(key: "Connection", value: "close")
            }
            
            remove("Proxy-Connection")
            contentLength = UInt(getValue("Content-Length") ?? "") ?? 0
        } else {
            throw HttpHeaderError.illegalEncoding
        }
    }
    
    func getValue(_ key: String) -> String? {
        for (k, v) in headers {
            if key == k {
                return v
            }
        }
        
        return nil
    }
    
    func isExists(_ key: String) -> Bool {
        for (k, _) in headers {
            if key == k {
                return true
            }
        }
        
        return false
    }
    
    func update(key: String, newValue: String) {
        for i in 0..<headers.count {
            let (k, _) = headers[i]
            if k == key {
                headers[i] = (k, newValue)
            }
            break
        }
    }
    
    func remove(_ key: String) {
        for i in 0..<headers.count {
            let (k, _) = headers[i]
            if k == key {
                headers.remove(at: i)
                break
            }
        }
    }
    
    func add(key: String, value: String) {
        headers.append((key, value))
    }
    
    public var description: String {
        if let s = String(data: rawData, encoding: .utf8) {
            return s
        } else {
            return "Can't decode request header"
        }
    }
    
    var url: String {
        if isConnect {
            return path
        }
        
        if isSecure {
            return "\(path)"
        } else {
            return "\(path)"
        }
    }
    
    var data: Data {
        var contents = headers.map { (k, v) in
            return "\(k): \(v)"
        }
        
        contents.insert(firstLine!, at: 0)
        return (contents.joined(separator: "\r\n") + "\r\n\r\n").data(using: .utf8)!
    }
    
    func curlCommand(parms: Data?) -> String {
        var cmd = "curl"
        cmd += " -X \(method)"
        
        for (k, v) in headers {
            cmd += " -H '\(k): \(v)'"
        }
        
        if let raw = parms?.utf8, raw.count > 0 {
            cmd += " -d '\(raw)'"
        }
        
        cmd += " '\(url)'"
        return cmd
    }
}

