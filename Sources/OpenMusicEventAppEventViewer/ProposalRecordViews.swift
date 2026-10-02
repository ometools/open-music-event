import HeroImageList
import Foundation
import ATProtoTypes
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
import SwiftUITabFeatures
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

struct ProposalRecordSnapshot: Equatable, Identifiable, Sendable {
    enum Version: Equatable, Sendable {
        case primary
        case previous
    }

    enum RecordType: Equatable, Sendable {
        case calendar
        case relationship
        case event
        case stage
        case contributor
        case schedule
        case scheduleItem
        case scheduleItemPerformanceDetails
        case scheduleItemContributor
        case channel
        case communicationPost
        case poster
        case unavailable

        var singularName: String {
            switch self {
            case .calendar: "Calendar"
            case .relationship: "Relationship"
            case .event: "Event"
            case .stage: "Stage"
            case .contributor: "Contributor"
            case .schedule: "Schedule"
            case .scheduleItem: "Schedule item"
            case .scheduleItemPerformanceDetails: "Performance details"
            case .scheduleItemContributor: "Schedule contributor"
            case .channel: "Channel"
            case .communicationPost: "Post"
            case .poster: "Poster"
            case .unavailable: "Record"
            }
        }

        var pluralName: String {
            switch self {
            case .calendar: "Calendars"
            case .relationship: "Relationships"
            case .event: "Events"
            case .stage: "Stages"
            case .contributor: "Contributors"
            case .schedule: "Schedules"
            case .scheduleItem: "Schedule Items"
            case .scheduleItemPerformanceDetails: "Performance Details"
            case .scheduleItemContributor: "Schedule Contributors"
            case .channel: "Channels"
            case .communicationPost: "Posts"
            case .poster: "Posters"
            case .unavailable: "Records"
            }
        }

        var systemImage: String {
            switch self {
            case .calendar, .schedule: "calendar"
            case .relationship: "person.3"
            case .event: "music.note"
            case .stage: "square.grid.2x2"
            case .contributor, .scheduleItemContributor: "person.crop.square"
            case .scheduleItem, .scheduleItemPerformanceDetails: "music.note"
            case .channel: "megaphone"
            case .communicationPost: "doc.text"
            case .poster: "photo"
            case .unavailable: "doc.text"
            }
        }
    }

    let id: String
    let fallbackTitle: String?
    let fallbackGroupName: String
    let transitionKind: OME.WorkspaceProposal.Presentation.Transition.Kind
    let record: OME.WorkspaceProposal.SourceRecord?
    let previousRecord: OME.WorkspaceProposal.SourceRecord?
    let sourceFiles: [String]
    let version: Version

    init(
        record presentationRecord: OME.WorkspaceProposal.Presentation.Record,
        groupName: String
    ) {
        let before = Self.knownRecord(from: presentationRecord.transition.before)
        let after = Self.knownRecord(from: presentationRecord.transition.after)

        self.id = presentationRecord.id
        self.fallbackTitle = presentationRecord.title
        self.fallbackGroupName = groupName
        self.transitionKind = presentationRecord.transition.kind
        self.sourceFiles = presentationRecord.sourceFiles
        self.version = .primary

        switch presentationRecord.transition.kind {
        case .added:
            self.record = after
            self.previousRecord = nil
        case .modified:
            self.record = after
            self.previousRecord = before
        case .deleted:
            self.record = before
            self.previousRecord = nil
        }
    }

    init(previousVersionOf snapshot: Self, record: OME.WorkspaceProposal.SourceRecord) {
        self.id = snapshot.id
        self.fallbackTitle = snapshot.fallbackTitle
        self.fallbackGroupName = snapshot.fallbackGroupName
        self.transitionKind = snapshot.transitionKind
        self.record = record
        self.previousRecord = nil
        self.sourceFiles = snapshot.sourceFiles
        self.version = .previous
    }

    static func knownRecord(
        from value: Open<OME.WorkspaceProposal.SourceRecord>?
    ) -> OME.WorkspaceProposal.SourceRecord? {
        guard let value, case let .known(record) = value else { return nil }
        return record
    }

    var previousSnapshot: Self? {
        previousRecord.map { Self(previousVersionOf: self, record: $0) }
    }

