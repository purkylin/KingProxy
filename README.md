# KingHttpProxy
A http proxy like privoxy

## Description
Forward http request to socks5 proxy, just like Privoxy
## Usage
```swift
httpProxy = HttpProxy(address: "127.0.0.1", port: 8898)
httpProxy.forwardProxy = ForwardProxy(type: .socks5, port: 8899, host: "127.0.0.1")
httpProxy.start()
```

## TODO

