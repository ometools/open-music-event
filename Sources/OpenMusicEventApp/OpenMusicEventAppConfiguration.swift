import ATProto
import ComposableAtmosphereUserInput
import ComposableAtmosphereUserInputUI
import Dependencies
import Foundation
import OpenMusicEventAppRouting

public struct OpenMusicEventAppConfiguration: Equatable, Sendable {
    public var productFeedbackBoard: OpenMusicEventFeedbackBoardConfiguration?

    public init(
        productFeedbackBoard: OpenMusicEventFeedbackBoardConfiguration? = .openMusicEventApp
    ) {
        self.productFeedbackBoard = productFeedbackBoard
    }

    public static let openMusicEvent = Self()

    public static let wickedWoods = Self()
}

public struct OpenMusicEventFeedbackBoardConfiguration: Equatable, Sendable {
    public var externalURL: URL?
    public var spaceURI: ATProto.URI

    public init(
        spaceURI: ATProto.URI,
        externalURL: URL? = nil
    ) {
        self.externalURL = externalURL
        self.spaceURI = spaceURI
    }

    public static let openMusicEventApp = Self(
        spaceURI: ATProto.URI(
            authority: "did:plc:42p4f3krv45gtkxjooaekbnw",
            collection: UserInputCollection.space.nsid,
            rkey: ATProto.Record.Key(rawValue: "3moixlle7bs25")
        ),
        externalURL: URL(
            string: "https://userinput.app/s/did:plc:42p4f3krv45gtkxjooaekbnw/3moixlle7bs25"
        )
    )

    public var userInputConfiguration: UserInputFeedbackBoardConfiguration? {
        guard spaceURI.collection == UserInputCollection.space.nsid,
              spaceURI.rkey != nil
        else { return nil }

        return UserInputFeedbackBoardConfiguration(
            space: UserInputRecordReference(uri: spaceURI),
            externalURL: externalURL
        )
    }
}

private enum OpenMusicEventAppConfigurationKey: DependencyKey {
    static var liveValue: OpenMusicEventAppConfiguration { .openMusicEvent }
    static var testValue: OpenMusicEventAppConfiguration { .openMusicEvent }
}

private enum BrandedEventRouteClaimsKey: DependencyKey {
    static var liveValue: [BrandedEventRouteClaim] { [] }
    static var testValue: [BrandedEventRouteClaim] { [] }
}

public extension DependencyValues {
    var openMusicEventAppConfiguration: OpenMusicEventAppConfiguration {
        get { self[OpenMusicEventAppConfigurationKey.self] }
        set { self[OpenMusicEventAppConfigurationKey.self] = newValue }
    }

    var brandedEventRouteClaims: [BrandedEventRouteClaim] {
        get { self[BrandedEventRouteClaimsKey.self] }
        set { self[BrandedEventRouteClaimsKey.self] = newValue }
    }
}
