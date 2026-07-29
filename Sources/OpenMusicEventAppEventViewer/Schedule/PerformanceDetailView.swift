import BlueskyActorCache
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventEditors
import OpenMusicEventImages
import OpenMusicEventViewers
import Sharing
import SQLiteData
import SwiftUI
import Tagged

@Feature
public struct PerformanceDetail {
    public init() {}

    public struct State: Identifiable {
        public init(
            performanceID: OMERecord.ID<OMERecord.Performance>,
            eventID: OMERecord.Event.ID? = nil
        ) {
            @Dependency(\.defaultEventID) var defaultEventID
            @Dependency(\.defaultEventTimeZone) var defaultEventTimeZone

            self.eventID = eventID ?? defaultEventID
            self.performanceID = performanceID
            self.timeZone = defaultEventTimeZone
            self._eventViewerState = Shared(.eventViewerState(self.eventID))
            _contributors = FetchAll(
                PerformanceDetail.contributorsQuery(
                    performanceID: performanceID,
                    eventID: self.eventID,
                    hydration: .bskyActorProfile
                )
            )
            _performance = FetchOne(
                PerformanceDetail.performanceQuery(
                    performanceID: performanceID,
                    eventID: self.eventID
                )
            )
            _performanceContributors = FetchAll(
                EditPerformance.performanceContributorsQuery(
                    performanceID: performanceID,
                    eventID: self.eventID
                )
            )
            _schedules = FetchAll(
                ScheduleViewer.schedulesQuery(eventID: self.eventID)
            )
            _stages = FetchAll(
                ScheduleViewer.stagesQuery(eventID: self.eventID)
            )
            let fullPerformanceID = OMERecord.Performance.ID(
                organizerID: self.eventID.organizerID,
                eventID: self.eventID.eventID,
                performanceID: performanceID
            )
            _reactions = FetchAll(
                PerformanceReaction.forPerformance(performanceID: fullPerformanceID)
            )
            _reactionUsage = FetchAll(
                PerformanceReactionEmojiUsage.ranked
            )
            _userSchedules = FetchAll(
                UserSchedule.all(eventID: self.eventID)
            )
            _userSchedulePerformances = FetchAll(
                UserSchedule.Performance.all
            )
        }

        public let eventID: OMERecord.Event.ID
        public let performanceID: OMERecord.ID<OMERecord.Performance>
        @DebugSnapshotIgnored
        public let timeZone: TimeZone

        @FetchAll var contributors: [ContributorProfile]
        public var destination: Destination.State?
        @Shared public var eventViewerState: EventViewerState
        @FetchOne public var performance: OMERecord.Performance?
        @FetchAll var performanceContributors: [OMERecord.Performance.Contributors]
        @FetchAll public var schedules: [OMERecord.Schedule]
        @FetchAll public var stages: [OMERecord.Stage]
        @FetchAll public var reactions: [PerformanceReaction]
        @FetchAll public var reactionUsage: [PerformanceReactionEmojiUsage]
        @FetchAll public var userSchedules: [UserSchedule]
        @FetchAll public var userSchedulePerformances: [UserSchedule.Performance]

        public var userScheduleOverlay: UserScheduleOverlay {
            UserScheduleOverlay(
                schedules: userSchedules,
                memberships: userSchedulePerformances,
                selectedScheduleID: eventViewerState.selectedUserScheduleID
            )
        }

        public var id: OMERecord.ID<OMERecord.Performance> { performanceID }

        public var fullPerformanceID: OMERecord.Performance.ID {
            OMERecord.Performance.ID(
                organizerID: eventID.organizerID,
                eventID: eventID.eventID,
                performanceID: performanceID
            )
        }

        public var canEditPerformance: Bool {
            performance != nil && schedule != nil
        }

        public var schedule: OMERecord.Schedule? {
            guard let scheduleID = performance?.scheduleID else { return nil }
            return schedules.first { $0.id.scheduleID == scheduleID }
        }

        public var stage: OMERecord.Stage? {
            guard let performance else { return nil }
            return stages.first { $0.id.stageID == performance.stageID }
        }

        var actorProfileLoadRequests: [ContributorProfile.ActorProfileLoadRequest] {
            contributors.actorProfileLoadRequests
        }

        var displayedContributors: [ContributorProfile] {
            displayedContributorCredits.map(\.profile)
        }

        var displayedContributorCredits: [ContributorCredit] {
            orderedContributorCredits(for: .primary)
                + orderedContributorCredits(for: .supporting)
                + unorderedContributorCredits
        }

