import Foundation
import Tagged

public enum OpenMusicEventHostTag {}
public enum OpenMusicEventPathTag {}
public enum OpenMusicEventQueryTag {}
public enum OpenMusicEventSiteAssetTag {}
public enum OpenMusicEventWellKnownFileTag {}

public typealias OpenMusicEventHost = Tagged<OpenMusicEventHostTag, String>
public typealias OpenMusicEventPath = Tagged<OpenMusicEventPathTag, String>
public typealias OpenMusicEventQuery = Tagged<OpenMusicEventQueryTag, String>
public typealias OpenMusicEventSiteAsset = Tagged<OpenMusicEventSiteAssetTag, String>
public typealias OpenMusicEventWellKnownFile = Tagged<OpenMusicEventWellKnownFileTag, String>

public struct OpenMusicEventIncomingRequest: Equatable, Sendable {
    public var host: OpenMusicEventHost
    public var path: OpenMusicEventPath
    public var query: OpenMusicEventQuery?

    public init(
        host: OpenMusicEventHost,
        path: OpenMusicEventPath,
        query: OpenMusicEventQuery? = nil
    ) {
        self.host = host
        self.path = path
        self.query = query?.nilIfEmpty
    }
}

public struct OpenMusicEventRoutingConfiguration: Equatable, Sendable {
    public var appHost: OpenMusicEventHost
    public var handleHost: OpenMusicEventHost

    public init(
        appHost: OpenMusicEventHost = OpenMusicEventHost(rawValue: "openmusicevent.app"),
        handleHost: OpenMusicEventHost = OpenMusicEventHost(rawValue: "ome.social")
    ) {
        self.appHost = appHost
        self.handleHost = handleHost
    }

    public static let production = Self()
}

public enum OpenMusicEventRoute: Equatable, Sendable {
    case appleAppSiteAssociation
    case health
    case ready
    case site(OpenMusicEventSiteRoute)
    case wellKnown(OpenMusicEventWellKnownFile)
}

public enum OpenMusicEventSiteRoute: Equatable, Sendable {
    case asset(OpenMusicEventSiteAsset)
    case home
    case index
    case stylesheet
}

public struct OpenMusicEventPathRouter: Sendable {
    public init() {}

    public func parse(_ path: String) -> OpenMusicEventRoute? {
        let pathComponents = path.pathComponents

        if pathComponents.count == 2,
           pathComponents[0] == "assets",
           isSafeSinglePathComponent(pathComponents[1]) {
            return .site(.asset(OpenMusicEventSiteAsset(rawValue: pathComponents[1])))
        }

        if pathComponents.count == 2,
           pathComponents[0] == ".well-known",
           isSafeSinglePathComponent(pathComponents[1]) {
            return .wellKnown(OpenMusicEventWellKnownFile(rawValue: pathComponents[1]))
        }

        switch pathComponents {
        case []:
            return .site(.home)

        case ["index.html"]:
            return .site(.index)

        case ["styles.css"]:
            return .site(.stylesheet)

        case ["apple-app-site-association"]:
            return .appleAppSiteAssociation

        case ["healthz"]:
            return .health

        case ["readyz"]:
            return .ready

        default:
            return nil
        }
    }

    public func path(for route: OpenMusicEventRoute) -> String {
        switch route {
        case .appleAppSiteAssociation:
            return "/apple-app-site-association"

        case .health:
            return "/healthz"

        case .ready:
            return "/readyz"

        case let .site(siteRoute):
            return path(for: siteRoute)

        case let .wellKnown(file):
            precondition(isSafeSinglePathComponent(file.rawValue), "Unsafe well-known file path component.")
            return "/.well-known/\(file.rawValue)"
        }
    }

    public func path(for siteRoute: OpenMusicEventSiteRoute) -> String {
        switch siteRoute {
        case let .asset(asset):
            precondition(isSafeSinglePathComponent(asset.rawValue), "Unsafe asset path component.")
            return "/assets/\(asset.rawValue)"

        case .home:
            return "/"

        case .index:
            return "/index.html"

        case .stylesheet:
            return "/styles.css"
        }
    }
}

public let openMusicEventPathRouter = OpenMusicEventPathRouter()

public struct OpenMusicEventRouter: Sendable {
    public var configuration: OpenMusicEventRoutingConfiguration

    public init(configuration: OpenMusicEventRoutingConfiguration = .production) {
        self.configuration = configuration
    }

    public func route(_ request: OpenMusicEventIncomingRequest) -> OpenMusicEventRoute? {
        openMusicEventPathRouter.parse(normalizedPath(request.path))
    }

    public func path(for route: OpenMusicEventRoute) -> String {
        openMusicEventPathRouter.path(for: route)
    }

    public func url(
        for route: OpenMusicEventRoute,
        host: OpenMusicEventHost? = nil,
        scheme: String = "https"
    ) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = (host ?? configuration.appHost).rawValue
        components.path = path(for: route)
        return components.url!
    }
}

public extension Tagged where Tag == OpenMusicEventWellKnownFileTag, RawValue == String {
    static let appleAppSiteAssociation = Self(rawValue: "apple-app-site-association")
    static let assetLinks = Self(rawValue: "assetlinks.json")
    static let atprotoDID = Self(rawValue: "atproto-did")
    static let didJSON = Self(rawValue: "did.json")
    static let oauthClientMetadata = Self(rawValue: "oauth-client-metadata.json")
}

private func normalizedPath(_ path: OpenMusicEventPath) -> String {
    if path.rawValue.isEmpty {
        return "/"
    }
    if path.rawValue.hasPrefix("/") {
        return path.rawValue
    }
    return "/" + path.rawValue
}

private func isSafeSinglePathComponent(_ value: String) -> Bool {
    !value.isEmpty
        && value != "."
        && value != ".."
        && value.allSatisfy { character in
            character.isASCII
                && (
                    character.isLetter
                        || character.isNumber
                        || character == "."
                        || character == "-"
                        || character == "_"
                )
        }
}

private extension OpenMusicEventQuery {
    var nilIfEmpty: OpenMusicEventQuery? {
        rawValue.isEmpty ? nil : self
    }
}

private extension String {
    var pathComponents: [String] {
        split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}
