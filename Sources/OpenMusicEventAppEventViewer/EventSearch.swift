import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import ScheduleComponents
import Sharing
import SQLiteData
import SwiftUITabFeatures
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

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
            self._timeZone = FetchOne(
                OMERecord.Event.timeZoneQuery(eventID: eventID)
            )
            self.destination = destination
            self.content = .dashboard(Self.emptyDashboard)
            _contributors = FetchAll(
                ContributorProfile.all(eventID: eventID, hydration: .none)
            )
            _event = FetchOne(
                OMERecord.Event.where { $0.id.eq(eventID) }
            )
            _performanceContributors = FetchAll(
                EventSearch.performanceContributorsQuery(eventID: eventID)
            )
            _performanceRows = FetchAll(
                PerformanceRow.all(eventID: eventID)
            )
            _scheduleViewerStates = FetchAll(
                ScheduleViewerState.forEvent(eventID: eventID)
            )
        }

        public let eventID: OMERecord.Event.ID
        @FetchOne public var timeZone: TimeZone?
        var eventTimePresentation: EventTimePresentation? {
            timeZone.map { EventTimePresentation(timeZone: $0) }
        }

        public var content: EventSearchContent

        @FetchAll var contributors: [ContributorProfile]
        @FetchOne var event: OMERecord.Event?
        @FetchAll var performanceContributors: [OMERecord.Performance.Contributors]
        @FetchAll var performanceRows: [PerformanceRow]
        @FetchAll var scheduleViewerStates: [ScheduleViewerState]

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
                        guard $0.eventID == eventID,
                              $0.query == query,
                              $0.content != content
                        else { return }
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
                    guard $0.eventID == eventID,
                          $0.query == query,
                          $0.content != content
                    else { return }
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
    @Environment(\.timeZone) var deviceTimeZone
    @Bindable var store: StoreOf<EventSearch>

    public init(store: StoreOf<EventSearch>) {
        self.store = store
    }

    @FocusState var searchFocus

    public var body: some View {
        NavigationStack {
            PeriodicTimelineView(every: 60) { currentDate in
                if let eventTimePresentation = store.state.eventTimePresentation {
                    EventSearchContentView(
                        content: store.content,
                        now: currentDate,
                        contributors: store.contributors,
                        event: store.event,
                        eventTimePresentation: eventTimePresentation,
                        timeZoneDisclosure: .whenDeviceClockDiffers(deviceTimeZone),
                        performanceContributors: store.performanceContributors,
                        performanceRows: store.performanceRows,
                        scheduleViewerStates: store.scheduleViewerStates,
                        openTarget: { store.send(.openTarget($0)) }
                    )
                    .task(id: currentDate) {
                        store.send(.timelineTick(currentDate))
                    }
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
    let event: OMERecord.Event?
    let eventTimePresentation: EventTimePresentation
    let timeZoneDisclosure: EventTimePresentation.Disclosure
    let performanceContributors: [OMERecord.Performance.Contributors]
    let performanceRows: [PerformanceRow]
    let scheduleViewerStates: [ScheduleViewerState]
    let openTarget: (EventSearchDocument.Target) -> Void

    var body: some View {
        switch content {
        case let .dashboard(dashboard):
            EventSearchDashboardView(
                dashboard: dashboard,
                now: now,
                contributors: contributors,
                event: event,
                eventTimePresentation: eventTimePresentation,
                timeZoneDisclosure: timeZoneDisclosure,
                performanceContributors: performanceContributors,
                scheduleViewerStates: scheduleViewerStates,
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
                    EventSearchResultRow(
                        result: result,
                        contributor: contributor(for: result),
                        performanceRow: performanceRow(for: result),
                        now: now,
                        eventTimePresentation: eventTimePresentation,
                        timeZoneDisclosure: timeZoneDisclosure
                    )
                }
                .navigationLinkListRowStyle()
            }
            .listStyle(.plain)
        }
    }

    func contributor(for result: EventSearchResult) -> ContributorProfile? {
        guard case let .contributor(contributorID) = result.document.target else { return nil }
        return contributors.first { $0.contributorID == contributorID }
    }

    func performanceRow(for result: EventSearchResult) -> PerformanceRow? {
        guard case let .performance(performanceID) = result.document.target else { return nil }
        return performanceRows.first { $0.performanceID == performanceID }
    }
}

struct EventSearchDashboardView: View {
    let dashboard: EventSearchDashboard
    let now: Date
    let contributors: [ContributorProfile]
    let event: OMERecord.Event?
    let eventTimePresentation: EventTimePresentation
    let timeZoneDisclosure: EventTimePresentation.Disclosure
    let performanceContributors: [OMERecord.Performance.Contributors]
    let scheduleViewerStates: [ScheduleViewerState]
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
                                showStageNameLabels: showStageNameLabels(for: row.stage),
                                eventTimePresentation: eventTimePresentation,
                                timeZoneDisclosure: timeZoneDisclosure,
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

    func showStageNameLabels(for stage: OMERecord.Stage) -> Bool {
        let division = ScheduleViewer.ScheduleDivision(category: stage.category)
        if let state = scheduleViewerStates.first(where: { $0.id.category == division.id }) {
            return state.showStageNameLabels
        }
        guard let category = stage.category else { return false }
        return event?.categoryConfigs?[category]?.showStageNameLabels ?? false
    }
}

struct EventSearchStageCard: View {
    let row: StageDashboardRow
    let now: Date
    let leadContributors: [OMERecord.ID<OMERecord.Performance>: ContributorProfile]
    let showStageNameLabels: Bool
    let eventTimePresentation: EventTimePresentation
    let timeZoneDisclosure: EventTimePresentation.Disclosure
    let openTarget: (EventSearchDocument.Target) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                PerformanceStageBubbleView(stage: row.stage, tint: stageColor)
                    .scaleEffect(46 / PerformanceContextIdentity.bubbleSize)
                    .frame(width: 46, height: 46)
                if showStageNameLabels {
                    Text(row.stage.name)
                        .font(.headline)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            if let performance = row.nowPlayingRows.first {
                performanceSection(title: "Now", performance: performance)
            }

            if let performance = row.comingNextRows.first {
                performanceSection(
                    title: "Up next",
                    performance: performance,
                    showsStartTime: true
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(stageColor.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(stageColor.opacity(0.22))
        }
        .opacity(isClosed ? 0.45 : 1)
        .portableContentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel(Text(accessibilityLabel))
        .onTapGesture {
            openTarget(.stage(row.stage.id.stageID))
        }
    }

    @ViewBuilder
    func performanceSection(
        title: String,
        performance: PerformanceDashboardRow,
        showsStartTime: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

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
                    if showsStartTime {
                        Text("Starts \(startTimeText(for: performance.performance.startTime))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        }
    }

    var stageColor: Color {
        row.stage.color.swiftUIColor
    }

    var isClosed: Bool {
        row.nowPlayingRows.isEmpty && row.comingNextRows.isEmpty
    }

    var accessibilityLabel: String {
        var parts = [row.stage.name]
        if let performance = row.nowPlayingRows.first {
            parts.append("Now, \(performance.title)")
        }
        if let performance = row.comingNextRows.first {
            parts.append(
                "Up next, \(performance.title), starts \(startTimeText(for: performance.performance.startTime))"
            )
        }
        return parts.joined(separator: ", ")
    }

    func startTimeText(for startTime: Date) -> String {
        eventTimePresentation.formattedTime(
            for: startTime,
            disclosure: timeZoneDisclosure
        )
    }
}

struct EventSearchFeatureCard: View {
    let feature: EventSearchFeature

    var body: some View {
        HStack(spacing: 10) {
            EventSearchChromeIcon(
                systemImage: feature.systemImage,
                tint: feature.tint
            )
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
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(tint ?? .accentColor)
                .frame(width: size, height: size)
            MappedSystemImage(systemName: systemImage)
                .frame(width: size * 0.5, height: size * 0.5)
                .foregroundStyle(.white)
        }
    }
}

struct EventSearchPerformanceRow: View {
    @Environment(\.dateTimeRangeResolutionPolicy) var dateTimeRangeResolutionPolicy
    @Environment(\.performanceReactionMenuContext) var reactionMenuContext
    let row: PerformanceRow
    let now: Date
    let eventTimePresentation: EventTimePresentation
    let timeZoneDisclosure: EventTimePresentation.Disclosure

    var body: some View {
        HStack(spacing: 8) {
            EventSearchRow(
                title: row.title,
                subtitle: eventTimePresentation.performanceRowTimeRange(
                    for: row.performance,
                    disclosure: timeZoneDisclosure
                ),
                secondarySubtitle: eventTimePresentation.daySegment(
                    for: row.performance.startTime,
                    policy: dateTimeRangeResolutionPolicy
                ),
                status: PerformanceTimingStatus(
                    startTime: row.performance.startTime,
                    endTime: row.performance.endTime,
                    now: now
                ),
                chrome: EventSearchPerformanceChrome(stage: row.stage)
            )

            PerformanceReactionSummaryWhenFits(
                performanceID: row.performance.id
            )
            .portableLayoutPriority(-1)
        }
        .contextMenu {
            PerformanceReactionMenuContent(
                performanceID: row.performance.id,
                context: reactionMenuContext
            )
        }
    }
}

struct EventSearchResultRow: View {
    let result: EventSearchResult
    let contributor: ContributorProfile?
    let performanceRow: PerformanceRow?
    let now: Date
    let eventTimePresentation: EventTimePresentation
    let timeZoneDisclosure: EventTimePresentation.Disclosure

    var body: some View {
        if let contributor {
            EventSearchRow(
                title: result.document.title,
                subtitle: result.document.subtitle ?? result.document.kind.title,
                chrome: ContributorArtworkView(
                    asset: contributor.artworkAsset,
                    cacheContext: contributor.artworkCacheContext,
                    size: 44
                )
            )
        } else if let performanceRow {
            EventSearchPerformanceRow(
                row: performanceRow,
                now: now,
                eventTimePresentation: eventTimePresentation,
                timeZoneDisclosure: timeZoneDisclosure
            )
        } else {
            EventSearchRow(
                title: result.document.title,
                subtitle: result.document.subtitle ?? result.document.kind.title,
                chrome: EventSearchChromeIcon(
                    systemImage: result.document.semanticSystemImage,
                    tint: result.document.semanticTint,
                    size: 44
                )
            )
        }
    }
}

struct EventSearchPerformanceChrome: View {
    let stage: OMERecord.Stage?

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(stage?.color.swiftUIColor ?? .secondary.opacity(0.35))
                .frame(width: 5, height: 44)

            Group {
                if let stage {
                    ScheduleStageIcon(stage: stage)
                } else {
                    MappedSystemImage(systemName: "music.note")
                        .padding(10)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .foregroundStyle(.primary)
        }
    }
}

struct EventSearchRow<Chrome: View>: View {
    let title: String
    let subtitle: String
    var secondarySubtitle: String?
    var status: PerformanceTimingStatus?
    let chrome: Chrome

    var body: some View {
        HStack(spacing: 10) {
            chrome

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(subtitle)
                        .lineLimit(1)
                        .portableLayoutPriority(1)

                    if let secondarySubtitle {
                        Text(secondarySubtitle)
                            .lineLimit(1)
                    }

                    if let status {
                        if case .startsIn = status {
                            Text("Starts in")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .portableLayoutPriority(1)
                        }

                        PerformanceTimingChip(status: status)
                            .portableLayoutPriority(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44, alignment: .leading)
        .foregroundStyle(.primary)
    }
}

private extension EventSearchDocument {
    var semanticSystemImage: String {
        guard case let .feature(featureID) = target else { return kind.systemImage }
        return EventSearchFeature.systemImage(for: featureID)
    }

    var semanticTint: Color? {
        guard case let .feature(featureID) = target else { return kind.tint }
        return EventSearchFeature.tint(for: featureID)
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

    var tint: Color? {
        switch self {
        case .channel: .orange
        case .contact: .green
        case .contributor: .pink
        case .eventInfo: .gray
        case .feature: nil
        case .location: .blue
        case .performance: .green
        case .poster: .purple
        case .stage: .indigo
        }
    }
}

private extension EventSearchFeature {
    var tint: Color? {
        Self.tint(for: id)
    }

    var systemImage: String {
        Self.systemImage(for: id)
    }

    static func tint(for id: ID) -> Color? {
        switch id {
        case EventSearchFeature.KnownID.schedule: .green
        case EventSearchFeature.KnownID.contributors: .pink
        case EventSearchFeature.KnownID.stages: .indigo
        case EventSearchFeature.KnownID.communications: .orange
        case EventSearchFeature.KnownID.location: .blue
        case EventSearchFeature.KnownID.contact: .green
        case EventSearchFeature.KnownID.posters: .purple
        case EventSearchFeature.KnownID.alerts: .red
        case EventSearchFeature.KnownID.about: .gray
        default: nil
        }
    }

    static func systemImage(for id: ID) -> String {
        switch id {
        case EventSearchFeature.KnownID.schedule: "calendar"
        case EventSearchFeature.KnownID.contributors: "person.3"
        case EventSearchFeature.KnownID.stages: "square.grid.2x2"
        case EventSearchFeature.KnownID.communications: "megaphone"
        case EventSearchFeature.KnownID.location: "mappin.and.ellipse"
        case EventSearchFeature.KnownID.contact: "phone"
        case EventSearchFeature.KnownID.posters: "photo.on.rectangle"
        case EventSearchFeature.KnownID.alerts: "bell"
        case EventSearchFeature.KnownID.about: "info.circle"
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