        var headlineContributors: [ContributorProfile] {
            let primaryContributors = orderedContributorCredits(for: .primary).map(\.profile)
            return primaryContributors.isEmpty
                ? displayedContributors
                : primaryContributors
        }

        private var unorderedContributorCredits: [ContributorCredit] {
            let orderedIDs = Set(
                performanceContributors.compactMap(\.contributorID)
            )
            return contributors
                .filter { !orderedIDs.contains($0.contributorID) }
                .map { ContributorCredit(profile: $0, performanceContributor: nil) }
        }

        private func orderedContributorCredits(
            for billing: OMERecord.Performance.Contributors.Billing
        ) -> [ContributorCredit] {
            let contributorsByID = Dictionary(
                uniqueKeysWithValues: contributors.map { ($0.contributorID, $0) }
            )
            return performanceContributors
                .filter { $0.billing == billing }
                .compactMap { performanceContributor in
                    performanceContributor.contributorID
                        .flatMap { contributorsByID[$0] }
                        .map {
                            ContributorCredit(
                                profile: $0,
                                performanceContributor: performanceContributor
                            )
                        }
                }
        }

        struct ContributorCredit: Identifiable {
            var profile: ContributorProfile
            var performanceContributor: OMERecord.Performance.Contributors?

            var id: OMERecord.Contributor.ID {
                profile.id
            }

            var contributorID: OMERecord.ID<OMERecord.Contributor> {
                profile.contributorID
            }

            var roleTitle: String? {
                guard let performanceContributor else { return nil }
                return performanceContributor.role?.displayTitle ?? "Performer"
            }
        }
    }

    public enum Action {
        case contributorButtonTapped(OMERecord.ID<OMERecord.Contributor>)
        case destination(Destination.Action)
        case editButtonTapped
        case otherReactionButtonTapped
        case reactionButtonTapped(PerformanceReaction.Emoji)
        case newUserScheduleButtonTapped
        case userScheduleMembershipButtonTapped(UserSchedule.ID)
    }

    @Feature
    public enum Destination {
        case contributorDetail(Spawn<ContributorDetail>)
        case reactionEntry(PerformanceReactionEntry)
        case userScheduleForm(Spawn<UserScheduleForm>)
    }

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.uuid) var uuid

    static func contributorsQuery(
        performanceID: OMERecord.ID<OMERecord.Performance>,
        eventID: OMERecord.Event.ID,
        hydration: ContributorProfile.Hydration = .none
    ) -> some Statement<ContributorProfile> {
        ContributorProfile.forPerformance(
            performanceID: performanceID,
            eventID: eventID,
            hydration: hydration
        )
    }

    static func performanceQuery(
        performanceID: OMERecord.ID<OMERecord.Performance>,
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Performance> {
        OMERecord.Performance
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.id.performanceID.eq(performanceID) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case let .contributorButtonTapped(contributorID):
                guard state.displayedContributors.contains(where: { $0.contributorID == contributorID }) else {
                    return
                }
                store.withDependencies {
                    state.destination = .contributorDetail(
                        Spawn(
                            ContributorDetail.State(
                                contributorID: contributorID,
                                eventID: state.eventID
                            )
                        )
                    )
                }

            case .destination:
                break

            case .editButtonTapped:
                guard state.performance != nil,
                      state.schedule != nil
                else { return }
                let eventID = state.eventID
                let performanceID = state.performanceID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .editPerformance(
                            eventID: eventID,
                            performanceID: performanceID
                        )
                    )
                    await task?.value
                }

            case .otherReactionButtonTapped:
                state.destination = .reactionEntry(
                    PerformanceReactionEntry.State(
                        performanceID: state.fullPerformanceID
                    )
                )

            case let .reactionButtonTapped(emoji):
                let performanceID = state.fullPerformanceID
                let id = uuid()
                let date = now
                store.addTask {
                    do {
                        try await database.write { db in
                            try PerformanceReaction.toggle(
                                performanceID: performanceID,
                                emoji: emoji,
                                id: id,
                                date: date,
                                in: db
                            )
                        }
                    } catch {
                        reportIssue(error)
                    }
                }

            case .newUserScheduleButtonTapped:
                guard state.performance != nil else { return }
                state.destination = .userScheduleForm(
                    Spawn(
                        UserScheduleForm.State(
                            eventID: state.eventID,
                            performanceID: state.performanceID
                        )
                    )
                )

            case let .userScheduleMembershipButtonTapped(scheduleID):
                guard state.performance != nil,
                      state.userSchedules.contains(where: { $0.id == scheduleID })
                else { return }
                let membership = UserSchedule.Performance(
                    scheduleID: scheduleID,
                    performanceID: state.performanceID
                )
                let isMember = state.userSchedulePerformances.contains { $0.id == membership.id }
                store.addTask {
                    do {
                        try await database.write { db in
                            if isMember {
                                try UserSchedule.Performance.find(membership.id).delete().execute(db)
                            } else {
                                try UserSchedule.Performance.insert { membership }.execute(db)
                            }
                        }
                    } catch {
                        reportIssue(error)
                    }
                }
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .onChange(of: store.actorProfileLoadRequests, initial: true) { _, requests, _ in
            guard !requests.isEmpty else { return }

            store.addTask {
                for request in requests {
                    do {
                        _ = try await blueskyActorProfileCache.refreshProfileIfNeeded(
                            request.actor.description,
                            24 * 60 * 60,
                            15 * 60
                        )
                    } catch is CancellationError {
                        return
                    } catch {
                    }
                }
            }
        }
    }
}

