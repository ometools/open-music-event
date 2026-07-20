import Dependencies
import Foundation
import OpenMusicEventLexicon

public typealias OMERecord = OpenMusicEvent

public struct WhiteLabelAppConfiguration: Equatable, Sendable {
    public var brand: WhiteLabelBrand
    public var developmentOrganizerID: OMERecord.Organizer.ID?
    public var handle: String?
    public var organizerID: OMERecord.Organizer.ID?

    public init(
        brand: WhiteLabelBrand,
        organizerID: OMERecord.Organizer.ID? = nil,
        handle: String? = nil,
        developmentOrganizerID: OMERecord.Organizer.ID? = nil
    ) {
        self.brand = brand
        self.organizerID = organizerID
        self.handle = handle
        self.developmentOrganizerID = developmentOrganizerID
    }
}

public struct WhiteLabelBrand: Equatable, Sendable {
    public var displayName: String
    public var systemImage: String

    public init(
        displayName: String,
        systemImage: String = "music.note.list"
    ) {
        self.displayName = displayName
        self.systemImage = systemImage
    }
}

public struct WhiteLabelSourceDescriptor: Equatable, Sendable {
    public var reference: WhiteLabelSourceReference
    public var version: String?

    public init(
        reference: WhiteLabelSourceReference,
        version: String? = nil
    ) {
        self.reference = reference
        self.version = version
    }
}

public enum WhiteLabelSourceReference: Equatable, Sendable {
    case archiveURL(URL)
    case source(String)
}

public enum WickedWoodsWhiteLabel {
    public static let handle = "wickedwoods.ca"
    public static let temporaryDevelopmentOrganizerID = OMERecord.Organizer.ID("did:plc:wickedwoodsdev")!

    public static func configuration(
        organizerID: OMERecord.Organizer.ID? = nil
    ) -> WhiteLabelAppConfiguration {
        WhiteLabelAppConfiguration(
            brand: WhiteLabelBrand(displayName: "Wicked Woods"),
            organizerID: organizerID,
            handle: handle,
            developmentOrganizerID: organizerID == nil ? temporaryDevelopmentOrganizerID : nil
        )
    }

    public static func developmentSourceOverride(
        reference: WhiteLabelSourceReference,
        version: String? = nil
    ) -> WhiteLabelDevelopmentSourceOverride {
        WhiteLabelDevelopmentSourceOverride(
            organizerID: temporaryDevelopmentOrganizerID,
            source: WhiteLabelSourceDescriptor(reference: reference, version: version)
        )
    }
}

public struct WhiteLabelDevelopmentSourceOverride: Equatable, Sendable {
    public var organizerID: OMERecord.Organizer.ID
    public var source: WhiteLabelSourceDescriptor

    public init(
        organizerID: OMERecord.Organizer.ID,
        source: WhiteLabelSourceDescriptor
    ) {
        self.organizerID = organizerID
        self.source = source
    }
}

public struct WhiteLabelOrganizerIdentityResolverClient: Sendable {
    public var resolve: @Sendable (String) async throws -> OMERecord.Organizer.ID

    public init(
        resolve: @escaping @Sendable (String) async throws -> OMERecord.Organizer.ID
    ) {
        self.resolve = resolve
    }
}

public struct WhiteLabelSourceRegistryClient: Sendable {
    public var source: @Sendable (OMERecord.Organizer.ID) async throws -> WhiteLabelSourceDescriptor

    public init(
        source: @escaping @Sendable (OMERecord.Organizer.ID) async throws -> WhiteLabelSourceDescriptor
    ) {
        self.source = source
    }
}

public struct WhiteLabelSourceImportClient: Sendable {
    public var ensureImported: @Sendable (OMERecord.Organizer.ID, WhiteLabelSourceDescriptor) async throws -> [OMERecord.Event.ID]

    public init(
        ensureImported: @escaping @Sendable (OMERecord.Organizer.ID, WhiteLabelSourceDescriptor) async throws -> [OMERecord.Event.ID]
    ) {
        self.ensureImported = ensureImported
    }
}

