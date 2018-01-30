# KingHttpProxy
A http proxy like privoxy
## Feature
* Http(s) proxy
* Fortward http to socks5 proxy
* Partial support surge rule
## Usage
```swift
ACL.shared?.load(configFile: "your config file")
httpProxy = HttpProxy(address: "127.0.0.1", port: 8898)
httpProxy.forwardProxy = ForwardProxy(type: .socks5, port: 8899, host: "127.0.0.1")
httpProxy.start()
```
## Install
`github "purkylin/KingHttpProxy"`
## TODO