public struct PerformanceDetailView: View {
    @Bindable var store: StoreOf<PerformanceDetail>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<PerformanceDetail>,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        Group {
            if let performance = store.performance {
                HeroImageList(title: Text(performance.title)) {
                    PerformanceHeroView(
                        performance: performance,
                        stage: store.stage,
                        contributors: store.headlineContributors
                    )
                } content: {
                    PerformanceSummaryRow(
                        performance: performance,
                        stage: store.stage,
                        contributors: store.headlineContributors,
                        timeZone: store.timeZone
                    )

                    Section {
                        Menu {
                            PerformanceReactionMenuContent(
                                performanceID: store.fullPerformanceID,
                                context: reactionMenuContext
                            )
                        } label: {
                            Text("React")
                        }
                        .accessibilityLabel("React to this performance")
                    }

                    if let description = performance.displayDescription {
                        Section("About") {
                            Text(description)
                        }

                    }

                    if !performance.recordings.isEmpty {
                        Section("Recordings") {
                            ForEach(Array(performance.recordings.enumerated()), id: \.offset) { _, recording in
                                PerformanceRecordingRow(recording: recording)
                            }
                        }
                    }

                    if !store.displayedContributors.isEmpty {
                        Section("Contributors") {
                            ForEach(store.displayedContributorCredits) { credit in
                                Button {
                                    store.send(.contributorButtonTapped(credit.contributorID))
                                } label: {
                                    ContributorsRowView(
                                        profile: credit.profile,
                                        subtitle: credit.roleTitle
                                    )
                                }
                                .navigationLinkListRowStyle()
                            }
                        }
                    }

                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        PerformanceUserScheduleMenu(store: store)
                    }
                    if showsAuthoringControls {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                store.send(.editButtonTapped)
                            } label: {
                                Label("Edit Performance", systemImage: "pencil")
                                    .labelStyle(.iconOnly)
                            }
                            .disabled(!store.canEditPerformance)
                        }
                    }
                }
            } else {
                Group {
                    if showsTechnicalDetails {
                        ContentUnavailableView(
                            "Performance",
                            systemImage: "music.mic",
                            description: Text(verbatim: store.performanceID.rawValue.rawValue)
                        )
                    } else {
                        ContentUnavailableView("Performance unavailable", systemImage: "music.mic")
                    }
                }
                .navigationTitle("Performance")
            }
        }
        .navigationDestination(item: $store.scope(\.destination, action: \.destination).contributorDetail) { detailStore in
            ContributorDetailView(
                store: detailStore,
                showsAuthoringControls: showsAuthoringControls
            )
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).reactionEntry) { entryStore in
            PerformanceReactionEntryView(store: entryStore)
        }
        .navigationDestination(item: $store.scope(\.destination, action: \.destination).userScheduleForm) { formStore in
            UserScheduleFormView(store: formStore)
        }
    }

    var reactionMenuContext: PerformanceReactionMenuContext {
        PerformanceReactionMenuContext(
            reactions: store.reactions,
            usage: store.reactionUsage,
            toggle: { _, emoji in
                store.send(.reactionButtonTapped(emoji))
            },
            showOther: { _ in
                store.send(.otherReactionButtonTapped)
            }
        )
    }
}

public struct PerformanceUserScheduleMenu: View {
    @Bindable var store: StoreOf<PerformanceDetail>

