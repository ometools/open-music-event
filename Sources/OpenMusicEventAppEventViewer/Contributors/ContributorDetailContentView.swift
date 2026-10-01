import HeroImageList
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
import ScheduleComponents
import SwiftUITabFeatures
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

struct ContributorDetailContentView: View {
    @Environment(\.dateTimeRangeResolutionPolicy) var dateTimeRangeResolutionPolicy
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    @Environment(\.performanceReactionMenuContext) var reactionMenuContext
    @Environment(\.timeZone) var deviceTimeZone
    let profile: ContributorProfile
    let heroImageSources: [HeroImageSource]
    let stageContext: ContributorStageContext
    let performanceRows: [PerformanceRow]
    let eventTimePresentation: EventTimePresentation
    let showsAuthoringControls: Bool
    let performanceButtonTapped: (ProgramItem.ID) -> Void
    let editButtonTapped: () -> Void

    var body: some View {
        let heroImageTitleSources = profile.heroImageTitleSources
        HeroImageList(
            title: Text(profile.name),
            showsNavigationTitleBeforeScroll: heroImageTitleSources.containsLogo
        ) {
            HeroImage(
                title: Text(profile.name),
                sources: heroImageSources,
                titleSources: heroImageTitleSources,
                tint: stageContext.primaryStage?.stageUIColor ?? .accentColor
            ) {
                MappedSystemImage(systemName: "person.crop.square")
                    .frame(width: 82, height: 82)
            }
        } content: {
            if !performanceRows.isEmpty {
                Section("Schedule") {
                    ForEach(performanceRows) { row in
                        Button {
                            performanceButtonTapped(row.performanceID)
                        } label: {
                            PeriodicTimelineView(every: 1) { currentDate in
                                ContributorSchedulePerformanceRow(
                                    row: row,
                                    timeRangeText: eventTimePresentation.programItemRowTimeRange(
                                        for: row.performance,
                                        disclosure: .whenDeviceClockDiffers(deviceTimeZone)
                                    ),
                                    daySegmentText: row.performance.startDate.map {
                                        eventTimePresentation.daySegment(
                                            for: $0,
                                            policy: dateTimeRangeResolutionPolicy
                                        )
                                    } ?? "Unscheduled",
                                    now: currentDate
                                )
                            }
                        }
                        .navigationLinkListRowStyle()
                        .accessibilityIdentifier(
                            "button.performance.\(row.performanceID.description)"
                        )
                        .contextMenu {
                            PerformanceReactionMenuContent(
                                performanceID: row.performance.id,
                                context: reactionMenuContext
                            )
                        }
                    }
                }
            }

            if needsStageDisambiguation, !stageContext.lineupOnlyStages.isEmpty {
                Section("Stage Lineups") {
                    ForEach(stageContext.lineupOnlyStages) { stage in
                        EventPlaceStageRowView(place: stage)
                    }
                }
            }

            if let bio = profile.bio {
                Section("About") {
                    Text(bio)
                }
            }

            if let links = profile.contributor.links, !links.isEmpty {
                Section("Links") {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                        ContributorLinkRow(link: link)
                    }
                }
            }
        }
        .toolbar {
            if showsAuthoringControls {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: editButtonTapped) {
                        Label("Edit", systemImage: "pencil")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
    }
}

struct ContributorSchedulePerformanceRow: View {
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    let row: PerformanceRow
    let timeRangeText: String
    let daySegmentText: String
    var now: Date?

    var body: some View {
        HStack(spacing: 10) {
            if needsStageDisambiguation {
                RoundedRectangle(cornerRadius: 2)
                    .fill(row.stage?.stageUIColor ?? .secondary.opacity(0.35))
                    .frame(width: 5, height: 44)

                stageIcon
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(timeRangeText)
                        .lineLimit(1)
                        .portableLayoutPriority(1)

                    Text(daySegmentText)
                        .lineLimit(1)

                    if let timingStatus {
                        PerformanceTimingChip(status: timingStatus)
                            .portableLayoutPriority(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PerformanceReactionSummaryWhenFits(
                performanceID: row.performance.id
            )
            .portableLayoutPriority(-1)
        }
        .frame(minHeight: 44, alignment: .leading)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var stageIcon: some View {
        if let stage = row.stage {
            EventPlaceStageArtworkView(place: stage, size: 44, fallbackTextScale: 0.5)
        } else {
            MappedSystemImage(systemName: "music.note")
                .padding(10)
                .foregroundStyle(.secondary)
        }
    }

    var timingStatus: PerformanceTimingStatus? {
        guard let now else { return nil }
        guard let start = row.performance.startDate,
              let end = row.performance.endDate
        else { return nil }
        return PerformanceTimingStatus(
            startTime: start,
            endTime: end,
            now: now
        )
    }
}

struct EventPlaceStageRowView: View {
    let place: EventPlace

    var body: some View {
        HStack(spacing: 12) {
            EventPlaceStageArtworkView(place: place, size: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .lineLimit(1)
                if let category = place.stageUse?.category, !category.isEmpty {
                    Text(category.replacingOccurrences(of: "-", with: " ")
                        .replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .foregroundStyle(.primary)
    }
}

struct EventPlaceStageArtworkView: View {
    let place: EventPlace
    let size: CGFloat
    var fallbackTextScale: CGFloat = 0.36

    var body: some View {
        Group {
            if let logo = place.stageLogoDisplayImage {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(place.stageUIColor.opacity(0.18))
                    ImageAssetAsyncImage(
                        image: logo,
                        contentMode: .fit,
                        renderedImageSize: CGSize(width: size, height: size)
                    ) {
                        EventPlaceStageIconFallback(
                            place: place, size: size, textScale: fallbackTextScale
                        )
                    }
                    .foregroundStyle(place.stageUIColor)
                    .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                EventPlaceStageIconFallback(
                    place: place, size: size, textScale: fallbackTextScale
                )
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
    }
}

struct EventPlaceStageIconFallback: View {
    let place: EventPlace
    let size: CGFloat
    var textScale: CGFloat = 0.36

    var body: some View {
        if let icon = place.stageUse?.icon {
            MappedSystemImage(systemName: icon.rawValue)
                .frame(width: size * 0.42, height: size * 0.42)
        } else if let shortLabel = place.stageUse?.shortLabel, !shortLabel.isEmpty {
            Text(shortLabel)
                .font(.system(size: size * textScale, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.2)
        } else {
            Text(place.stageFallbackInitials)
                .font(.system(size: size * textScale, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.2)
        }
    }
}
