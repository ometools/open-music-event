import CustomDump
import Foundation
import GRDB
import InlineSnapshotTesting
import ATProtoTypes
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SQLiteData
import SnapshotTesting
import SourceEditing
import Testing

@Suite("Source change presentation")
struct SourceChangePresentationTests {
    @Test
    func contributorSnapshotsRoundTripAsCompleteRecords() throws {
        let baselineDatabase = try sourcePresentationDatabase()
        let workingDatabase = try sourcePresentationDatabase()
        let organizerID = try #require(OME.Organizer.ID("did:plc:source-presentation"))
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: OME.ID<OME.Event>("event")
        )
        let contributorID = OME.Contributor.ID(
            organizerID: organizerID,
            eventID: eventID.eventID,
            contributorID: OME.ID<OME.Contributor>("artist")
        )

        try baselineDatabase.write { db in
            try insertSourcePresentationContributor(
                id: contributorID,
                name: "Old Artist",
                bio: "Old biography",
                in: db
            )
        }
        try workingDatabase.write { db in
            try insertSourcePresentationContributor(
                id: contributorID,
                name: "New Artist",
                bio: "New biography",
                in: db
            )
        }

        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/example/events",
            branch: "main"
        )
        let summary = try workingDatabase.read { working in
            try baselineDatabase.read { baseline in
                try openMusicEventSourceEditSummary(
                    workspace: workspace,
                    workingDatabase: working,
                    baselineDatabase: baseline
                )
            }
        }
        let presentation = try SourceChangePresentationRenderer().render(summary)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let encodedPresentation = try encoder.encode(presentation)
        assertInlineSnapshot(
            of: String(decoding: encodedPresentation, as: UTF8.self),
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
                      "id" : "app.openmusicevent.contributor:contributorID=\"artist\",eventID=\"event\",organizerID=\"did:plc:source-presentation\"",
                      "sourceFiles" : [

                      ],
                      "title" : "New Artist",
                      "transition" : {
                        "after" : {
                          "$type" : "app.openmusicevent.contributor",
                          "bio" : "New biography",
                          "id" : {
                            "contributorID" : "artist",
                            "eventID" : "event",
                            "organizerID" : "did:plc:source-presentation"
                          },
                          "name" : "New Artist"
                        },
                        "before" : {
                          "$type" : "app.openmusicevent.contributor",
                          "bio" : "Old biography",
                          "id" : {
                            "contributorID" : "artist",
                            "eventID" : "event",
                            "organizerID" : "did:plc:source-presentation"
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
        let decodedPresentation = try JSONDecoder().decode(
            OME.WorkspaceProposal.Presentation.self,
            from: encodedPresentation
        )
        let contributor = try #require(
            decodedPresentation.groups
                .first { $0.id == OME.Contributor.tableName }?
                .records.first
        )

        #expect(contributor.title == "New Artist")
        expectNoDifference(
            Set(contributor.changedFields),
            Set(["name", "bio"])
        )
        #expect(contributor.transition.kind == .modified)
        let beforeRecord = try #require(contributor.transition.before)
        let afterRecord = try #require(contributor.transition.after)
        #expect(beforeRecord.object?["$type"]?.string == OME.Contributor.nsid.rawValue)
        #expect(afterRecord.object?["$type"]?.string == OME.Contributor.nsid.rawValue)
        let before = try JSONDecoder().decode(OME.Contributor.self, from: JSONEncoder().encode(beforeRecord))
        let after = try JSONDecoder().decode(OME.Contributor.self, from: JSONEncoder().encode(afterRecord))
        let expectedBefore = try baselineDatabase.read { db in
            let contributor = try OME.Contributor.find(contributorID).fetchOne(db)
            return try #require(contributor)
        }
        let expectedAfter = try workingDatabase.read { db in
            let contributor = try OME.Contributor.find(contributorID).fetchOne(db)
            return try #require(contributor)
        }
        expectNoDifference(
            before,
            expectedBefore
        )
        expectNoDifference(
            after,
            expectedAfter
        )
    }
}

private func sourcePresentationDatabase() throws -> any DatabaseWriter {
    let database = try SQLiteData.defaultDatabase()
    var migrator = DatabaseMigrator()
    OME.DatabaseMigrations.register(into: &migrator)
    try migrator.migrate(database)
    return database
}

private func insertSourcePresentationContributor(
    id: OME.Contributor.ID,
    name: String,
    bio: String,
    in db: Database
) throws {
    let timeZone = try #require(TimeZone(secondsFromGMT: 0))
    try OME.Organizer.insert {
        OME.Organizer.Draft(id: id.organizerID)
    }
    .execute(db)
    try OME.Event.insert {
        OME.Event.Draft(
            id: OME.Event.ID(
                organizerID: id.organizerID,
                eventID: id.eventID
            ),
            name: "Source Presentation Event",
            description: nil,
            startDate: nil,
            endDate: nil,
            status: nil,
            mode: nil,
            locations: nil,
            uris: nil,
            timeZone: timeZone,
            images: nil,
            contactNumbers: nil
        )
    }
    .execute(db)
    try OME.Contributor.insert {
        OME.Contributor.Draft(
            id: id,
            name: name,
            did: nil,
            bio: bio,
            images: nil,
            links: nil
        )
    }
    .execute(db)
}