    public init(store: StoreOf<PerformanceDetail>) {
        self.store = store
    }

    public var body: some View {
        Menu {
            if let selectedSchedule = store.state.userScheduleOverlay.selectedSchedule {
                membershipButton(schedule: selectedSchedule)
                Divider()
            }

            ForEach(store.userSchedules) { schedule in
                membershipButton(schedule: schedule)
            }

            Button {
                store.send(.newUserScheduleButtonTapped)
            } label: {
                Label("Add to a new schedule", systemImage: "plus")
            }
        } label: {
            Label("Personal Schedules", systemImage: "calendar")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Personal schedules")
    }

    @ViewBuilder
    func membershipButton(schedule: UserSchedule) -> some View {
        let isMember = store.state.userScheduleOverlay.contains(
            performanceID: store.performanceID,
            in: schedule.id
        )
        Button {
            store.send(.userScheduleMembershipButtonTapped(schedule.id))
        } label: {
            Label(
                "\(isMember ? "Remove from" : "Add to") \(schedule.title)",
                systemImage: isMember ? "checkmark-circle" : "calendar"
            )
        }
    }
}

struct PerformanceHeroView: View {
    let performance: OMERecord.Performance
    let stage: OMERecord.Stage?
    let contributors: [ContributorProfile]

    var body: some View {
        let summary = PerformanceDetailSummary(
            stage: stage,
            contributors: contributors
        )

        HeroImage(
            title: Text(performance.title),
            sources: stage?.heroImageSources ?? [],
            titleSources: [.title],
            tint: summary.tint
        ) {
            PerformanceHeroPlaceholder(
                performance: performance,
                stage: stage
            )
        }
    }
}

struct PerformanceSummaryRow: View {
    @Environment(\.dateTimeRangeResolutionPolicy) var dateTimeRangeResolutionPolicy
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    let performance: OMERecord.Performance
    let stage: OMERecord.Stage?
    let contributors: [ContributorProfile]
    let timeZone: TimeZone