    var recordType: RecordType {
        guard let record = record ?? previousRecord else { return .unavailable }
        return switch record {
        case .calendar: .calendar
        case .relationship: .relationship
        case .event: .event
        case .stage: .stage
        case .contributor: .contributor
        case .schedule: .schedule
        case .scheduleItem: .scheduleItem
        case .scheduleItemPerformanceDetails: .scheduleItemPerformanceDetails
        case .scheduleItemContributor: .scheduleItemContributor
        case .channel: .channel
        case .communicationPost: .communicationPost
        case .poster: .poster
        }
    }

    var title: String {
        guard let record else {
            return fallbackTitle?.proposalNonempty ?? recordType.singularName
        }

        switch record {
        case let .calendar(calendar):
            return calendar.name.proposalNonempty ?? fallbackTitle ?? "Calendar"
        case let .relationship(relationship):
            return fallbackTitle?.proposalNonempty
                ?? relationship.proposalTitle
        case let .event(event):
            return event.name.proposalNonempty ?? fallbackTitle ?? "Event"
        case let .stage(stage):
            return stage.name.proposalNonempty ?? fallbackTitle ?? "Stage"
        case let .contributor(contributor):
            return contributor.name.proposalNonempty ?? fallbackTitle ?? "Contributor"
        case let .schedule(schedule):
            return schedule.customTitle?.proposalNonempty
                ?? schedule.date.proposalFormatted(in: .current)
        case let .scheduleItem(item):
            return item.title.proposalNonempty ?? fallbackTitle ?? "Schedule item"
        case .scheduleItemPerformanceDetails:
            return fallbackTitle?.proposalNonempty ?? "Performance recordings"
        case let .scheduleItemContributor(contributor):
            return contributor.anonymousName?.proposalNonempty
                ?? fallbackTitle?.proposalNonempty
                ?? "Schedule contributor"
        case let .channel(channel):
            return channel.name.proposalNonempty ?? fallbackTitle ?? "Channel"
        case let .communicationPost(post):
            return post.title.proposalNonempty ?? fallbackTitle ?? "Post"
        case let .poster(poster):
            return poster.title?.proposalNonempty ?? fallbackTitle?.proposalNonempty ?? "Poster"
        }
    }

    var subtitle: String? {
        guard let record else { return "Preview unavailable" }
        switch record {
        case let .calendar(calendar):
            return calendar.description?.proposalNonempty
        case let .relationship(relationship):
            return relationship.role.rawValue.proposalHumanized
        case let .event(event):
            return event.proposalDateSummary ?? event.description?.proposalNonempty
        case let .stage(stage):
            return stage.category?.rawValue.proposalHumanized.proposalNonempty
        case let .contributor(contributor):
            return contributor.bio?.proposalNonempty
        case let .schedule(schedule):
            return schedule.date.proposalFormatted(in: .current)
        case let .scheduleItem(item):
            return item.proposalTimeSummary
        case let .scheduleItemPerformanceDetails(details):
            return details.recordings.count == 1
                ? "1 recording"
                : "\(details.recordings.count) recordings"
        case let .scheduleItemContributor(contributor):
            return contributor.role?.rawValue.proposalHumanized
                ?? contributor.billing.rawValue.proposalHumanized
        case let .channel(channel):
            return channel.description.proposalNonempty
        case let .communicationPost(post):
            if let timestamp = post.timestamp {
                return timestamp.formatted(.relative(presentation: .numeric, unitsStyle: .wide))
            }
            return CommsMarkdown.fallbackText(post.contents).proposalSingleLine.proposalNonempty
        case .poster:
            return "Poster"
        }
    }

    var collectionName: String {
        recordType == .unavailable
            ? fallbackGroupName.proposalFriendlyGroupName
            : recordType.pluralName
    }

    var contextTitle: String {
        if version == .previous { return "Previous version" }
        return switch transitionKind {
        case .added: "Added in this proposal"
        case .modified: "Proposed version"
        case .deleted: "Removed by this proposal"
        }
    }

    var accessibilityLabel: String {
        "\(title), \(recordType.singularName), \(contextTitle)"
    }
}

struct ProposalRecordGroupDisclosure: View {
    let group: OME.WorkspaceProposal.Presentation.Group

    var snapshots: [ProposalRecordSnapshot] {
        group.records.map { ProposalRecordSnapshot(record: $0, groupName: group.displayName) }
    }

