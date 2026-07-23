import Testing

@testable import OpenMusicEventViewers

@Suite
struct EventFeatureTests {
    @Test
    func readOnlyDefaultFeaturesExcludeEditorTabs() {
        #expect(!EventFeature.defaultReadOnlyFeatures.contains(.workspace))
        #expect(!EventFeature.defaultReadOnlyFeatures.contains(.settings))
    }

    @Test
    func readOnlyFeaturesIncludeScheduleDivisionsBeforeStaticFeatures() {
        let workshopDivision = ScheduleDivision(
            category: OMERecord.Stage.Category("workshop")
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
        #expect(!features.contains(.settings))
    }

    @Test
    func eventTargetsMapToViewerFeatures() {
        #expect(EventTarget.schedule.eventFeature == .schedule(.schedule))
        #expect(EventTarget.contributors.eventFeature == .contributors)
        #expect(
            EventTarget.contributor(
                OMERecord.ID<OMERecord.Contributor>(.init("artist-1"))
            )
                .eventFeature == .contributors
        )
        #expect(EventTarget.settings.eventFeature == .settings)
        #expect(EventTarget.workspace.eventFeature == .workspace)
    }

    @Test
    func legacyEditFeatureDescriptionParsesAsWorkspace() {
        #expect(EventFeature("edit") == .workspace)
        #expect(EventFeature("workspace") == .workspace)
    }

    @Test
    func shareFeatureHasAStableMoreDestinationIdentity() {
        #expect(EventFeature("share") == .share)
        #expect(EventFeature.share.description == "share")
        #expect(EventFeature.share.customizationID == "openMusicEvent.eventViewer.share")
        #expect(EventFeature.share.title == "Share")
        #expect(EventFeature.share.systemImage == "qrcode")
    }
}
