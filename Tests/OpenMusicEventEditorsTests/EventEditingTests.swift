import Testing

@testable import OpenMusicEventEditors

@Suite
struct EventEditingTests {
    @Test
    func editorModuleContributesEditorFeatures() {
        #expect(EventFeature.editorFeatures == [
            .workspace,
        ])
        #expect(!EventFeature.settings.isEditorFeature)
        #expect(EventFeature.workspace.isEditorFeature)
        #expect(!EventFeature.about.isEditorFeature)
    }
}