public enum WhiteLabelError: Equatable, LocalizedError, Sendable {
    case developmentSourceOverrideUnavailable
    case directSourceRequiresDevelopmentOverride(OMERecord.Organizer.ID)
    case missingOrganizerIdentity(String)
    case organizerIdentityResolverUnconfigured(String)
    case sourceImportUnconfigured(OMERecord.Organizer.ID)
    case sourceRegistryUnconfigured(OMERecord.Organizer.ID)

    public var errorDescription: String? {
        switch self {
        case .developmentSourceOverrideUnavailable:
            "Development source overrides are only available in debug and test builds."
        case .directSourceRequiresDevelopmentOverride:
            "Direct source loading must use the development source override."
        case let .missingOrganizerIdentity(displayName):
            "\(displayName) does not have an organizer account yet."
        case let .organizerIdentityResolverUnconfigured(handle):
            "No organizer account resolver is configured for \(handle)."
        case .sourceImportUnconfigured:
            "No white-label source importer is configured for this organizer."
        case .sourceRegistryUnconfigured:
            "No white-label source is registered for this organizer."
        }
    }
}

private enum WhiteLabelDevelopmentSourceOverrideKey: DependencyKey {
    static var liveValue: WhiteLabelDevelopmentSourceOverride? { nil }
    static var testValue: WhiteLabelDevelopmentSourceOverride? { nil }
}

private enum WhiteLabelOrganizerIdentityResolverClientKey: DependencyKey {
    static var liveValue: WhiteLabelOrganizerIdentityResolverClient {
        WhiteLabelOrganizerIdentityResolverClient { handle in
            throw WhiteLabelError.organizerIdentityResolverUnconfigured(handle)
        }
    }

    static var testValue: WhiteLabelOrganizerIdentityResolverClient {
        liveValue
    }
}

private enum WhiteLabelSourceRegistryClientKey: DependencyKey {
    static var liveValue: WhiteLabelSourceRegistryClient {
        WhiteLabelSourceRegistryClient { organizerID in
            throw WhiteLabelError.sourceRegistryUnconfigured(organizerID)
        }
    }

    static var testValue: WhiteLabelSourceRegistryClient {
        liveValue
    }
}

private enum WhiteLabelSourceImportClientKey: DependencyKey {
    static var liveValue: WhiteLabelSourceImportClient {
        WhiteLabelSourceImportClient { organizerID, _ in
            throw WhiteLabelError.sourceImportUnconfigured(organizerID)
        }
    }

    static var testValue: WhiteLabelSourceImportClient {
        WhiteLabelSourceImportClient { _, _ in [] }
    }
}

public extension DependencyValues {
    var whiteLabelDevelopmentSourceOverride: WhiteLabelDevelopmentSourceOverride? {
        get { self[WhiteLabelDevelopmentSourceOverrideKey.self] }
        set { self[WhiteLabelDevelopmentSourceOverrideKey.self] = newValue }
    }

    var whiteLabelOrganizerIdentityResolver: WhiteLabelOrganizerIdentityResolverClient {
        get { self[WhiteLabelOrganizerIdentityResolverClientKey.self] }
        set { self[WhiteLabelOrganizerIdentityResolverClientKey.self] = newValue }
    }

    var whiteLabelSourceImport: WhiteLabelSourceImportClient {
        get { self[WhiteLabelSourceImportClientKey.self] }
        set { self[WhiteLabelSourceImportClientKey.self] = newValue }
    }

    var whiteLabelSourceRegistry: WhiteLabelSourceRegistryClient {
        get { self[WhiteLabelSourceRegistryClientKey.self] }
        set { self[WhiteLabelSourceRegistryClientKey.self] = newValue }
    }
}

public extension WhiteLabelSourceRegistryClient {
    static func codeBacked(
        _ sources: [OMERecord.Organizer.ID: WhiteLabelSourceDescriptor]
    ) -> Self {
        Self { organizerID in
            guard let source = sources[organizerID] else {
                throw WhiteLabelError.sourceRegistryUnconfigured(organizerID)
            }
            return source
        }
    }
}
