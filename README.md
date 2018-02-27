# KingProxy
A proxy can forward http to socks and socks to socks base rule
## Feature
* Http(s) proxy
* Forward http to socks5 proxy
* Forward socks to another sub socks proxy
* Partial support surge rule
## Requirement
* Swift4
* Xcode9
* iOS 10.0/macOS 10.12
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
```
## Install
* Carthage
`github "purkylin/KingProxy" "master"`
## TODO
* Stable api
* Implementent KingDNSProxy composent

