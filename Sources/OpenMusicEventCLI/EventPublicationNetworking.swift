import Foundation
import struct ArgumentParser.ValidationError

enum EventPublicationNetworking {
    static func configuration(proxy: String?) throws -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        if let proxy {
            configuration.connectionProxyDictionary = try proxyDictionary(proxy)
        }
        return configuration
    }

    static func proxyDictionary(_ value: String) throws -> [AnyHashable: Any] {
        guard let url = URL(string: value), url.scheme == "http",
              let host = url.host, !host.isEmpty, let port = url.port,
              url.user == nil, url.password == nil,
              url.path.isEmpty || url.path == "/",
              url.query == nil, url.fragment == nil else {
            throw ValidationError(
                "--proxy must be an http URL with a host and port and no path or credentials."
            )
        }
        return [
            "HTTPEnable": 1,
            "HTTPProxy": host,
            "HTTPPort": port,
            "HTTPSEnable": 1,
            "HTTPSProxy": host,
            "HTTPSPort": port,
        ]
    }
}
