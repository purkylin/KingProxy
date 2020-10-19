# DEPRECATED (Use new library [nio-proxy](https://github.com/purkylin/proxy-nio))
# KingProxy 

 [![Join the chat at https://telegram.me/NEKitGroup](https://img.shields.io/badge/chat-on%20Telegram-blue.svg)](https://telegram.me/KingProxyTalk)
 [![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage) 
 [![GitHub license](https://img.shields.io/badge/license-BSD_3--Clause-blue.svg)](LICENSE.md)
 
## Feature
* Http(s) proxy
* Forward http to socks5 proxy
* Forward socks to another sub socks proxy
* Partial support surge rule
* DNS server
## Requirement
* Swift5
* Xcode9
* iOS 10.0/macOS 10.12
* Manual download GeoLite2-Country.mmdb file
## Usage
```swift
ACL.shared?.load(configFile: "your config file")

// http
httpProxy = KingHttpProxy()
httpProxy.forwardProxy = ForwardProxy(type: .socks5, host: "127.0.0.1", port: 8899)
_ = httpProxy.start(on: 8899)

// socks
socksProxy = KingSocksProxy()
socksProxy.forwardProxy = ForwardProxy(type: .socks5, host: "127.0.0.1", port: 8899)
_ = socksProxy.start() // Select a free port

// dns
dnsServer = DNSServer()
dnsServer.start(on: 53)
```
## Install
* Carthage
`github "purkylin/KingProxy" "master"`
## TODO
* Stable api