    var body: some View {
        let summary = PerformanceDetailSummary(
            stage: stage,
            contributors: contributors
        )

        VStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 4) {
                PerformanceContextIdentity(
                    title: summary.artistSummary,
                    content: .contributor(
                        summary.featuredContributor,
                        fallbackTitle: summary.featuredContributor?.name ?? summary.artistSummary
                    ),
                    tint: summary.tint,
                    placement: .leading
                )
                .frame(alignment: .leading)

                VStack(spacing: 2) {
                    Text(
                        ScheduleViewer.performanceRowTimeRange(for: performance, timeZone: timeZone)
                    )
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .layoutPriority(1)
                    #if os(iOS)
                    .minimumScaleFactor(0.55)
                    #endif

                    TimelineView(.periodic(from: Date.now, by: 1)) { context in
                        PerformanceTimingChip(
                            startTime: performance.startTime,
                            endTime: performance.endTime,
                            now: context.date
                        )
                        .layoutPriority(1)
                    }

                    Text(
                        ScheduleViewer.daySegment(
                            for: performance.startTime,
                            timeZone: timeZone,
                            policy: dateTimeRangeResolutionPolicy
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .center)

                if needsStageDisambiguation {
                    PerformanceContextIdentity(
                        title: summary.stageTitle,
                        content: .stage(stage),
                        tint: summary.tint,
                        placement: .trailing
                    )
                    .frame(alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct PerformanceDetailSummary {
    let stage: OMERecord.Stage?
    let contributors: [ContributorProfile]

    var tint: Color {
        stage?.color.swiftUIColor ?? .accentColor
    }

    var featuredContributor: ContributorProfile? {
        contributors.first { $0.logoAsset != nil }
            ?? contributors.first { $0.artworkAsset != nil }
            ?? contributors.first
    }

    var stageTitle: String {
        stage?.name ?? "Stage TBA"
    }

    var artistSummary: String {
        switch contributors.count {
        case 0:
            return "Lineup TBA"
        case 1:
            return contributors[0].name
        case 2:
            return "\(contributors[0].name) / \(contributors[1].name)"
        default:
            return "\(contributors[0].name) + \(contributors.count - 1) more"
        }
    }
}

private extension OMERecord.Performance.Contributors.Role {
    var displayTitle: String {
        let role = OMERecord.Relationship.Role(rawValue)
        let selection = EditPerformance.State.RelationshipRoleSelection(role: role)
        return selection == .custom
            ? rawValue.identifierDisplayTitle
            : selection.title
    }
}

private extension String {
    var identifierDisplayTitle: String {
        let spaced = replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
        return spaced
            .split(separator: " ")
            .map { word in
                word.uppercased() == "DJ"
                    ? "DJ"
                    : word.prefix(1).uppercased() + String(word.dropFirst())
            }
            .joined(separator: " ")
    }
}

struct PerformanceContextIdentity: View {
    static let bubbleSize: CGFloat = 70
    static let itemWidth: CGFloat = 96
    static let labelHeight: CGFloat = 36

    enum Content {
        case contributor(ContributorProfile?, fallbackTitle: String)
        case stage(OMERecord.Stage?)
    }

    enum Placement {
        case leading
        case trailing
    }

    let title: String
    let content: Content
    let tint: Color
    let placement: Placement

    var body: some View {
        VStack(spacing: 4) {
            bubbleSlot
            titleLabel
        }
        .frame(width: Self.itemWidth)
        .frame(alignment: frameAlignment)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    var bubbleSlot: some View {
        switch content {
        case let .contributor(contributor, fallbackTitle):
            PerformanceArtistBubbleView(
                contributor: contributor,
                fallbackTitle: fallbackTitle,
                tint: tint
            )
            .frame(width: Self.bubbleSize, height: Self.bubbleSize)
            .accessibilityHidden(true)

        case let .stage(stage):
            PerformanceStageBubbleView(stage: stage, tint: tint)
                .frame(width: Self.bubbleSize, height: Self.bubbleSize)
                .accessibilityHidden(true)
        }
    }

    var titleLabel: some View {
        Text(title)
            .font(.caption)
            .lineLimit(2)
            #if os(iOS)
            .minimumScaleFactor(0.78)
            #endif
            .multilineTextAlignment(.center)
            .frame(width: Self.itemWidth, height: Self.labelHeight, alignment: .top)
    }

    var frameAlignment: Alignment {
        switch placement {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        }
    }
}

struct PerformanceStageBubbleView: View {
    let stage: OMERecord.Stage?
    let tint: Color

    var body: some View {
        PerformanceScheduleBubbleChrome(tint: tint) {
            stageIcon
        }
    }

    @ViewBuilder
    var stageIcon: some View {
        if let stage {
            ScheduleStageIcon(stage: stage)
        } else {
            Text("TBA")
                .font(.system(size: 18, weight: .heavy))
                .lineLimit(1)
                #if os(iOS)
                .minimumScaleFactor(0.5)
                #endif
        }
    }
}

struct PerformanceScheduleBubbleChrome<Content: View>: View {
    let tint: Color
    let content: Content

    init(
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        #if os(iOS) || os(macOS)
        if #available(iOS 26, macOS 26, *) {
            glassBubble
        } else {
            unselectedBubble
        }
        #else
        unselectedBubble
        #endif
    }

    @available(iOS 26, macOS 26, *)
    var glassBubble: some View {
        GlassEffectContainer(spacing: 8) {
            bubbleContent
                .glassEffect(.clear.interactive(), in: .circle)
            
        }
        .frame(
            width: PerformanceContextIdentity.bubbleSize,
            height: PerformanceContextIdentity.bubbleSize
        )
    }

    var unselectedBubble: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.12))

            tintedContent
        }
        .frame(
            width: PerformanceContextIdentity.bubbleSize,
            height: PerformanceContextIdentity.bubbleSize
        )
    }

    var bubbleContent: some View {
        ZStack {
            Circle()
                .fill(Color.clear)

            tintedContent
        }
        .frame(
            width: PerformanceContextIdentity.bubbleSize,
            height: PerformanceContextIdentity.bubbleSize
        )
    }

    var tintedContent: some View {
        content
            .frame(width: 46, height: 46)
            .padding(12)
            .foregroundStyle(tint)
    }
}

struct PerformanceArtistBubbleView: View {
    let contributor: ContributorProfile?
    let fallbackTitle: String
    let tint: Color

    var body: some View {
        if let logoAsset = contributor?.logoAsset {
            PerformanceScheduleBubbleChrome(tint: tint) {
                ImageAssetAsyncImage(
                    asset: logoAsset,
                    cacheContext: contributor?.logoCacheContext,
                    contentMode: .fit
                ) {
                    PerformanceArtistBubbleFallback(title: fallbackTitle, tint: tint)
                }
            }
        } else if !photoCandidates.isEmpty {
            PerformanceArtistPhotoBubbleView(
                candidates: photoCandidates,
                fallbackTitle: fallbackTitle,
                tint: tint
            )
        } else {
            PerformanceScheduleBubbleChrome(tint: tint) {
                PerformanceArtistBubbleFallback(title: fallbackTitle, tint: tint)
            }
        }
    }

    var photoCandidates: [PerformanceArtistImageCandidate] {
        guard let contributor else { return [] }

        var candidates: [PerformanceArtistImageCandidate] = []
        if let artworkAsset = contributor.artworkAsset {
            candidates.append(
                PerformanceArtistImageCandidate(
                    asset: artworkAsset,
                    cacheContext: contributor.artworkCacheContext
                )
            )
        }
        if let preferredArtworkAsset = contributor.contributor.preferredArtworkAsset,
           !candidates.contains(where: { $0.asset == preferredArtworkAsset }) {
            candidates.append(
                PerformanceArtistImageCandidate(
                    asset: preferredArtworkAsset,
                    cacheContext: LocalImageCacheContext(contributorID: contributor.id)
                )
            )
        }
        return candidates
    }
}

struct PerformanceArtistImageCandidate {
    let asset: OMERecord.ImageAsset
    let cacheContext: LocalImageCacheContext?
}

struct PerformanceArtistPhotoBubbleView: View {
    let candidates: [PerformanceArtistImageCandidate]
    let fallbackTitle: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.12))

