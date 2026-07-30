import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventImages
import ScheduleComponents
import SwiftUITabFeatures
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

struct ContributorDetailContentView: View {
    let profile: ContributorProfile
    let heroImageSources: [HeroImageSource]
    let stageContext: ContributorStageContext
    let performanceRows: [PerformanceRow]
    let timeZone: TimeZone
    let showsAuthoringControls: Bool
    let performanceButtonTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
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
                tint: stageContext.primaryStage?.color.swiftUIColor ?? .accentColor
            ) {
                Image(systemName: "person.crop.square")
                    .font(.system(size: 82, weight: .semibold))
            }
        } content: {
            ContributorDetailSectionsView(
                bio: profile.bio,
                contributor: profile.contributor,
                stageContext: stageContext,
                performanceRows: performanceRows,
                timeZone: timeZone,
                performanceButtonTapped: performanceButtonTapped
            )
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

struct ContributorDetailSectionsView: View {
    let bio: String?
    let contributor: OMERecord.Contributor
    let stageContext: ContributorStageContext
    let performanceRows: [PerformanceRow]
    let timeZone: TimeZone
    let performanceButtonTapped: (OMERecord.ID<OMERecord.Performance>) -> Void

    var body: some View {
        ContributorScheduleSection(
            performanceRows: performanceRows,
            timeZone: timeZone,
            performanceButtonTapped: performanceButtonTapped
        )
        ContributorStageLineupsSection(stages: stageContext.lineupOnlyStages)

        if let bio {
            Section("About") {
                Text(bio)
            }
        }

        if let links = contributor.links, !links.isEmpty {
            Section("Links") {
                ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                    ContributorLinkRow(link: link)
                }
            }
        }
    }
}

struct ContributorScheduleSection: View {
    @Environment(\.dateTimeRangeResolutionPolicy) var dateTimeRangeResolutionPolicy
    let performanceRows: [PerformanceRow]
    let timeZone: TimeZone
    let performanceButtonTapped: (OMERecord.ID<OMERecord.Performance>) -> Void

    var body: some View {
        if !performanceRows.isEmpty {
            Section("Schedule") {
                ForEach(performanceRows) { row in
                    Button {
                        performanceButtonTapped(row.performanceID)
                    } label: {
                        TimelineView(.periodic(from: Date.now, by: 1)) { context in
                            ContributorSchedulePerformanceRow(
                                row: row,
                                subtitle: ScheduleViewer.performanceRowSubtitle(
                                    for: row.performance,
                                    timeZone: timeZone,
                                    policy: dateTimeRangeResolutionPolicy
                                ),
                                now: context.date
                            )
                        }
                    }
                    .navigationLinkListRowStyle()
                }
            }
        }
    }
}

struct ContributorSchedulePerformanceRow: View {
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    let row: PerformanceRow
    let subtitle: String
    var now: Date?

    var body: some View {
        HStack(spacing: 10) {
            if needsStageDisambiguation {
                RoundedRectangle(cornerRadius: 2)
                    .fill(row.stage?.color.swiftUIColor ?? .secondary.opacity(0.35))
                    .frame(width: 5, height: 44)

                stageIcon
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let timingStatus {
                        PerformanceTimingChip(status: timingStatus)
                            .portableLayoutPriority(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44, alignment: .leading)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var stageIcon: some View {
        if let stage = row.stage {
            ScheduleStageIcon(stage: stage)
        } else {
            Image(
                system: "music.note",
                material: "Icons.Outlined.MusicNote"
            )
                .resizable()
                .scaledToFit()
                .padding(10)
                .foregroundStyle(.secondary)
        }
    }

    var timingStatus: PerformanceTimingStatus? {
        guard let now else { return nil }
        return PerformanceTimingStatus(
            startTime: row.performance.startTime,
            endTime: row.performance.endTime,
            now: now
        )
    }
}

struct ContributorStageLineupsSection: View {
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    let stages: [OMERecord.Stage]

    var body: some View {
        if needsStageDisambiguation, !stages.isEmpty {
            Section("Stage Lineups") {
                ForEach(stages) { stage in
                    StageRowView(stage: stage)
                }
            }
        }
    }
}
