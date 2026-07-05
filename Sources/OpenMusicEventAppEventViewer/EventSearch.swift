import ComposableArchitecture2
import Dependencies
import OpenMusicEventDatabase
import SQLiteData
import SwiftUITabFeatures
import SwiftUI

public enum EventSearchContent: Equatable, Sendable {
    case dashboard(EventSearchDashboard)
    case noResults
    case results([EventSearchResult])
}

@Feature
public struct EventSearch {
    public init() {}

    public struct State {
        public init(
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            self.content = .dashboard(Self.emptyDashboard)
        }

        public let eventID: OMERecord.Event.ID

        public var content: EventSearchContent

        public var query = ""

        public var destination: Destination.State?

        public static func route(
            eventID: OMERecord.Event.ID,
            target: EventTarget?
        ) -> Self {
            switch target {
            case let .contributor(contributorID):
                return .init(
                    eventID: eventID,
                    destination: .contributorDetail(
                        Spawn(.init(contributorID: contributorID, eventID: eventID))
                    )
                )
            case let .stage(stageID):
                return .init(
                    eventID: eventID,
                    destination: .stageDetail(
                        Spawn(.init(stageID: stageID, eventID: eventID))
                    )
                )
            default:
                return .init(eventID: eventID)
            }
        }

        static var emptyDashboard: EventSearchDashboard {
            EventSearchDashboard(
                stageRows: [],
                featureRows: EventSearchFeature.indexedFeatures.map(FeatureShortcutRow.init(feature:)),
                channelRows: []
            )
        }

        static func content(
            eventID: OMERecord.Event.ID,
            query: String,
            db: Database
        ) throws -> EventSearchContent {
            guard let term = EventSearchTerm(rawValue: query) else {
                return .dashboard(try EventSearchDashboard.fetch(eventID: eventID, db: db))
            }

            let results = try EventSearchIndex.results(matching: term, in: eventID, db: db)
            return results.isEmpty ? .noResults : .results(results)
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case openTarget(EventSearchDocument.Target)
    }

    @Feature
    public enum Destination {
        case contributorDetail(Spawn<ContributorDetail>)
        case performanceDetail(Spawn<PerformanceDetail>)
        case stageDetail(Spawn<StageDetail>)
    }

