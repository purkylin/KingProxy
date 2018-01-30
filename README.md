# KingHttpProxy
A http proxy like privoxy
## Feature
* Http(s) proxy
* Fortward http to socks5 proxy
* Partial support surge rule
## Requirement
* Swift4
* Xcode9
* iOS 10.0/macOS 10.12
## Usage
```swift
ACL.shared?.load(configFile: "your config file")
httpProxy = HttpProxy(address: "127.0.0.1", port: 8898)
httpProxy.forwardProxy = ForwardProxy(type: .socks5, host: "127.0.0.1", port: 8899)
httpProxy.start()
```
## Install
* Carthage
`github "purkylin/KingHttpProxy" "master"`
## TODO


