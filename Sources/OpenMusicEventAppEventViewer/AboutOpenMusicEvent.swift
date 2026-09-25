import ATProto
import Bluesky
import ComposableArchitecture2
import Dependencies
import Foundation
import ATProtoTypes
import OpenMusicEventImages
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

public struct AppContribution: Equatable, Identifiable, Sendable {
    public init(
        id: String,
        avatarURL: URL? = nil,
        bio: String? = nil,
        did: DID,
        displayName: String,
        handle: String? = nil,
        role: OMERecord.Relationship.Role
    ) {
        self.id = id
        self.avatarURL = avatarURL
        self.bio = bio
        self.did = did
        self.displayName = displayName
        self.handle = handle
        self.role = role
    }

    public let id: String
    public let avatarURL: URL?
    public let bio: String?
    public let did: DID
    public let displayName: String
    public let handle: String?
    public let role: OMERecord.Relationship.Role

    var avatarAsset: OMERecord.ImageAsset? {
        avatarURL.map {
            OMERecord.ImageAsset(
                source: .url($0),
                role: .photo,
                renderKind: .fullImage,
                materializationPolicy: .lazy
            )
        }
    }

    var handleText: String? {
        handle.map { "@\($0)" }
    }

    var roleTitle: String {
        role == .developer ? "Developer" : role.rawValue
    }
}

public struct AppContributorsClient: Sendable {
    public init(
        load: @escaping @Sendable () async throws -> [AppContribution]
    ) {
        self.load = load
    }

    public var load: @Sendable () async throws -> [AppContribution]
}

public enum AppContributorsClientError: Equatable, Error, Sendable {
    case missingPDSHost(String)
    case unimplemented
}

public extension AppContributorsClient {
    static var live: Self {
        Self {
            @Dependency(Atmosphere.Account.Client.self) var accountClient
            @Dependency(\.blueskyActorProfileCache) var actorProfileCache
            @Dependency(XRPC.Client.self) var xrpcClient

            let (account, didDocument) = try await accountClient.resolveHandle(
                Atmosphere.Account.Handle(rawValue: "openmusicevent.app")
            )
            let appDID = account.id.rawValue
            guard let pdsHost = didDocument.pdsHost else {
                throw AppContributorsClientError.missingPDSHost(appDID.description)
            }

            var cursor: ATProto.Repository.Cursor?
            var listedRecords: [ATProto.Repository.ListedRecord<OMERecord.Relationship>] = []
            repeat {
                let page = try await xrpcClient.listRecords(
                    OMERecord.Relationship.self,
                    repo: .did(appDID),
                    collection: OMERecord.Relationship.nsid,
                    limit: 100,
                    cursor: cursor,
                    pdsHost: pdsHost,
                    authorizationPolicy: .none
                )
                listedRecords.append(contentsOf: page.records)
                cursor = page.cursor
            } while cursor != nil

            var contributions: [AppContribution] = []
            for listedRecord in listedRecords {
                guard let identity = developerIdentity(
                    from: listedRecord,
                    appDID: appDID
                ) else { continue }

                let cachedProfile = try? await actorProfileCache.cachedProfile(
                    identity.did.description
                )
                let refreshedProfile = try? await actorProfileCache.refreshProfileIfNeeded(
                    identity.did.description,
                    60 * 60 * 24,
                    60 * 15
                )
                let profile = refreshedProfile ?? cachedProfile
                let handle = profile?.handle.nilIfEmpty ?? identity.handle?.nilIfEmpty
                let displayName = profile?.displayName?.nilIfEmpty
                    ?? identity.displayName?.nilIfEmpty
                    ?? handle
                    ?? "Contributor"
                contributions.append(
                    AppContribution(
                        id: listedRecord.uri.description,
                        avatarURL: profile?.avatar,
                        bio: profile?.description?.nilIfEmpty,
                        did: identity.did,
                        displayName: displayName,
                        handle: handle,
                        role: listedRecord.value.role
                    )
                )
            }

            return contributions.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        }
    }

    static func developerIdentity(
        from listedRecord: ATProto.Repository.ListedRecord<OMERecord.Relationship>,
        appDID: DID
    ) -> OMERecord.Relationship.IdentityReference? {
        guard case let .did(authorDID) = listedRecord.uri.authority,
              authorDID == appDID,
              listedRecord.value.role == .developer,
              case let .known(.identity(subject)) = listedRecord.value.subject,
              let relationshipObject = listedRecord.value.object,
              case let .known(.identity(object)) = relationshipObject,
              object.did == appDID
        else { return nil }

        return subject
    }
}

private enum AppContributorsClientKey: DependencyKey {
    static var liveValue: AppContributorsClient { .live }

    static var testValue: AppContributorsClient {
        AppContributorsClient {
            throw AppContributorsClientError.unimplemented
        }
    }
}

public extension DependencyValues {
    var appContributors: AppContributorsClient {
        get { self[AppContributorsClientKey.self] }
        set { self[AppContributorsClientKey.self] = newValue }
    }
}

@Feature
public struct AboutOpenMusicEvent {
    public init() {}

    public enum Contributors: Equatable, Sendable {
        case failed
        case loaded([AppContribution])
        case loading
    }

    public struct State: Equatable {
        public init(
            eventID: OMERecord.Event.ID? = nil,
            sourceProvenance: EventSourceProvenanceRecord? = nil
        ) {
            self.eventID = eventID
            self.sourceProvenance = sourceProvenance
        }

