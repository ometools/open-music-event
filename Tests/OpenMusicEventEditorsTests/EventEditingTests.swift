import Testing

@testable import OpenMusicEventEditors

@Suite
struct EventEditingTests {
    @Test
    func editorModuleContributesEditorFeatures() {
        #expect(EventFeature.editorFeatures == [
            .settings,
            .edit,
        ])
        #expect(EventFeature.settings.isEditorFeature)
        #expect(EventFeature.edit.isEditorFeature)
        #expect(!EventFeature.about.isEditorFeature)
    }
}