    @Dependency(\.defaultDatabase) var database
    @StoreTaskID var searchTask

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case let .openTarget(target):
                let eventID = state.eventID
                switch target {
                case .channel(_):
                    store.addTask {
                        try store.post(
                            key: NavigationRequested.self,
                            value: .event(eventID, .communications)
                        )
                    }

                case let .contributor(contributorID):
                    store.withDependencies {
                        state.destination = .contributorDetail(
                            Spawn(.init(contributorID: contributorID, eventID: eventID))
                        )
                    }

                case let .feature(featureID):
                    guard let target = EventTarget(featureID: featureID) else { return }
                    store.addTask {
                        try store.post(
                            key: NavigationRequested.self,
                            value: .event(eventID, target)
                        )
                    }

                case let .performance(performanceID):
                    store.withDependencies {
                        state.destination = .performanceDetail(
                            Spawn(.init(performanceID: performanceID, eventID: eventID))
                        )
                    }

                case .poster(_):
                    store.addTask {
                        try store.post(
                            key: NavigationRequested.self,
                            value: .event(eventID, .posters)
                        )
                    }

                case let .stage(stageID):
                    store.withDependencies {
                        state.destination = .stageDetail(
                            Spawn(.init(stageID: stageID, eventID: eventID))
                        )
                    }
                }
            }
        }
        .onChange(of: store.query, initial: true) { _, query, state in
            let eventID = state.eventID
            store.addTask(id: searchTask) {
                let content = try database.read { db in
                    try State.content(eventID: eventID, query: query, db: db)
                }
                try store.modify {
                    guard $0.eventID == eventID, $0.query == query else { return }
                    $0.content = content
                }
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct EventSearchView: View {
    @Bindable var store: StoreOf<EventSearch>

    public init(store: StoreOf<EventSearch>) {
        self.store = store
    }

    @FocusState var searchFocus

    public var body: some View {
        NavigationStack {
            EventSearchContentView(
                content: store.content,
                openTarget: { store.send(.openTarget($0)) }
            )
            .navigationTitle("Search")
            .navigationDestination(item: $store.scope(\.destination, action: \.destination).contributorDetail) { detailStore in
                ContributorDetailView(store: detailStore)
            }
            .navigationDestination(item: $store.scope(\.destination, action: \.destination).performanceDetail) { detailStore in
                PerformanceDetailView(store: detailStore)
            }
            .navigationDestination(item: $store.scope(\.destination, action: \.destination).stageDetail) { detailStore in
                StageDetailView(store: detailStore)
            }
        }
        .searchable(text: $store.query, prompt: "Search this event")
    }
}

struct EventSearchContentView: View {
    let content: EventSearchContent
    let openTarget: (EventSearchDocument.Target) -> Void

    var body: some View {
        switch content {
        case let .dashboard(dashboard):
            EventSearchDashboardView(dashboard: dashboard, openTarget: openTarget)

        case .noResults:
            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass"
            )

        case let .results(results):
            List(results) { result in
                Button {
                    openTarget(result.document.target)
                } label: {
                    EventSearchResultRow(result: result)
                }
                .navigationLinkListRowStyle()
            }
            .listStyle(.plain)
        }
    }
}

struct EventSearchDashboardView: View {
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    let dashboard: EventSearchDashboard
    let openTarget: (EventSearchDocument.Target) -> Void

    var body: some View {
        List {
            if needsStageDisambiguation, !dashboard.stageRows.isEmpty {
                Section("Stages") {
                    ForEach(dashboard.stageRows) { row in
                        Button {
                            openTarget(.stage(row.stage.id.stageID))
                        } label: {
                            EventSearchRow(
                                title: row.stage.name,
                                subtitle: "Stage",
                                systemImage: "square.grid.2x2"
                            )
                        }
                        .navigationLinkListRowStyle()
                    }
                }
            }

            if !dashboard.featureRows.isEmpty {
                Section("Features") {
                    ForEach(dashboard.featureRows) { row in
                        Button {
                            openTarget(.feature(row.feature.id))
                        } label: {
                            EventSearchRow(
                                title: row.feature.title,
                                subtitle: row.feature.subtitle,
                                systemImage: row.feature.systemImage
                            )
                        }
                        .navigationLinkListRowStyle()
                    }
                }
            }

            if !dashboard.channelRows.isEmpty {
                Section("Channels") {
                    ForEach(dashboard.channelRows) { row in
                        Button {
                            openTarget(.channel(row.channel.id.channelID))
                        } label: {
                            EventSearchRow(
                                title: row.channel.name,
                                subtitle: "Comms",
                                systemImage: "megaphone"
                            )
                        }
                        .navigationLinkListRowStyle()
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

struct EventSearchResultRow: View {
    let result: EventSearchResult

    var body: some View {
        EventSearchRow(
            title: result.document.title,
            subtitle: result.document.subtitle ?? result.document.kind.title,
            systemImage: result.document.kind.systemImage
        )
    }
}

struct EventSearchRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
    }
}

private extension EventSearchDocument.Kind {
    var systemImage: String {
        switch self {
        case .channel: "megaphone"
        case .contact: "phone"
        case .contributor: "person"
        case .eventInfo: "info.circle"
        case .feature: "square.grid.2x2"
        case .location: "mappin.and.ellipse"
        case .performance: "music.mic"
        case .poster: "photo.on.rectangle"
        case .stage: "square.grid.2x2"
        }
    }

    var title: String {
        switch self {
        case .channel: "Comms"
        case .contact: "Contact"
        case .contributor: "Contributor"
        case .eventInfo: "About"
        case .feature: "Feature"
        case .location: "Location"
        case .performance: "Performance"
        case .poster: "Poster"
        case .stage: "Stage"
        }
    }
}

private extension EventSearchFeature {
    var systemImage: String {
        switch id {
        case KnownID.schedule: "calendar"
        case KnownID.contributors: "person.3"
        case KnownID.stages: "square.grid.2x2"
        case KnownID.communications: "megaphone"
        case KnownID.location: "mappin.and.ellipse"
        case KnownID.contact: "phone"
        case KnownID.posters: "photo.on.rectangle"
        case KnownID.alerts: "bell"
        case KnownID.about: "info.circle"
        default: "square.grid.2x2"
        }
    }
}

private extension EventTarget {
    init?(featureID: EventSearchFeature.ID) {
        switch featureID {
        case EventSearchFeature.KnownID.schedule:
            self = .schedule
        case EventSearchFeature.KnownID.contributors:
            self = .contributors
        case EventSearchFeature.KnownID.stages:
            self = .stages
        case EventSearchFeature.KnownID.communications:
            self = .communications
        case EventSearchFeature.KnownID.location:
            self = .location
        case EventSearchFeature.KnownID.contact:
            self = .contactInfo
        case EventSearchFeature.KnownID.posters:
            self = .posters
        case EventSearchFeature.KnownID.alerts:
            self = .notifications
        case EventSearchFeature.KnownID.about:
            self = .about
        default:
            return nil
        }
    }
}