    var displayName: String {
        snapshots.first?.collectionName ?? group.displayName.proposalFriendlyGroupName
    }

    var body: some View {
        PortableDisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                    if index > 0 {
                        Divider()
                    }

                    NavigationLink {
                        ProposalRecordDetailView(snapshot: snapshot)
                    } label: {
                        ProposalRecordRow(snapshot: snapshot)
                    }
                    .navigationLinkListRowStyle()
                    .accessibilityIdentifier("workspace.proposal.change.row.\(snapshot.id)")
                    .accessibilityLabel(Text(verbatim: snapshot.accessibilityLabel))
                }
            }
            .padding(.top, 4)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                Text(group.records.count == 1 ? "1 change" : "\(group.records.count) changes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ProposalRecordRow: View {
    let snapshot: ProposalRecordSnapshot

    var body: some View {
        HStack(spacing: 12) {
            recordContent
                .frame(maxWidth: .infinity, alignment: .leading)

            SourceChangeKindBadge(kind: SourceRecordChangeKind(snapshot.transitionKind))
        }
        .padding(.vertical, 4)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    var recordContent: some View {
        switch snapshot.record {
        case let .calendar(calendar):
            ProposalArtworkRow(
                title: snapshot.title,
                subtitle: snapshot.subtitle,
                asset: calendar.images?.imageAsset(role: .logo)
                    ?? calendar.images?.imageAsset(role: .hero),
                cacheContext: .init(calendarID: calendar.id),
                systemImage: "calendar"
            )
        case let .event(event):
            ProposalArtworkRow(
                title: snapshot.title,
                subtitle: snapshot.subtitle,
                asset: event.images?.imageAsset(role: .icon)
                    ?? event.images?.imageAsset(role: .hero),
                cacheContext: .init(eventID: event.id),
                systemImage: "music.note"
            )
        case let .stage(stage):
            StageRowView(stage: stage)
        case let .contributor(contributor):
            ProposalArtworkRow(
                title: snapshot.title,
                subtitle: snapshot.subtitle,
                asset: contributor.images?.imageAsset(role: .photo)
                    ?? contributor.images?.imageAsset(role: .logo),
                cacheContext: .init(contributorID: contributor.id),
                systemImage: "person.crop.square"
            )
        case let .channel(channel):
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                        .font(.headline)
                        .fontWeight(.medium)
                    if let description = channel.description.proposalNonempty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if channel.notificationsRequired {
                    MappedSystemImage(systemName: "bell.badge")
                        .frame(width: 20, height: 20)
                        .accessibilityLabel("Notifications required")
                } else if channel.defaultNotificationState == .subscribed {
                    MappedSystemImage(systemName: "bell.fill")
                        .frame(width: 20, height: 20)
                        .accessibilityLabel("Notifications enabled")
                }
            }
            .padding(.vertical, 4)
        case let .communicationPost(post):
            ProposalCommsPostRow(post: post)
        case let .poster(poster):
            ProposalArtworkRow(
                title: snapshot.title,
                subtitle: snapshot.subtitle,
                asset: poster.image,
                cacheContext: .init(posterID: poster.id),
                systemImage: "photo"
            )
        case .relationship, .schedule, .scheduleItem,
             .scheduleItemPerformanceDetails, .scheduleItemContributor:
            ProposalSemanticRow(
                title: snapshot.title,
                subtitle: snapshot.subtitle,
                systemImage: snapshot.recordType.systemImage
            )
        case nil:
            ProposalSemanticRow(
                title: snapshot.title,
                subtitle: snapshot.subtitle,
                systemImage: snapshot.recordType.systemImage
            )
        }
    }
}

struct ProposalArtworkRow: View {
    let title: String
    let subtitle: String?
    let asset: OME.ImageAsset?
    let cacheContext: LocalImageCacheContext
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            ImageAssetAsyncImage(
                asset: asset?.proposalReachableAsset,
                cacheContext: cacheContext,
                renderedImageSize: CGSize(width: 60, height: 60)
            ) {
                MappedSystemImage(systemName: systemImage)
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 60, height: 60)
            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            ProposalRowText(title: title, subtitle: subtitle)
        }
    }
}