        public var contributors: Contributors = .loading
        public let eventID: OMERecord.Event.ID?
        @Trigger public var loadContributors
        public let sourceProvenance: EventSourceProvenanceRecord?

        public var eventInformationProviderDescription: String {
            guard eventID != nil else {
                return "Event information is supplied by event organizers and their published sources. OpenMusicEvent displays that information but does not claim authorship of it."
            }
            guard let sourceProvenance else {
                return "No external source information is attached to this event. OpenMusicEvent cannot identify a published provider for it."
            }
            switch sourceProvenance.sourceKind {
            case .local:
                return "This event was created or imported locally. Its local source path is not shared here."
            case .tangled:
                return "This event information comes from the organizer-controlled Tangled source \(sourceProvenance.sourceReference)."
            }
        }
    }

    public enum Action {
        case retryButtonTapped
    }

    @Dependency(\.appContributors) var appContributors

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .retryButtonTapped:
                let loadContributors = state.loadContributors
                store.addTask {
                    try loadContributors()
                }
            }
        }
        .onMount { state in
            let loadContributors = state.loadContributors
            store.addTask {
                try loadContributors()
            }
        }
        .onTrigger(store.loadContributors) { state in
            state.contributors = .loading
            store.addTask {
                do {
                    let contributors = try await appContributors.load()
                    try store.modify {
                        $0.contributors = .loaded(contributors)
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try store.modify {
                        $0.contributors = .failed
                    }
                }
            }
        }
    }
}

public struct AboutOpenMusicEventView: View {
    public init(store: StoreOf<AboutOpenMusicEvent>) {
        self.store = store
    }

    let store: StoreOf<AboutOpenMusicEvent>

    public var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenMusicEvent")
                        .font(.title2.bold())
                    Text("An open-source app for discovering, following, and contributing to music events.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("OpenMusicEvent and the Atmosphere") {
                Text("OpenMusicEvent uses the open AT Protocol. Your account is a portable identity that can work across compatible apps, while public event information remains available without signing in.")

                PortableDisclosureGroup("Why does OpenMusicEvent offer accounts?") {
                    Text("OpenMusicEvent asks for an account only when an action needs your identity, such as publishing, collaborating, or participating in public feedback.")
                }

                PortableDisclosureGroup("What stays on this device?") {
                    Text("Local events, saved attendee state, preferences, caches, and unpublished workspaces stay on this device. Account credentials use platform-protected storage.")
                }

                PortableDisclosureGroup("What can become public?") {
                    Text("AT Protocol records, public feedback, and source proposals become public only when you explicitly submit them. Local drafts and saved schedules are not published automatically.")
                }

                PortableDisclosureGroup("Who provides the event information?") {
                    Text(store.eventInformationProviderDescription)
                }

                PortableDisclosureGroup("How can I inspect the source?") {
                    Text("OpenMusicEvent is open source. You can inspect the app's source code from the link below.")
                }
            }

            Section("Contributors") {
                switch store.contributors {
                case .loading:
                    HStack {
                        ProgressView()
                        Text("Loading contributors…")
                            .foregroundStyle(.secondary)
                    }

                case .failed:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Developer profile unavailable")
                        Button("Retry") {
                            store.send(.retryButtonTapped)
                        }
                    }

                case let .loaded(contributors):
                    if contributors.isEmpty {
                        Text("No developer profile is currently published.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(contributors) { contributor in
                            NavigationLink {
                                AppContributorProfileView(contributor: contributor)
                            } label: {
                                AppContributorRow(contributor: contributor)
                            }
                        }
                    }
                }
            }

            Section {
                AboutExternalLinkRow(
                    title: "Feedback Board",
                    destination: URL(string: "https://userinput.app/s/did:plc:42p4f3krv45gtkxjooaekbnw/3moixlle7bs25")!
                )
                AboutExternalLinkRow(
                    title: "Website",
                    destination: URL(string: "https://openmusicevent.app")!
                )
                AboutExternalLinkRow(
                    title: "Source code",
                    destination: URL(string: "https://tangled.org/woody.fm/openmusicevent")!
                )
            } header: {
                Text("Project")
            } footer: {
                if let versionDescription {
                    Text(versionDescription)
                }
            }
        }
        .navigationTitle("About OpenMusicEvent")
    }

    var versionDescription: String? {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        else { return nil }
        return "Version \(version) (\(build))"
    }
}

struct AppContributorRow: View {
    let contributor: AppContribution

    var body: some View {
        HStack(spacing: 12) {
            ContributorArtworkView(
                asset: contributor.avatarAsset,
                cacheContext: nil,
                size: 52
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(contributor.roleTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(contributor.displayName)
                if let handleText = contributor.handleText {
                    Text(handleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AppContributorProfileView: View {
    let contributor: AppContribution

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    ContributorArtworkView(
                        asset: contributor.avatarAsset,
                        cacheContext: nil,
                        size: 96
                    )
                    Text(contributor.displayName)
                        .font(.title2.bold())
                    if let handleText = contributor.handleText {
                        Text(handleText)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Role") {
                Text(contributor.roleTitle)
                Text("Attributed by openmusicevent.app")
                    .foregroundStyle(.secondary)
            }

            if let bio = contributor.bio {
                Section("About") {
                    Text(bio)
                }
            }
        }
        .navigationTitle(contributor.displayName)
    }
}

struct AboutExternalLinkRow: View {
    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
