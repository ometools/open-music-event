import CustomDump
import Foundation
import InlineSnapshotTesting
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SnapshotTesting
import SourceEditing
import Testing

@testable import OpenMusicEventAppViewServer

@Suite("Workspace proposal renderer")
struct WorkspaceProposalRendererTests {
    @Test
    func `renders an exact proposal patch through the shared source presentation`() async throws {
        let scratchRootURL = FileManager.default.temporaryDirectory
            .appending(
                path: "ome-workspace-proposal-render-test-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let targetSourceURL = scratchRootURL.appending(
            path: "target-source",
            directoryHint: .isDirectory
        )
        let contributorPath = "events/server-render-2026/contributors/artist.md"
        let contributorURL = targetSourceURL.appending(path: contributorPath)
        try FileManager.default.createDirectory(
            at: contributorURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: scratchRootURL) }

        // The target artifact contains the currently published event and artist profile.
        try """
        name: Server Render Event
        startDate: "2026-08-28"
        endDate: "2026-08-30"
        status: scheduled
        mode: community.lexicon.calendar.event#inperson
        timeZone: America/Denver
        """
        .appending("\n")
        .write(
            to: targetSourceURL.appending(path: "events/server-render-2026/event.yml"),
            atomically: true,
            encoding: .utf8
        )
        let oldContributor = """
        ---
        name: Old Artist
        ---
        Old biography
        """
        .appending("\n")
        try oldContributor.write(to: contributorURL, atomically: true, encoding: .utf8)

        // Tangled supplies a patch that replaces the complete contributor source file.
        let newContributor = """
        ---
        name: New Artist
        ---
        New biography
        """
        .appending("\n")
        let patchData = try SourcePatchGitPatchCodec().formatReviewPatch(
            SourcePatch(
                fileChanges: [
                    SourcePatchFileChange(
                        path: contributorPath,
                        kind: .modified,
                        oldContents: Data(oldContributor.utf8),
                        newContents: Data(newContributor.utf8)
                    )
                ]
            )
        )

        // The server imports both exact sources and renders the same typed value as Workspace.
        let organizerID = try #require(OME.Organizer.ID("did:plc:server-renderer"))
        let presentation = try await WorkspaceProposalRenderer().render(
            workspace: SourceWorkspace(
                organizerID: organizerID,
                repository: "https://tangled.org/example/events",
                branch: "main"
            ),
            targetSourceURL: targetSourceURL,
            patchData: patchData
        )

        expectNoDifference(presentation.totalCount, 1)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        assertInlineSnapshot(
            of: String(decoding: try encoder.encode(presentation), as: UTF8.self),
            as: .lines
        ) {
            #"""
            {
              "formatVersion" : 1,
              "groups" : [
                {
                  "displayName" : "Contributor",
                  "id" : "app.openmusicevent.contributor",
                  "records" : [
                    {
                      "changedFields" : [
                        "bio",
                        "name"
                      ],
                      "id" : "app.openmusicevent.contributor:contributorID=\"artist\",eventID=\"events-server-render-2026\",organizerID=\"did:plc:server-renderer\"",
                      "sourceFiles" : [
                        "events/server-render-2026/contributors/artist.md"
                      ],
                      "title" : "New Artist",
                      "transition" : {
                        "after" : {
                          "$type" : "app.openmusicevent.contributor",
                          "bio" : "New biography\n",
                          "id" : {
                            "contributorID" : "artist",
                            "eventID" : "events-server-render-2026",
                            "organizerID" : "did:plc:server-renderer"
                          },
                          "name" : "New Artist"
                        },
                        "before" : {
                          "$type" : "app.openmusicevent.contributor",
                          "bio" : "Old biography\n",
                          "id" : {
                            "contributorID" : "artist",
                            "eventID" : "events-server-render-2026",
                            "organizerID" : "did:plc:server-renderer"
                          },
                          "name" : "Old Artist"
                        },
                        "kind" : "modified"
                      }
                    }
                  ]
                }
              ]
            }
            """#
        }
    }
}
