import OpenMusicEventLexicon
import HeroImageList
import Bluesky
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventEditors
import OpenMusicEventImages
import OpenMusicEventViewers
import ScheduleComponents
import SQLiteData
import SwiftUI
import Tagged

@Feature
public struct ProgramItemDetail {
    public init() {}

    public struct State: Identifiable {
        public init(
            performanceID: ProgramItem.ID,
            eventID: Event.ID? = nil
        ) {
            @Dependency(EventDetailContext.self) var eventViewer
            self.eventID = eventID ?? eventViewer.eventID
            self.performanceID = performanceID
            self._timeZone = FetchOne(
                Event.timeZoneQuery(eventID: self.eventID)
            )
            self._persistedEventViewerState = FetchOne(
                wrappedValue: nil,
                EventDetailState.none
            )
            _contributors = FetchAll(
                ContributorProfile.forProgramItem(
                    programItemID: performanceID,
                    eventID: self.eventID,
                    hydration: .bskyActorProfile
                )
            )
            _performance = FetchOne(
                ProgramItemDetail.performanceQuery(
                    performanceID: performanceID,
                    eventID: self.eventID
                )
            )
            _schedules = FetchAll(
                ScheduleList.schedulesQuery(eventID: self.eventID)
            )
            _stages = FetchAll(EventPlace.where { $0.event.eq(self.eventID) })
            _reactions = FetchAll(
                PerformanceReaction.forPerformance(performanceID: performanceID)
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

        public let eventID: Event.ID
        public let performanceID: ProgramItem.ID
        @FetchOne public var timeZone: TimeZone?
        var eventTimePresentation: EventTimePresentation? {
            timeZone.map { EventTimePresentation(timeZone: $0) }
        }

        @FetchAll var contributors: [ContributorProfile]
        public var destination: Destination.State?
        @FetchOne var persistedEventViewerState: EventDetailState?
        public var eventViewerState: EventDetailState {
            persistedEventViewerState ?? EventDetailState(id: eventID)
        }
        @FetchOne public var performance: ProgramItem?
        @FetchAll public var schedules: [Schedule]
        @FetchAll public var stages: [EventPlace]
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

        public var id: ProgramItem.ID { performanceID }

        public var canEditPerformance: Bool {
            performance != nil
        }

        public var schedule: Schedule? {
            guard let scheduleID = performance?.schedule else { return nil }
            return schedules.first { $0.id == scheduleID }
        }

        public var stage: EventPlace? {
            guard let performance else { return nil }
            return stages.first { $0.id == performance.eventPlace }
        }

        var actorProfileLoadRequests: [ContributorProfile.ActorProfileLoadRequest] {
            contributors.actorProfileLoadRequests
        }

        var displayedContributors: [ContributorProfile] {
            displayedContributorCredits.compactMap(\.profile)
        }

        var displayedContributorCredits: [ContributorCredit] {
            let contributorsByID = Dictionary(
                uniqueKeysWithValues: contributors.map { ($0.contributorID, $0) }
            )
            return (performance?.credits ?? []).enumerated().map { index, credit in
                ContributorCredit(
                    id: index,
                    credit: credit,
                    profile: credit.contributor.flatMap { contributorsByID[$0] }
                )
            }
        }

        var headlineContributors: [ContributorProfile] {
            let primaryContributors = displayedContributorCredits
                .filter { $0.credit.billing == .known(.primary) }
                .compactMap(\.profile)
            return primaryContributors.isEmpty
                ? displayedContributors
                : primaryContributors
        }

        var headlineNames: [String] {
            let primary = displayedContributorCredits
                .filter { $0.credit.billing == .known(.primary) }
                .map { $0.credit.name }
            return primary.isEmpty
                ? displayedContributorCredits.map { $0.credit.name }
                : primary
        }

        struct ContributorCredit: Identifiable {
            let id: Int
            let credit: ProgramItem.Credit
            let profile: ContributorProfile?
            var contributorID: Contributor.ID? { profile?.contributorID }
            var roleTitle: String? {
                guard let role = credit.role else { return nil }
                return role == role.uppercased()
                    ? role
                    : role.replacingOccurrences(of: "-", with: " ").capitalized
            }
        }
    }

    public enum Action {
        case contributorButtonTapped(Contributor.ID)
        case deleteButtonTapped
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
    @Dependency(\.getSelectedOAuthSessionID) var getSelectedOAuthSessionID
    @Dependency(\.uuid) var uuid

    static func performanceQuery(
        performanceID: ProgramItem.ID,
        eventID: Event.ID
    ) -> some SelectStatementOf<ProgramItem> {
        ProgramItem
            .where { $0.id.eq(performanceID) }
            .where { $0.event.eq(eventID) }
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

            case .deleteButtonTapped:
                guard state.canEditPerformance else { return }
                let performanceID = state.performanceID
                store.addTask {
                    let task = try store.post(
                        key: SchedulePerformanceDeleteRequested.self,
                        value: performanceID
                    )
                    await task?.value
                }

            case .destination:
                break

            case .editButtonTapped:
                guard state.performance != nil else { return }
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
                        performanceID: state.performanceID
                    )
                )

            case let .reactionButtonTapped(emoji):
                let performanceID = state.performanceID
                let id = uuid()
                let date = now
                let userDID = getSelectedOAuthSessionID()?.rawValue
                store.addTask {
                    do {
                        try await database.write { db in
                            try PerformanceReaction.toggle(
                                performanceID: performanceID,
                                emoji: emoji,
                                id: id,
                                date: date,
                                userDID: userDID,
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
        .ifLet(\.destination) {
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
        .onMount { state in
            let eventID = state.eventID
            let persistedEventViewerState = state.$persistedEventViewerState
            store.addTask {
                try await persistedEventViewerState.load(
                    EventDetailState.where { $0.id.eq(eventID) }
                )
                .task
            }
        }
    }
}

public struct ProgramItemDetailView: View {
    @Bindable var store: StoreOf<ProgramItemDetail>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<ProgramItemDetail>,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        Group {
            if let performance = store.performance,
               let eventTimePresentation = store.state.eventTimePresentation {
                HeroImageList(title: Text(performance.title)) {
                    PerformanceHeroView(
                        performance: performance,
                        stage: store.stage,
                        contributors: store.headlineContributors,
                        contributorNames: store.headlineNames
                    )
                } content: {
                    PerformanceSummaryRow(
                        performance: performance,
                        stage: store.stage,
                        contributors: store.headlineContributors,
                        contributorNames: store.headlineNames,
                        eventTimePresentation: eventTimePresentation
                    )



                    if let description = performance.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !description.isEmpty {
                        Section("About") {
                            Text(description)
                        }

                    }

                    if !performance.recordingMedia.isEmpty {
                        Section("Recordings") {
                            ForEach(Array(performance.recordingMedia.enumerated()), id: \.offset) { _, recording in
                                PerformanceRecordingRow(recording: recording)
                            }
                        }
                    }

                    if !store.displayedContributorCredits.isEmpty {
                        Section {
                            ForEach(store.displayedContributorCredits) { credit in
                                if let profile = credit.profile,
                                   let contributorID = credit.contributorID {
                                    Button {
                                        store.send(.contributorButtonTapped(contributorID))
                                    } label: {
                                        ContributorsRowView(
                                            profile: profile,
                                            subtitle: credit.roleTitle
                                        )
                                    }
                                    .navigationLinkListRowStyle()
                                } else {
                                    LabeledContent(credit.credit.name, value: credit.roleTitle ?? "")
                                }
                            }
                        }
                    }

                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        PerformanceUserScheduleMenu(store: store)
                    }

                    ToolbarItem {
                        PerformanceReactionMenu(
                            performanceID: store.performanceID,
                            context: reactionMenuContext
                        )
                    }

                    if showsAuthoringControls {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                Button {
                                    store.send(.editButtonTapped)
                                } label: {
                                    Label("Edit Performance", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    store.send(.deleteButtonTapped)
                                } label: {
                                    Label("Delete Performance", systemImage: "trash")
                                }
                            } label: {
                                Label("Performance Actions", systemImage: "gearshape")
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
                            description: Text(verbatim: store.performanceID.description)
                        )
                    } else {
                        ContentUnavailableView("Performance unavailable", systemImage: "music.mic")
                    }
                }
                .navigationTitle("Performance")
            }
        }
        .accessibilityIdentifier(
            "view.performance-detail.\(store.performanceID.description)"
        )
        .navigationDestination(item: $store.scope(\.destination).contributorDetail) { detailStore in
            ContributorDetailView(
                store: detailStore,
                showsAuthoringControls: showsAuthoringControls
            )
        }
        .sheet(item: $store.scope(\.destination).reactionEntry) { entryStore in
            PerformanceReactionEntryView(store: entryStore)
        }
        .navigationDestination(item: $store.scope(\.destination).userScheduleForm) { formStore in
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
    @Bindable var store: StoreOf<ProgramItemDetail>

    public init(store: StoreOf<ProgramItemDetail>) {
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
            Label(
                "Personal Schedules",
                mappedSystemImage: userScheduleSystemImage
            )
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
                mappedSystemImage: userScheduleSystemImage
            )
        }
    }
}

struct PerformanceHeroView: View {
    let performance: ProgramItem
    let stage: EventPlace?
    let contributors: [ContributorProfile]
    let contributorNames: [String]

    var body: some View {
        let summary = ProgramItemDetailSummary(
            stage: stage,
            contributors: contributors,
            contributorNames: contributorNames
        )

        HeroImage(
            title: Text(performance.title),
            sources: performance.heroImageSources + (stage?.heroImageSources ?? []),
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
    @Environment(\.timeZone) var deviceTimeZone
    let performance: ProgramItem
    let stage: EventPlace?
    let contributors: [ContributorProfile]
    let contributorNames: [String]
    let eventTimePresentation: EventTimePresentation

    var body: some View {
        let summary = ProgramItemDetailSummary(
            stage: stage,
            contributors: contributors,
            contributorNames: contributorNames
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
                        eventTimePresentation.programItemRowTimeRange(
                            for: performance,
                            disclosure: .whenDeviceClockDiffers(deviceTimeZone)
                        )
                    )
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
#if !os(Android)
                    .portableLayoutPriority(1)
#endif

                    if let start = performance.startDate, let end = performance.endDate {
                        PeriodicTimelineView(every: 1) { currentDate in
                            PerformanceTimingChip(startTime: start, endTime: end, now: currentDate)
                                .portableLayoutPriority(1)
                        }
                    }

                    if let start = performance.startDate {
                        Text(
                            eventTimePresentation.daySegment(
                                for: start,
                                policy: dateTimeRangeResolutionPolicy
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
#if !os(Android)
                .portableLayoutPriority(1)
#endif
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

struct ProgramItemDetailSummary {
    let stage: EventPlace?
    let contributors: [ContributorProfile]
    let contributorNames: [String]

    var tint: Color {
        stage?.stageUIColor ?? .accentColor
    }

    var featuredContributor: ContributorProfile? {
        contributors.first { $0.logoDisplayImage != nil }
            ?? contributors.first { $0.artworkDisplayImage != nil }
            ?? contributors.first
    }

    var stageTitle: String {
        stage?.name ?? "Stage TBA"
    }

    var artistSummary: String {
        switch contributorNames.count {
        case 0:
            return "Lineup TBA"
        case 1:
            return contributorNames[0]
        case 2:
            return "\(contributorNames[0]) / \(contributorNames[1])"
        default:
            return "\(contributorNames[0]) + \(contributorNames.count - 1) more"
        }
    }
}

struct PerformanceContextIdentity: View {
    static let bubbleSize: OMECGFloat = 70
    static let itemWidth: OMECGFloat = 96
    static let labelHeight: OMECGFloat = 36

    enum Content {
        case contributor(ContributorProfile?, fallbackTitle: String)
        case stage(EventPlace?)
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
#if !os(Android)
        .accessibilityElement(children: .combine)
#endif
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
    let stage: EventPlace?
    let tint: Color

    var body: some View {
        PerformanceScheduleBubbleChrome(tint: tint) {
            stageIcon
        }
    }

    @ViewBuilder
    var stageIcon: some View {
        if let stage {
            EventPlaceStageArtworkView(place: stage, size: PerformanceContextIdentity.bubbleSize)
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

#if os(iOS) || os(macOS)
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
#endif

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
        if let logoImage = contributor?.logoDisplayImage {
            PerformanceScheduleBubbleChrome(tint: tint) {
                ImageAssetAsyncImage(
                    image: logoImage,
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

    var photoCandidates: [DisplayImageAsset] {
        guard let contributor else { return [] }
        return [contributor.artworkDisplayImage].compactMap { $0 }
    }
}

struct PerformanceArtistPhotoBubbleView: View {
    let candidates: [DisplayImageAsset]
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
                            performanceArtistPhotoMaskGradient
                        )
                }
        }
        .frame(
            width: PerformanceContextIdentity.bubbleSize,
            height: PerformanceContextIdentity.bubbleSize
        )
    }

    var performanceArtistPhotoMaskGradient: RadialGradient {
        #if os(Android)
        RadialGradient(
            colors: [.white, .white, .white.opacity(0.58), .clear],
            center: .center,
            startRadius: 0,
            endRadius: PerformanceContextIdentity.bubbleSize / 2
        )
        #else
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
        #endif
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
    let candidates: [DisplayImageAsset]
    let fallbackTitle: String
    let tint: Color

    var body: some View {
        if let candidate = candidates.first {
            ImageAssetAsyncImage(
                image: candidate,
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
    let performance: ProgramItem
    let stage: EventPlace?

    var body: some View {
        if needsStageDisambiguation, let stage {
            EventPlaceStageArtworkView(place: stage, size: 150)
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
    let recording: OME.Media
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        switch recording {
        case let .external(external):
            Link(destination: external.uri) {
                Label(external.title ?? "Recording", systemImage: "link")
            }
        case let .record(record):
            Label(
                showsTechnicalDetails ? record.uri.description : "Recording",
                systemImage: "record.circle"
            )
        case .image:
            EmptyView()
        }
    }
}

extension ProgramItem {
    var recordingMedia: [OME.Media] {
        (media ?? []).compactMap { item in
            guard case let .known(media) = item else { return nil }
            switch media {
            case .record, .external: return media
            case .image: return nil
            }
        }
    }
}
