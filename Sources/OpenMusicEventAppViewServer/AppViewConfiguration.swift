import Foundation
import Hummingbird

public struct AppViewConfiguration: Sendable {
    public init(
        host: String = "127.0.0.1",
        port: Int = 8080,
        siteRoot: URL? = nil,
        wellKnownRoot: URL? = nil
    ) {
        self.host = host
        self.port = port
        self.siteRoot = siteRoot ?? Bundle.module.resourceURL!.appendingPathComponent("Site")
        self.wellKnownRoot = wellKnownRoot ?? Bundle.module.resourceURL!.appendingPathComponent("WellKnown")
    }

    public var host: String
    public var port: Int
    public var siteRoot: URL
    public var wellKnownRoot: URL
}

public extension AppViewConfiguration {
    static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        Self(
            host: environment["OME_APPVIEW_HOST"] ?? "127.0.0.1",
            port: environment["OME_APPVIEW_PORT"].flatMap(Int.init) ?? 8080,
            siteRoot: environment["OME_APPVIEW_SITE_ROOT"].map(URL.init(fileURLWithPath:)),
            wellKnownRoot: environment["OME_APPVIEW_WELL_KNOWN_ROOT"].map(URL.init(fileURLWithPath:))
        )
    }

    static func lambda(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        Self(
            host: environment["OME_APPVIEW_HOST"] ?? "127.0.0.1",
            port: environment["OME_APPVIEW_PORT"].flatMap(Int.init) ?? 8080,
            siteRoot: lambdaSiteRoot(environment: environment),
            wellKnownRoot: lambdaWellKnownRoot(environment: environment)
        )
    }

    var hummingbirdConfiguration: ApplicationConfiguration {
        .init(address: .hostname(host, port: port))
    }

    private static func lambdaSiteRoot(environment: [String: String]) -> URL {
        if let siteRoot = environment["OME_APPVIEW_SITE_ROOT"] {
            return URL(fileURLWithPath: siteRoot)
        }

        let taskRoot = environment["LAMBDA_TASK_ROOT"] ?? FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: taskRoot).appendingPathComponent("Site", isDirectory: true)
    }

    private static func lambdaWellKnownRoot(environment: [String: String]) -> URL {
        if let wellKnownRoot = environment["OME_APPVIEW_WELL_KNOWN_ROOT"] {
            return URL(fileURLWithPath: wellKnownRoot)
        }

        let taskRoot = environment["LAMBDA_TASK_ROOT"] ?? FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: taskRoot).appendingPathComponent("WellKnown", isDirectory: true)
    }
}