            imageContent
                .opacity(0.88)
                .mask {
                    Circle()
                        .fill(
                            RadialGradient(
                                stops: [
                                    .init(color: .white, location: 0.0),
                                    .init(color: .white, location: 0.54),
                                    .init(color: .white.opacity(0.58), location: 0.82),
                                    .init(color: .clear, location: 1.0),
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: PerformanceContextIdentity.bubbleSize / 2
                            )
                        )
                }
        }
        .frame(
            width: PerformanceContextIdentity.bubbleSize,
            height: PerformanceContextIdentity.bubbleSize
        )
    }

    var imageContent: some View {
        PerformanceArtistPhotoImageView(
            candidates: candidates,
            fallbackTitle: fallbackTitle,
            tint: tint
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [
                    tint.opacity(0.38),
                    tint.opacity(0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(Circle())
    }
}

struct PerformanceArtistPhotoImageView: View {
    let candidates: [PerformanceArtistImageCandidate]
    let fallbackTitle: String
    let tint: Color

    var body: some View {
        if let candidate = candidates.first {
            ImageAssetAsyncImage(
                asset: candidate.asset,
                cacheContext: candidate.cacheContext,
                contentMode: .fill
            ) { reason in
                switch reason {
                case .failure, .unavailable:
                    PerformanceArtistPhotoImageView(
                        candidates: Array(candidates.dropFirst()),
                        fallbackTitle: fallbackTitle,
                        tint: tint
                    )

                case .loading:
                    PerformanceArtistBubbleFallback(title: fallbackTitle, tint: tint)
                }
            }
        } else {
            PerformanceArtistBubbleFallback(title: fallbackTitle, tint: tint)
        }
    }
}

struct PerformanceArtistBubbleFallback: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(initials)
            .font(.system(size: 38, weight: .heavy))
            .lineLimit(1)
            #if os(iOS)
            .minimumScaleFactor(0.35)
            #endif
            .foregroundStyle(tint)
    }

    var initials: String {
        let words = title
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        return words.isEmpty ? "SET" : words
    }
}

struct PerformanceHeroPlaceholder: View {
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    let performance: OMERecord.Performance
    let stage: OMERecord.Stage?

    var body: some View {
        if needsStageDisambiguation, let stage {
            StageIconFallback(stage: stage, size: 150)
        } else {
            Text(initials)
                .font(.system(size: 46, weight: .heavy))
                .lineLimit(1)
                #if os(iOS)
                .minimumScaleFactor(0.35)
                #endif
        }
    }

    var initials: String {
        let words = performance.title
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        return words.isEmpty ? "SET" : words
    }
}

struct PerformanceRecordingRow: View {
    let recording: ExternalPlatform.Asset
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        if let url = recording.url {
            Link(destination: url) {
                Label(recording.platform.name, systemImage: "link")
            }
        } else if let record = recording.record {
            Label(
                showsTechnicalDetails ? record.uri.description : "Recording",
                systemImage: "record.circle"
            )
        } else {
            Label("Recording", systemImage: "play.circle")
        }
    }
}
