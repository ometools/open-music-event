import OpenMusicEventDatabase
import OpenMusicEventImages
import SwiftUI

struct ContributorDetailContentView: View {
    let profile: ContributorProfile
    let stageContext: ContributorStageContext
    let editButtonTapped: () -> Void

    var body: some View {
        HeroImageList(
            title: Text(profile.name),
            showsNavigationTitleBeforeScroll: profile.logoAsset != nil
        ) {
            HeroImage(
                title: Text(profile.name),
                asset: profile.artworkAsset,
                cacheContext: profile.artworkCacheContext,
                logoAsset: profile.logoAsset,
                logoCacheContext: profile.logoCacheContext,
                tint: stageContext.primaryStage?.color.swiftUIColor ?? .accentColor
            ) {
                Image(systemName: "person.crop.square")
                    .font(.system(size: 82, weight: .semibold))
            }
        } content: {
            ContributorDetailSectionsView(
                bio: profile.bio,
                contributor: profile.contributor,
                stageContext: stageContext
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

    var body: some View {
        if let kind = contributor.kind?.displayName {
            Section("Details") {
                LabeledContent("Kind", value: kind)
            }
        }

        ContributorScheduleSection(stageContext: stageContext)
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
    let stageContext: ContributorStageContext

    var body: some View {
        if !stageContext.scheduledPerformances.isEmpty {
            Section("Schedule") {
                ForEach(stageContext.scheduledPerformances) { performance in
                    SchedulePerformanceRow(
                        performance: performance,
                        stage: stageContext.stage(for: performance)
                    )
                }
            }
        }
    }
}

struct ContributorStageLineupsSection: View {
    let stages: [OMERecord.Stage]

    var body: some View {
        if !stages.isEmpty {
            Section("Stage Lineups") {
                ForEach(stages) { stage in
                    StageRowView(stage: stage)
                }
            }
        }
    }
}