struct ProposalSemanticRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.secondary.opacity(0.12))
                .frame(width: 60, height: 60)
                .overlay {
                    MappedSystemImage(systemName: systemImage)
                        .frame(width: 26, height: 26)
                        .foregroundStyle(.secondary)
                }

            ProposalRowText(title: title, subtitle: subtitle)
        }
    }
}

struct ProposalRowText: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .lineLimit(2)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

struct ProposalCommsPostRow: View {
    let post: CommsPost

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(post.title)
                .font(.headline)
                .fontWeight(.regular)
                .lineLimit(2)

            if let timestamp = post.timestamp {
                Text(timestamp, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            CommsMarkdownText(post.contents)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}

struct ProposalRecordDetailView: View {
    let snapshot: ProposalRecordSnapshot

    var body: some View {
        Group {
            switch snapshot.record {
            case let .calendar(calendar):
                ProposalCalendarDetailView(snapshot: snapshot, calendar: calendar)
            case let .relationship(relationship):
                ProposalRelationshipDetailView(snapshot: snapshot, relationship: relationship)
            case let .event(event):
                ProposalEventDetailView(snapshot: snapshot, event: event)
            case let .stage(stage):
                ProposalStageDetailView(snapshot: snapshot, stage: stage)
            case let .contributor(contributor):
                ProposalContributorDetailView(snapshot: snapshot, contributor: contributor)
            case let .schedule(schedule):
                ProposalScheduleDetailView(snapshot: snapshot, schedule: schedule)
            case let .scheduleItem(item):
                ProposalScheduleItemDetailView(snapshot: snapshot, item: item)
            case let .scheduleItemPerformanceDetails(details):
                ProposalPerformanceDetailsView(snapshot: snapshot, details: details)
            case let .scheduleItemContributor(contributor):
                ProposalScheduleContributorDetailView(snapshot: snapshot, contributor: contributor)
            case let .channel(channel):
                ProposalChannelDetailView(snapshot: snapshot, channel: channel)
            case let .communicationPost(post):
                ProposalCommsPostDetailView(snapshot: snapshot, post: post)
            case let .poster(poster):
                ProposalPosterDetailView(snapshot: snapshot, poster: poster)
            case nil:
                ProposalUnavailableDetailView(snapshot: snapshot)
            }
        }
        .navigationTitle(snapshot.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct ProposalRecordMetadataSections: View {
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    let snapshot: ProposalRecordSnapshot

    var body: some View {
        Section {
            HStack(spacing: 8) {
                SourceChangeKindBadge(kind: SourceRecordChangeKind(snapshot.transitionKind))
                Text(snapshot.contextTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        if let previousSnapshot = snapshot.previousSnapshot {
            Section("Versions") {
                NavigationLink {
                    ProposalRecordDetailView(snapshot: previousSnapshot)
                } label: {
                    Label("Previous version", mappedSystemImage: "arrow.backward")
                }
                .navigationLinkListRowStyle()
                .accessibilityIdentifier("workspace.proposal.change.previous.\(snapshot.id)")
                .accessibilityLabel(Text(verbatim: "Previous version of \(snapshot.title)"))
            }
        }

        if showsTechnicalDetails {
            Section("Technical Details") {
                WorkspaceTechnicalValueView(label: "Record ID", value: snapshot.id)
                ForEach(Array(snapshot.sourceFiles.enumerated()), id: \.offset) { index, file in
                    WorkspaceTechnicalValueView(
                        label: index == 0 ? "Source file" : "Source file \(index + 1)",
                        value: file
                    )
                }
            }
        }
    }
}

struct ProposalHeroDetailView<Content: View, Placeholder: View>: View {
    let snapshot: ProposalRecordSnapshot
    let sources: [HeroImageSource]
    let titleSources: [HeroImageTitleSource]
    let tint: Color
    let content: Content
    let placeholder: Placeholder

    init(
        snapshot: ProposalRecordSnapshot,
        sources: [HeroImageSource],
        titleSources: [HeroImageTitleSource],
        tint: Color = .accentColor,
        @ViewBuilder placeholder: () -> Placeholder,
        @ViewBuilder content: () -> Content
    ) {
        self.snapshot = snapshot
        self.sources = sources
        self.titleSources = titleSources
        self.tint = tint
        self.placeholder = placeholder()
        self.content = content()
    }

    var body: some View {
        HeroImageList(
            title: Text(snapshot.title),
            showsNavigationTitleBeforeScroll: titleSources.containsLogo
        ) {
            HeroImage(
                title: Text(snapshot.title),
                sources: sources.compactMap(\.proposalReachableSource),
                titleSources: titleSources.compactMap(\.proposalReachableSource),
                tint: tint
            ) {
                placeholder
            }
        } content: {
            ProposalRecordMetadataSections(snapshot: snapshot)
            content
        }
    }
}

struct ProposalCalendarDetailView: View {
    let snapshot: ProposalRecordSnapshot
    let calendar: OME.Calendar

    var body: some View {
        ProposalHeroDetailView(
            snapshot: snapshot,
            sources: calendar.heroImageSources,
            titleSources: calendar.heroImageTitleSources
        ) {
            MappedSystemImage(systemName: "calendar")
                .frame(width: 82, height: 82)
        } content: {
            if let description = calendar.description?.proposalNonempty {
                Section("About") {
                    Text(description)
                }
            }
        }
    }
}

struct ProposalEventDetailView: View {
    let snapshot: ProposalRecordSnapshot
    let event: OME.Event

    var body: some View {
        ProposalHeroDetailView(
            snapshot: snapshot,
            sources: event.heroImageSources,
            titleSources: event.heroImageTitleSources
        ) {
            MappedSystemImage(systemName: "music.note")
                .frame(width: 82, height: 82)
        } content: {
            if let description = event.description?.proposalNonempty {
                Section("About") {
                    Text(description)
                }
            }

            if event.startDate != nil || event.endDate != nil {
                Section("Dates") {
                    if let starts = event.startDate?.proposalFormatted(in: event.timeZone) {
                        LabeledContent("Starts", value: starts)
                    }
                    if let ends = event.endDate?.proposalFormatted(in: event.timeZone) {
                        LabeledContent("Ends", value: ends)
                    }
                    LabeledContent("Time Zone", value: event.timeZone.identifier)
                }
            }

            if event.status != nil || event.mode != nil {
                Section("Details") {
                    if let status = event.status?.proposalDisplayName {
                        LabeledContent("Status", value: status)
                    }
                    if let mode = event.mode?.proposalDisplayName {
                        LabeledContent("Mode", value: mode)
                    }
                }
            }

            ForEach(Array((event.locations ?? []).enumerated()), id: \.offset) { index, location in
                if location.address?.proposalNonempty != nil
                    || location.directions?.proposalNonempty != nil {
                    Section(event.locations?.count == 1 ? "Location" : "Location \(index + 1)") {
                        if let address = location.address?.proposalNonempty {
                            Text(address)
                        }
                        if let directions = location.directions?.proposalNonempty {
                            Text(directions)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct ProposalStageDetailView: View {
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    let snapshot: ProposalRecordSnapshot
    let stage: OME.Stage

    var body: some View {
        ProposalHeroDetailView(
            snapshot: snapshot,
            sources: stage.heroImageSources,
            titleSources: stage.heroImageTitleSources,
            tint: stage.color.swiftUIColor
        ) {
            StageIconFallback(stage: stage, size: 150)
        } content: {
            if stage.category != nil || stage.lineup?.isEmpty == false
                || (showsTechnicalDetails && stage.sortIndex != nil) {
                Section("Details") {
                    if let category = stage.category?.rawValue.proposalHumanized.proposalNonempty {
                        LabeledContent("Category", value: category)
                    }
                    if let lineup = stage.lineup, !lineup.isEmpty {
                        LabeledContent(
                            "Lineup",
                            value: lineup.count == 1 ? "1 contributor" : "\(lineup.count) contributors"
                        )
                    }
                    if showsTechnicalDetails, let sortIndex = stage.sortIndex {
                        LabeledContent("Sort Index", value: sortIndex.formatted())
                    }
                }
            }
        }
    }
}

struct ProposalContributorDetailView: View {
    let snapshot: ProposalRecordSnapshot
    let contributor: OME.Contributor

    var body: some View {
        ProposalHeroDetailView(
            snapshot: snapshot,
            sources: [
                contributor.images?.imageAsset(role: .photo).map {
                    .primaryImage(DisplayImageAsset(
                        asset: $0,
                        cacheContext: .init(contributorID: contributor.id)
                    ))
                },
                contributor.images?.imageAsset(role: .logo).map {
                    .logo(DisplayImageAsset(
                        asset: $0,
                        cacheContext: .init(contributorID: contributor.id)
                    ))
                },
            ].compactMap { $0 },
            titleSources: [
                contributor.images?.imageAsset(role: .logo).map {
                    .logo(DisplayImageAsset(
                        asset: $0,
                        cacheContext: .init(contributorID: contributor.id)
                    ))
                },
                .title,
            ].compactMap { $0 }
        ) {
            MappedSystemImage(systemName: "person.crop.square")
                .frame(width: 82, height: 82)
        } content: {
            if let bio = contributor.bio?.proposalNonempty {
                Section("About") {
                    Text(bio)
                }
            }

            if let links = contributor.links, !links.isEmpty {
                Section("Links") {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                        Link(destination: link.url) {
                            HStack(spacing: 12) {
                                Text(link.platform?.name ?? "Website")
                                    .foregroundStyle(.primary)
                                Spacer()
                                MappedSystemImage(systemName: "arrow.up.right")
                                    .frame(width: 14, height: 14)
                                    .foregroundStyle(.secondary)
                            }
                            .portableContentShape(Rectangle())
                        }
                    }
                }
            }
        }
    }
}

struct ProposalChannelDetailView: View {
    let snapshot: ProposalRecordSnapshot
    let channel: OME.Channel

    var body: some View {
        List {
            ProposalRecordMetadataSections(snapshot: snapshot)

            if let description = channel.description.proposalNonempty {
                Section("About") {
                    Text(description)
                }
            }

            Section("Notifications") {
                LabeledContent(
                    "Default",
                    value: channel.defaultNotificationState == .subscribed
                        ? "Enabled"
                        : "Disabled"
                )
                if channel.notificationsRequired {
                    Text("Notifications are required for this channel.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ProposalCommsPostDetailView: View {
    let snapshot: ProposalRecordSnapshot
    let post: CommsPost

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProposalRecordContextCard(snapshot: snapshot)

                if let headerImageURL = post.headerImageURL?.proposalReachableRemoteURL {
                    CachedRemoteImage(url: headerImageURL) { phase in
                        switch phase {
                        case let .success(image, _):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        case .failure, .unavailable:
                            ProposalRemoteImagePlaceholder()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if post.headerImageURL != nil {
                    ProposalRemoteImagePlaceholder()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(post.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let timestamp = post.timestamp {
                        Text(timestamp, format: .relative(presentation: .named))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                CommsMarkdownText(post.contents)
                    .multilineTextAlignment(.leading)

                ForEach(Array((post.images ?? []).enumerated()), id: \.offset) { _, image in
                    ImageAssetAsyncImage(
                        asset: image.proposalReachableAsset,
                        cacheContext: LocalImageCacheContext(commsPostID: post.id),
                        contentMode: .fit
                    ) {
                        ProposalRemoteImagePlaceholder()
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                ProposalPreviousVersionCard(snapshot: snapshot)
                ProposalTechnicalDetailsCard(snapshot: snapshot)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }
}

struct ProposalPosterDetailView: View {
    let snapshot: ProposalRecordSnapshot
    let poster: OME.Poster

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProposalRecordContextCard(snapshot: snapshot)

                ImageAssetAsyncImage(
                    asset: poster.image.proposalReachableAsset,
                    cacheContext: LocalImageCacheContext(posterID: poster.id),
                    contentMode: .fit
                ) {
                    PosterPlaceholderView()
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let title = poster.title?.proposalNonempty {
                    Text(title)
                        .font(.title2.weight(.bold))
                }

                ProposalPreviousVersionCard(snapshot: snapshot)
                ProposalTechnicalDetailsCard(snapshot: snapshot)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

struct ProposalScheduleDetailView: View {
    let snapshot: ProposalRecordSnapshot
    let schedule: OME.Schedule

    var body: some View {
        List {
            ProposalRecordMetadataSections(snapshot: snapshot)
            Section("Schedule") {
                LabeledContent("Date", value: schedule.date.proposalFormatted(in: .current))
                if let startsAt = schedule.startsAt {
                    LabeledContent("Starts", value: startsAt.proposalDateTime)
                }
                if let endsAt = schedule.endsAt {
                    LabeledContent("Ends", value: endsAt.proposalDateTime)
                }
            }
        }
    }
}

struct ProposalScheduleItemDetailView: View {
    let snapshot: ProposalRecordSnapshot
    let item: OME.ScheduleItem

    var body: some View {
        List {
            ProposalRecordMetadataSections(snapshot: snapshot)
            if let description = item.description?.proposalNonempty {
                Section("About") {
                    Text(description)
                }
            }
            Section("Time") {
                LabeledContent("Starts", value: item.startTime.proposalDateTime)
                LabeledContent("Ends", value: item.endTime.proposalDateTime)
            }
        }
    }
}

struct ProposalPerformanceDetailsView: View {
    let snapshot: ProposalRecordSnapshot
    let details: OME.ScheduleItem.PerformanceDetails

    var body: some View {
        List {
            ProposalRecordMetadataSections(snapshot: snapshot)
            Section("Recordings") {
                if details.recordings.isEmpty {
                    Text("No recordings")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(details.recordings.enumerated()), id: \.offset) { _, recording in
                    if let url = recording.url {
                        Link(destination: url) {
                            HStack {
                                Text(recording.platform.name)
                                Spacer()
                                MappedSystemImage(systemName: "arrow.up.right")
                                    .frame(width: 14, height: 14)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text(recording.platform.name)
                    }
                }
            }
        }
    }
}

struct ProposalScheduleContributorDetailView: View {
    let snapshot: ProposalRecordSnapshot
    let contributor: OME.ScheduleItem.Contributor

    var body: some View {
        List {
            ProposalRecordMetadataSections(snapshot: snapshot)
            Section("Contribution") {
                if let name = contributor.anonymousName?.proposalNonempty {
                    LabeledContent("Name", value: name)
                }
                if let role = contributor.role?.rawValue.proposalHumanized.proposalNonempty {
                    LabeledContent("Role", value: role)
                }
                LabeledContent("Billing", value: contributor.billing.rawValue.proposalHumanized)
            }
        }
    }
}

struct ProposalRelationshipDetailView: View {
    let snapshot: ProposalRecordSnapshot
    let relationship: OME.Relationship

    var body: some View {
        List {
            ProposalRecordMetadataSections(snapshot: snapshot)
            Section("Relationship") {
                LabeledContent("Role", value: relationship.role.rawValue.proposalHumanized)
                if let subject = relationship.subject.proposalDisplayName {
                    LabeledContent("Subject", value: subject)
                }
                if let object = relationship.object?.proposalDisplayName {
                    LabeledContent("For", value: object)
                }
                if let capabilities = relationship.capabilities, !capabilities.isEmpty {
                    LabeledContent(
                        "Permissions",
                        value: capabilities.map { $0.rawValue.proposalHumanized }.joined(separator: ", ")
                    )
                }
            }
        }
    }
}

struct ProposalUnavailableDetailView: View {
    let snapshot: ProposalRecordSnapshot

    var body: some View {
        List {
            Section {
                ContentUnavailableView {
                    Label("Preview unavailable", mappedSystemImage: "doc.text")
                } description: {
                    Text("This proposal does not include a previewable snapshot for this record.")
                }
            }
            ProposalRecordMetadataSections(snapshot: snapshot)
        }
    }
}

struct ProposalRecordContextCard: View {
    let snapshot: ProposalRecordSnapshot

    var body: some View {
        HStack(spacing: 8) {
            SourceChangeKindBadge(kind: SourceRecordChangeKind(snapshot.transitionKind))
            Text(snapshot.contextTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ProposalPreviousVersionCard: View {
    let snapshot: ProposalRecordSnapshot

    @ViewBuilder
    var body: some View {
        if let previousSnapshot = snapshot.previousSnapshot {
            NavigationLink {
                ProposalRecordDetailView(snapshot: previousSnapshot)
            } label: {
                Label("Previous version", mappedSystemImage: "arrow.backward")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            .navigationLinkListRowStyle()
            .accessibilityIdentifier("workspace.proposal.change.previous.\(snapshot.id)")
        }
    }
}

struct ProposalTechnicalDetailsCard: View {
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    let snapshot: ProposalRecordSnapshot

    @ViewBuilder
    var body: some View {
        if showsTechnicalDetails {
            VStack(alignment: .leading, spacing: 8) {
                Text("Technical Details")
                    .font(.headline)
                WorkspaceTechnicalValueView(label: "Record ID", value: snapshot.id)
                ForEach(Array(snapshot.sourceFiles.enumerated()), id: \.offset) { index, file in
                    WorkspaceTechnicalValueView(
                        label: index == 0 ? "Source file" : "Source file \(index + 1)",
                        value: file
                    )
                }
            }
            .padding(12)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct ProposalRemoteImagePlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.secondary.opacity(0.12))
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                MappedSystemImage(systemName: "photo")
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.secondary)
            }
    }
}

extension OME.ImageAsset {
    var proposalReachableAsset: Self? {
        guard case let .url(url) = source else { return self }
        return url.proposalReachableRemoteURL == nil ? nil : self
    }
}

extension HeroImageSource {
    var proposalReachableSource: Self? {
        guard case let .source(asset, _) = image else { return self }
        return asset.proposalReachableAsset == nil ? nil : self
    }
}

extension HeroImageTitleSource {
    var proposalReachableSource: Self? {
        switch self {
        case let .logo(image):
            guard case let .source(asset, _) = image else { return self }
            return asset.proposalReachableAsset == nil ? nil : self
        case .title:
            return self
        }
    }
}

extension URL {
    var proposalReachableRemoteURL: URL? {
        guard let scheme = scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        return self
    }
}

extension OME.Relationship {
    var proposalTitle: String {
        if let subject = subject.proposalDisplayName {
            return "\(subject) — \(role.rawValue.proposalHumanized)"
        }
        return role.rawValue.proposalHumanized
    }
}

extension Open where Known == OME.Relationship.Entity {
    var proposalDisplayName: String? {
        switch self {
        case let .known(.identity(identity)):
            return identity.displayName?.proposalNonempty
                ?? identity.handle?.proposalNonempty.map { "@\($0)" }
        case .known(.record):
            return "Record"
        case .unknown:
            return nil
        }
    }
}

extension OME.ScheduleItem {
    var proposalTimeSummary: String {
        "\(startTime.proposalTime)–\(endTime.proposalTime)"
    }
}

extension OME.Event {
    var proposalDateSummary: String? {
        switch (startDate, endDate) {
        case let (start?, end?):
            return start == end
                ? start.proposalFormatted(in: timeZone)
                : "\(start.proposalFormatted(in: timeZone))–\(end.proposalFormatted(in: timeZone))"
        case let (start?, nil):
            return start.proposalFormatted(in: timeZone)
        case let (nil, end?):
            return end.proposalFormatted(in: timeZone)
        case (nil, nil):
            return nil
        }
    }
}

extension Open where Known == OME.Event.Status {
    var proposalDisplayName: String? {
        switch self {
        case let .known(status): status.rawValue.proposalHumanized
        case let .unknown(value): value.string?.proposalNonempty
        }
    }
}

extension Open where Known == OME.Event.Mode {
    var proposalDisplayName: String? {
        switch self {
        case let .known(mode): mode.rawValue.proposalHumanized
        case let .unknown(value): value.string?.proposalNonempty
        }
    }
}

extension LocalDate {
    func proposalFormatted(in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: atStartOfDay(in: timeZone))
    }
}

extension Date {
    var proposalTime: String {
        formatted(date: .omitted, time: .shortened)
    }

    var proposalDateTime: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}

extension String {
    var proposalNonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var proposalSingleLine: String {
        components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var proposalHumanized: String {
        replacingOccurrences(of: "community.lexicon.calendar.event#", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    var proposalFriendlyGroupName: String {
        switch lowercased() {
        case "calendar", "calendars": "Calendars"
        case "relationship", "relationships": "Relationships"
        case "event", "events", "event details": "Events"
        case "stage", "stages": "Stages"
        case "contributor", "contributors": "Contributors"
        case "schedule", "schedules": "Schedules"
        case "scheduleitem", "scheduleitems", "schedule items": "Schedule Items"
        case "scheduleitemperformancedetails", "performance details": "Performance Details"
        case "scheduleitemcontributor", "schedule contributors": "Schedule Contributors"
        case "channel", "channels": "Channels"
        case "commspost", "communication posts", "posts": "Posts"
        case "poster", "posters": "Posters"
        default: proposalHumanized
        }
    }
}
