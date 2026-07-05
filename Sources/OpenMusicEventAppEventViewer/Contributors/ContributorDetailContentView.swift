import Foundation
import OpenMusicEventDatabase
import OpenMusicEventImages
import ScheduleComponents
import SwiftUITabFeatures
import SwiftUI

struct ContributorDetailContentView: View {
    let profile: ContributorProfile
    let stageContext: ContributorStageContext
    let performanceRows: [PerformanceRow]
    let timeZone: TimeZone
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
                sources: profile.heroImageSources,
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
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", action: editButtonTapped)
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
                        ContributorSchedulePerformanceRow(
                            row: row,
                            subtitle: ScheduleViewer.performanceRowSubtitle(
                                for: row.performance,
                                timeZone: timeZone,
                                policy: dateTimeRangeResolutionPolicy
                            )
                        )
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

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
            Image(systemName: "music.note")
                .resizable()
                .scaledToFit()
                .padding(10)
                .foregroundStyle(.secondary)
        }
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
