import ATProto
import Dependencies
import Foundation
import OpenMusicEventLexicon

/// White-label configuration is presentation and organizer identity only.
///
/// Source discovery, installation, authentication, and authoring use the same live application
/// features as the generic app.
public struct WhiteLabelAppConfiguration: Equatable, Sendable {
    public var brand: WhiteLabelBrand
    public var developmentOrganizerID: DID?
    public var handle: String?
    public var organizerID: DID?

    public init(
        brand: WhiteLabelBrand,
        organizerID: DID? = nil,
        handle: String? = nil,
        developmentOrganizerID: DID? = nil
    ) {
        self.brand = brand
        self.organizerID = organizerID
        self.handle = handle
        self.developmentOrganizerID = developmentOrganizerID
    }
}

public struct WhiteLabelBrand: Equatable, Sendable {
    public var displayName: String
    public var loadingImage: WhiteLabelStaticImage?
    public var systemImage: String

    public init(
        displayName: String,
        systemImage: String = "music.note.list",
        loadingImage: WhiteLabelStaticImage? = nil
    ) {
        self.displayName = displayName
        self.loadingImage = loadingImage
        self.systemImage = systemImage
    }
}

public struct WhiteLabelStaticImage: Equatable, Sendable {
    public var bundleURL: URL
    public var name: String

    public init(name: String, bundleURL: URL) {
        self.bundleURL = bundleURL
        self.name = name
    }
}

public enum WickedWoodsWhiteLabel {
    public static let handle = "wickedwoods.ca"
    public static let temporaryDevelopmentOrganizerID = DID(
        "did:plc:wickedwoodsdev"
    )!

    public static func configuration(
        organizerID: DID? = nil,
        loadingImage: WhiteLabelStaticImage? = nil
    ) -> WhiteLabelAppConfiguration {
        WhiteLabelAppConfiguration(
            brand: WhiteLabelBrand(
                displayName: "Wicked Woods",
                loadingImage: loadingImage
            ),
            organizerID: organizerID,
            handle: handle,
            developmentOrganizerID: organizerID == nil ? temporaryDevelopmentOrganizerID : nil
        )
    }
}

public struct WhiteLabelOrganizerIdentityResolverClient: Sendable {
    public var resolve: @Sendable (String) async throws -> DID

    public init(
        resolve: @escaping @Sendable (String) async throws -> DID
    ) {
        self.resolve = resolve
    }
}

public enum WhiteLabelError: Equatable, LocalizedError, Sendable {
    case missingEvent(DID)
    case missingOrganizerIdentity(String)
    case organizerIdentityResolverUnconfigured(String)

    public var errorDescription: String? {
        switch self {
        case .missingEvent:
            "No published event is available for this organizer."
        case let .missingOrganizerIdentity(displayName):
            "\(displayName) does not have an organizer account yet."
        case let .organizerIdentityResolverUnconfigured(handle):
            "No organizer account resolver is configured for \(handle)."
        }
    }
}

private enum WhiteLabelOrganizerIdentityResolverClientKey: DependencyKey {
    static var liveValue: WhiteLabelOrganizerIdentityResolverClient {
        WhiteLabelOrganizerIdentityResolverClient { handle in
            throw WhiteLabelError.organizerIdentityResolverUnconfigured(handle)
        }
    }

    static var testValue: WhiteLabelOrganizerIdentityResolverClient { liveValue }
}

public extension DependencyValues {
    var whiteLabelOrganizerIdentityResolver: WhiteLabelOrganizerIdentityResolverClient {
        get { self[WhiteLabelOrganizerIdentityResolverClientKey.self] }
        set { self[WhiteLabelOrganizerIdentityResolverClientKey.self] = newValue }
    }
}
