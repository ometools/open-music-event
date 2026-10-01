import OpenMusicEventLexicon
import Testing

@testable import OpenMusicEventViewers

@Suite
struct EventFeatureTests {
    @Test
    func readOnlyDefaultFeaturesKeepSettingsAndExcludeDisabledFeatures() {
        #expect(!EventFeature.defaultReadOnlyFeatures.contains(.notifications))
        #expect(!EventFeature.defaultReadOnlyFeatures.contains(.workspace))
        #expect(EventFeature.defaultReadOnlyFeatures.contains(.settings))
    }

    @Test
    func readOnlyFeaturesIncludeScheduleDivisionsBeforeStaticFeatures() {
        let workshopDivision = ScheduleDivision(
            category: "workshop"
        )

        let features = EventFeature.readOnlyFeatures(
            scheduleDivisions: [
                .schedule,
                workshopDivision,
            ]
        )

        #expect(Array(features.prefix(2)) == [
            .schedule(.schedule),
            .schedule(workshopDivision),
        ])
        #expect(!features.contains(.workspace))
        #expect(features.contains(.settings))
    }

    @Test
    func eventTargetsMapToViewerFeatures() throws {
        #expect(EventTarget.schedule.eventFeature == .schedule(.schedule))
        #expect(EventTarget.contributors.eventFeature == .contributors)
        #expect(
            EventTarget.contributor(
                try #require(Contributor.ID(
                    "at://did:plc:organizer/events.openmusic.contributor/3mrdbziccpcah"
                ))
            )
                .eventFeature == .contributors
        )
        #expect(EventTarget.settings.eventFeature == .settings)
        #expect(EventTarget.notifications.eventFeature == .settings)
        #expect(EventTarget.workspace.eventFeature == .workspace)
    }

    @Test
    func legacyEditFeatureDescriptionParsesAsWorkspace() {
        #expect(EventFeature("edit") == .workspace)
        #expect(EventFeature("workspace") == .workspace)
    }
}
