import ComposableArchitecture2
import ComposableCalendarEvents
import Dependencies
import ErrorHandling
import OpenMusicEventLexicon
import OpenMusicEventViewers
import OpenMusicEventWhiteLabel
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

/// A branded entry point into the same browse -> install -> event workflow as the generic app.
/// It owns no source, authentication, or authoring behavior.
@Feature
public struct WhiteLabelRoot {
    public init() {}

    public struct State {
        public init(configuration: WhiteLabelAppConfiguration) {
            self.configuration = configuration
        }

        public var configuration: WhiteLabelAppConfiguration
        public var errorMessage: String?
        public var isLoading = false
    }

    public enum Action {
        case retryButtonTapped
        case task
    }

    @Dependency(\.calendarEvents) var calendarEvents
    @Dependency(\.omeEventInstallation) var eventInstallation
    @Dependency(\.whiteLabelOrganizerIdentityResolver) var identityResolver

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .retryButtonTapped, .task:
                guard !state.isLoading else { return }
                state.isLoading = true
                state.errorMessage = nil
                let configuration = state.configuration
                store.addTask {
                    let eventID = await store.withErrorHandling(
                        fallbackMessage: .whiteLabelLoadFailed,
                        operation: .whiteLabelLoad
                    ) {
                        let organizerID = try await Self.organizerID(
                            configuration,
                            identityResolver: identityResolver
                        )
                        let page = try await calendarEvents.browse(
                            CalendarEvent.PageRequest(collection: OME.Event.nsid)
                        )
                        guard let event = page.events.first(where: {
                            $0.organizer.id == organizerID
                        }) else {
                            throw WhiteLabelError.missingEvent(organizerID)
                        }
                        return try await eventInstallation.ensureInstalled(event.uri)
                    }

                    try store.modify { $0.isLoading = false }
                    guard let eventID else {
                        try store.modify {
                            $0.errorMessage = UserFacingText.whiteLabelLoadFailed.localizedString
                        }
                        return
                    }
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(eventID, nil)
                    )
                }
            }
        }
        .onMount { state in
            guard !state.isLoading else { return }
            state.isLoading = true
            state.errorMessage = nil
            let configuration = state.configuration
            store.addTask {
                let eventID = await store.withErrorHandling(
                    fallbackMessage: .whiteLabelLoadFailed,
                    operation: .whiteLabelLoad
                ) {
                    let organizerID = try await Self.organizerID(
                        configuration,
                        identityResolver: identityResolver
                    )
                    let page = try await calendarEvents.browse(
                        CalendarEvent.PageRequest(collection: OME.Event.nsid)
                    )
                    guard let event = page.events.first(where: {
                        $0.organizer.id == organizerID
                    }) else {
                        throw WhiteLabelError.missingEvent(organizerID)
                    }
                    return try await eventInstallation.ensureInstalled(event.uri)
                }
                try store.modify { $0.isLoading = false }
                guard let eventID else {
                    try store.modify {
                        $0.errorMessage = UserFacingText.whiteLabelLoadFailed.localizedString
                    }
                    return
                }
                try store.post(key: NavigationRequested.self, value: .event(eventID, nil))
            }
        }
    }

    private static func organizerID(
        _ configuration: WhiteLabelAppConfiguration,
        identityResolver: WhiteLabelOrganizerIdentityResolverClient
    ) async throws -> OME.Organizer.ID {
        if let organizerID = configuration.organizerID {
            return organizerID
        }
        if let handle = configuration.handle {
            return try await identityResolver.resolve(handle)
        }
        if let organizerID = configuration.developmentOrganizerID {
            return organizerID
        }
        throw WhiteLabelError.missingOrganizerIdentity(configuration.brand.displayName)
    }
}

public struct WhiteLabelRootView: View {
    public init(store: StoreOf<WhiteLabelRoot>) {
        self.store = store
    }

    let store: StoreOf<WhiteLabelRoot>

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let loadingImage = store.configuration.brand.loadingImage {
                    Image(loadingImage.name, bundle: Bundle(url: loadingImage.bundleURL))
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 320, maxHeight: 240)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: store.configuration.brand.systemImage)
                        .font(.largeTitle)
                }
                Text(store.configuration.brand.displayName)
                    .font(.title)
                if store.isLoading {
                    ProgressView()
                }
                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Try Again") { store.send(.retryButtonTapped) }
                }
            }
            .padding()
        }
    }
}

private extension UserFacingText {
    static let whiteLabelLoadFailed = Self(
        "Unable to load event.",
        fallback: "Unable to load event."
    )
}

private extension ErrorOperation {
    static let whiteLabelLoad = Self("white-label.load")
}
