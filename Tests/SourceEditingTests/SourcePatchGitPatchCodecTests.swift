import CustomDump
import Foundation
import SourceEditing
import Testing

struct SourcePatchGitPatchCodecTests {
    @Test
    func printsAddedModifiedAndDeletedFiles() throws {
        let patch = SourcePatch.canonicalFixture

        let data = try SourcePatchGitPatchCodec().format(patch)
        let text = try #require(String(data: data, encoding: .utf8))

        expectNoDifference(
            text,
            """
            diff --git a/events/test/added.md b/events/test/added.md
            new file mode 100644
            --- /dev/null
            +++ b/events/test/added.md
            @@ -0,0 +1 @@
            +Added
            diff --git a/events/test/event.yml b/events/test/event.yml
            --- a/events/test/event.yml
            +++ b/events/test/event.yml
            @@ -1 +1 @@
            -name: Old
            +name: New
            diff --git a/events/test/deleted.md b/events/test/deleted.md
            deleted file mode 100644
            --- a/events/test/deleted.md
            +++ /dev/null
            @@ -1 +0,0 @@
            -Deleted

            """
        )
    }

    @Test
    func parsesPrintedPatch() throws {
        let codec = SourcePatchGitPatchCodec()
        let patch = SourcePatch.canonicalFixture

        let parsedPatch = try codec.parse(try codec.format(patch))

        expectNoDifference(parsedPatch, patch)
    }

    @Test
    func preservesMissingFinalNewlineMarkers() throws {
        let codec = SourcePatchGitPatchCodec()
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/test/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old".utf8),
                    newContents: Data("name: New".utf8)
                )
            ]
        )

        let data = try codec.format(patch)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("\\ No newline at end of file"))
        expectNoDifference(try codec.parse(data), patch)
    }

    @Test
    func rejectsBinaryFiles() throws {
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "image.png",
                    kind: .added,
                    newContents: Data([0xff, 0xfe, 0xfd])
                )
            ]
        )

        let error = #expect(throws: SourcePatchGitPatchCodecError.self) {
            _ = try SourcePatchGitPatchCodec().format(patch)
        }

        expectNoDifference(error, .binaryFile("image.png"))
    }

    @Test
    func rejectsUnsupportedPatchShapes() throws {
        let patch = """
        diff --git a/events/test/event.yml b/events/test/event.yml
        --- a/events/test/event.yml
        +++ b/events/test/event.yml
        @@ -1,2 +1,2 @@
         context
        -name: Old
        +name: New

        """

        let error = #expect(throws: SourcePatchGitPatchCodecError.self) {
            _ = try SourcePatchGitPatchCodec().parse(Data(patch.utf8))
        }

        expectNoDifference(error, .unsupportedPatch("Only full-file hunks are supported."))
    }
}

private extension SourcePatch {
    static let canonicalFixture = SourcePatch(
        fileChanges: [
            SourcePatchFileChange(
                path: "events/test/added.md",
                kind: .added,
                newContents: Data("Added\n".utf8)
            ),
            SourcePatchFileChange(
                path: "events/test/event.yml",
                kind: .modified,
                oldContents: Data("name: Old\n".utf8),
                newContents: Data("name: New\n".utf8)
            ),
            SourcePatchFileChange(
                path: "events/test/deleted.md",
                kind: .deleted,
                oldContents: Data("Deleted\n".utf8)
            ),
        ]
    )
}
