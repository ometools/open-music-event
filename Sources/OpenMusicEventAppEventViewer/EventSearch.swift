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
            _contributors = FetchAll(
                ContributorProfile.all(eventID: eventID, hydration: .none)
            )
            _performanceContributors = FetchAll(
                EventSearch.performanceContributorsQuery(eventID: eventID)
            )
        }

        public let eventID: OMERecord.Event.ID

        public var content: EventSearchContent

        @FetchAll var contributors: [ContributorProfile]
        @FetchAll var performanceContributors: [OMERecord.Performance.Contributors]

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
            now: Date,
            db: Database
        ) throws -> EventSearchContent {
            guard let term = EventSearchTerm(rawValue: query) else {
                return .dashboard(try EventSearchDashboard.fetch(eventID: eventID, now: now, db: db))
            }

            let results = try EventSearchIndex.results(matching: term, in: eventID, db: db)
            return results.isEmpty ? .noResults : .results(results)
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case openTarget(EventSearchDocument.Target)
        case timelineTick(Date)
    }

    @Feature
    public enum Destination {
        case contributorDetail(Spawn<ContributorDetail>)
        case performanceDetail(Spawn<PerformanceDetail>)
        case stageDetail(Spawn<StageDetail>)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now
    @StoreTaskID var searchTask

    static func performanceContributorsQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Performance.Contributors> {
        OMERecord.Performance.Contributors
            .where { $0.performanceID.organizerID.eq(eventID.organizerID) }
            .where { $0.performanceID.eventID.eq(eventID.eventID) }
            .order { ($0.performanceID.performanceID, $0.sortIndex) }
    }

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

            case let .timelineTick(now):
                guard EventSearchTerm(rawValue: state.query) == nil else { return }
                let eventID = state.eventID
                let query = state.query
                store.addTask(id: searchTask) {
                    let content = try database.read { db in
                        try State.content(eventID: eventID, query: query, now: now, db: db)
                    }
                    try store.modify {
                        guard $0.eventID == eventID, $0.query == query else { return }
                        $0.content = content
                    }
                }
            }
        }
        .onChange(of: store.query, initial: true) { _, query, state in
            let eventID = state.eventID
            let currentDate = now
            store.addTask(id: searchTask) {
                let content = try database.read { db in
                    try State.content(eventID: eventID, query: query, now: currentDate, db: db)
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
            TimelineView(.periodic(from: Date.now, by: 1)) { context in
                EventSearchContentView(
                    content: store.content,
                    now: context.date,
                    contributors: store.contributors,
                    performanceContributors: store.performanceContributors,
                    openTarget: { store.send(.openTarget($0)) }
                )
                .task(id: context.date) {
                    store.send(.timelineTick(context.date))
                }
            }
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
    let now: Date
    let contributors: [ContributorProfile]
    let performanceContributors: [OMERecord.Performance.Contributors]
    let openTarget: (EventSearchDocument.Target) -> Void

    var body: some View {
        switch content {
        case let .dashboard(dashboard):
            EventSearchDashboardView(
                dashboard: dashboard,
                now: now,
                contributors: contributors,
                performanceContributors: performanceContributors,
                openTarget: openTarget
            )

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
    let dashboard: EventSearchDashboard
    let now: Date
    let contributors: [ContributorProfile]
    let performanceContributors: [OMERecord.Performance.Contributors]
    let openTarget: (EventSearchDocument.Target) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !dashboard.stageRows.isEmpty {
                    Text("At the stages")
                        .font(.title2.weight(.bold))

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16),
                        ],
                        spacing: 16
                    ) {
                        ForEach(dashboard.stageRows) { row in
                            EventSearchStageCard(
                                row: row,
                                now: now,
                                leadContributors: leadContributors,
                                openTarget: openTarget
                            )
                        }
                    }
                }

                if !dashboard.featureRows.isEmpty {
                    Text("Explore")
                        .font(.title2.weight(.bold))

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ],
                        spacing: 12
                    ) {
                        ForEach(dashboard.featureRows) { row in
                            Button {
                                openTarget(.feature(row.feature.id))
                            } label: {
                                EventSearchFeatureCard(feature: row.feature)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.secondary.opacity(0.04))
    }

    var leadContributors: [OMERecord.ID<OMERecord.Performance>: ContributorProfile] {
        let contributorsByID = Dictionary(
            uniqueKeysWithValues: contributors.map { ($0.contributorID, $0) }
        )
        let primaryContributors = performanceContributors
            .filter { $0.billing == .primary }
            .sorted { lhs, rhs in
                if lhs.performanceID.performanceID == rhs.performanceID.performanceID {
                    return lhs.sortIndex < rhs.sortIndex
                }
                return lhs.performanceID.performanceID < rhs.performanceID.performanceID
            }

        return Dictionary(
            primaryContributors.compactMap { contribution in
                contribution.contributorID.flatMap { contributorID in
                    contributorsByID[contributorID].map { (contribution.performanceID.performanceID, $0) }
                }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

struct EventSearchStageCard: View {
    let row: StageDashboardRow
    let now: Date
    let leadContributors: [OMERecord.ID<OMERecord.Performance>: ContributorProfile]
    let openTarget: (EventSearchDocument.Target) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                PerformanceStageBubbleView(stage: row.stage, tint: stageColor)
                    .frame(width: 52, height: 52)
                Text(row.stage.name)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            if let performance = row.nowPlayingRows.first {
                performanceSection(title: "Now", performance: performance)
            }

            performanceSection(
                title: "Up next",
                performance: row.comingNextRows.first
            )
        }
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(stageColor.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(stageColor.opacity(0.22))
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            openTarget(.stage(row.stage.id.stageID))
        }
    }

    @ViewBuilder
    func performanceSection(
        title: String,
        performance: PerformanceDashboardRow?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let performance {
                HStack(spacing: 10) {
                    if let contributor = leadContributors[performance.performanceID],
                       let asset = contributor.artworkAsset {
                        ContributorArtworkView(
                            asset: asset,
                            cacheContext: contributor.artworkCacheContext,
                            size: 54
                        )
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(performance.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        PerformanceTimingChip(
                            status: PerformanceTimingStatus(
                                startTime: performance.performance.startTime,
                                endTime: performance.performance.endTime,
                                now: now
                            )
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("No next set announced")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var stageColor: Color {
        row.stage.color.swiftUIColor
    }
}

struct EventSearchFeatureCard: View {
    let feature: EventSearchFeature

    var body: some View {
        HStack(spacing: 10) {
            EventSearchChromeIcon(systemImage: feature.systemImage, tint: feature.tint)
            Text(feature.title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        }
    }
}

struct EventSearchChromeIcon: View {
    let systemImage: String
    let tint: Color?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint ?? .accentColor)
                .frame(width: 28, height: 28)
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

struct EventSearchPerformanceRow: View {
    let row: PerformanceDashboardRow
    let now: Date

    var body: some View {
        EventSearchRow(
            title: row.title,
            subtitle: row.stage?.name ?? "Performance",
            systemImage: "music.mic",
            status: PerformanceTimingStatus(
                startTime: row.performance.startTime,
                endTime: row.performance.endTime,
                now: now
            )
        )
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
    var status: PerformanceTimingStatus?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let status {
                        PerformanceTimingChip(status: status)
                            .layoutPriority(1)
                    }
                }
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
    var tint: Color? {
        switch id {
        case KnownID.schedule: .green
        case KnownID.contributors: .pink
        case KnownID.stages: .indigo
        case KnownID.communications: .orange
        case KnownID.location: .blue
        case KnownID.contact: .green
        case KnownID.posters: .purple
        case KnownID.alerts: .red
        case KnownID.about: .gray
        default: nil
        }
    }

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
