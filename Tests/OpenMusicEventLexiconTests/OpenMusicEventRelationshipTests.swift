import ATProto
import Foundation
import ATProtoTypes
import OpenMusicEventLexicon
import Testing

@Suite("OpenMusicEvent relationships")
struct OpenMusicEventRelationshipTests {
    @Test
    func publicSchemaValidatesRelationshipWire() throws {
        let schemaURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Lexicons/app/openmusicevent/relationship.json")
        let document = try JSONDecoder().decode(
            Lexicon.Document.self,
            from: Data(contentsOf: schemaURL)
        )
        try SchemaValidator().validate(document)

        let subject = try #require(DID("did:plc:subject"))
        let object = try #require(DID("did:plc:object"))
        let relationship = OME.Relationship(
            subject: .identity(did: subject, handle: "alice.example"),
            role: .collaborator([.propose, .merge]),
            object: .identity(did: object),
            createdAt: "2026-07-29T00:00:00Z"
        )
        let wire = try JSONDecoder().decode(
            Lexicon.JSONValue.self,
            from: JSONEncoder().encode(relationship)
        )
        let schema = try #require(document.defs["main"])
        try SchemaValidator(definitions: LexiconExporter.definitions(in: [document]))
            .validate(wire, against: schema, id: .init(nsid: document.id))
    }

    @Test
    func collectionsExposeNSIDsAndScopes() {
        #expect(OME.RelationshipCollection.relationship.rawValue == "app.openmusicevent.relationship")
        #expect(OME.Relationship.nsid == ATProto.NSID("app.openmusicevent.relationship"))
        #expect(OME.RelationshipCollection.relationship.repoScope == "repo:app.openmusicevent.relationship")
        #expect(OME.RelationshipOAuthScopes.defaultWriteScope == "repo:app.openmusicevent.relationship")
    }

    @Test
    func relationshipRecordEncodesCanonicalShape() throws {
        let subjectDID = try #require(DID("did:plc:subject"))
        let objectDID = try #require(DID("did:plc:object"))
        var record = OME.Relationship(
            subject: .identity(did: subjectDID, handle: "alice.example"),
            role: .developer,
            object: .identity(did: objectDID, handle: "app.example"),
            createdAt: "2026-07-04T12:00:00Z"
        )
        try record.assignRecordID(
            at: try #require(ISO8601DateFormatter().date(from: record.createdAt))
        )
        record.cid = "bafy-relationship"

        let json = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
                as? [String: Any]
        )

        #expect(json["$type"] as? String == "app.openmusicevent.relationship")
        #expect(json["id"] == nil)
        #expect(json["cid"] == nil)
        #expect(json["role"] as? String == "developer")
        #expect(json["createdAt"] as? String == "2026-07-04T12:00:00Z")

        let subject = try #require(json["subject"] as? [String: Any])
        #expect(subject["$type"] as? String == "app.openmusicevent.relationship#identity")
        #expect(subject["did"] as? String == "did:plc:subject")
        #expect(subject["handle"] as? String == "alice.example")

        let object = try #require(json["object"] as? [String: Any])
        #expect(object["did"] as? String == "did:plc:object")
    }

    @Test
    func workspaceCollaboratorRoleRoundTripsWithIndependentCapabilities() throws {
        let collaborator = try #require(DID("did:plc:collaborator"))
        let owner = try #require(DID("did:plc:owner"))
        let workspace = OME.Relationship.RecordReference(
            author: owner,
            collection: OME.SourceRecord.nsid,
            rkey: ATProto.Record.Key(rawValue: OME.SourceRecord.canonicalRecordKey)
        )
        let record = OME.Relationship(
            subject: .identity(did: collaborator, handle: "alice.example"),
            role: .collaborator([.merge]),
            object: .record(workspace),
            createdAt: "2026-07-29T00:00:00Z"
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(OME.Relationship.self, from: data)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["role"] as? String == "collaborator")
        #expect(json["capabilities"] as? [String] == ["merge"])
        #expect(decoded.workspaceRole == .collaborator([.merge]))
        #expect(decoded.workspaceRole?.canEdit == true)
        #expect(decoded.workspaceRole?.canPropose == false)
        #expect(decoded.workspaceRole?.canMerge == true)
    }

    @Test
    func genericOrganizerRoleIsNotAWorkspaceOwnerRole() throws {
        let subjectDID = try #require(DID("did:plc:subject"))
        let relationship = OME.Relationship(
            subject: .identity(did: subjectDID),
            role: .organizer,
            createdAt: "2026-07-29T00:00:00Z"
        )

        #expect(relationship.workspaceRole == nil)
    }

    @Test
    func recordEntityDecodesFromTaggedUnionShape() throws {
        let json = """
        {
          "$type": "app.openmusicevent.relationship",
          "subject": {
            "$type": "app.openmusicevent.relationship#record",
            "uri": "at://did:plc:subject/app.openmusicevent.contributor/runekey",
            "cid": "bafy-subject"
          },
          "role": "performer",
          "object": {
            "$type": "app.openmusicevent.relationship#record",
            "uri": "at://did:plc:object/app.openmusicevent.performance/friday-the-portal-1"
          },
          "createdAt": "2026-07-04T12:00:00Z"
        }
        """.data(using: .utf8)!

        let relationship = try JSONDecoder().decode(OME.Relationship.self, from: json)

        #expect(relationship.type == "app.openmusicevent.relationship")
        #expect(relationship.role == OME.Relationship.Role.performer)

        guard case let .known(.record(subject)) = relationship.subject else {
            Issue.record("Expected subject to decode as a known record entity.")
            return
        }
        #expect(subject.cid == "bafy-subject")
        #expect(subject.uri.description == "at://did:plc:subject/app.openmusicevent.contributor/runekey")

        guard case let .known(.record(object)) = relationship.object else {
            Issue.record("Expected object to decode as a known record entity.")
            return
        }
        #expect(object.uri.description == "at://did:plc:object/app.openmusicevent.performance/friday-the-portal-1")
    }

    @Test
    func rolesCarryArbitraryStringValues() throws {
        let role = OME.Relationship.Role("translationOf")

        #expect(try JSONDecoder().decode(OME.Relationship.Role.self, from: JSONEncoder().encode(role)) == role)
    }

    @Test
    func recordReferencesCanBeBuiltFromOMERecordParts() throws {
        let author = try #require(DID("did:plc:author"))
        let reference = OME.Relationship.RecordReference(
            author: author,
            collection: OME.Contributor.nsid,
            rkey: ATProto.Record.Key("runekey"),
            cid: "bafy-contributor"
        )

        #expect(reference.uri.description == "at://did:plc:author/app.openmusicevent.contributor/runekey")
        #expect(reference.cid == "bafy-contributor")
    }

    @Test
    func recordBackedRelationshipUsesRecordSubjectAndObject() throws {
        let author = try #require(DID("did:plc:owner"))
        let contributor = OME.Relationship.RecordReference(
            author: author,
            collection: OME.Contributor.nsid,
            rkey: ATProto.Record.Key("runekey")
        )
        let performance = OME.Relationship.RecordReference(
            author: author,
            collection: OME.Performance.nsid,
            rkey: ATProto.Record.Key("friday-the-portal-1")
        )
        let relationship = OME.Relationship(
            subject: contributor,
            role: .performer,
            object: performance,
            createdAt: "2026-07-04T12:00:00Z"
        )

        #expect(relationship.role == .performer)
        #expect(OME.Relationship.Validation.relationshipAuthor(author, canAssert: relationship))

        guard case let .known(.record(subject)) = relationship.subject else {
            Issue.record("Expected subject to be a known record entity.")
            return
        }
        guard case let .known(.record(object)) = relationship.object else {
            Issue.record("Expected object to be a known record entity.")
            return
        }

        #expect(subject == contributor)
        #expect(object == performance)
    }

    @Test
    func validationMatchesRepoAuthorsToEntities() throws {
        let subjectDID = try #require(DID("did:plc:subject"))
        let objectDID = try #require(DID("did:plc:object"))
        let relationship = OME.Relationship(
            subject: .identity(did: subjectDID),
            role: .developer,
            object: .identity(did: objectDID),
            createdAt: "2026-07-04T12:00:00Z"
        )

        #expect(OME.Relationship.Validation.relationshipAuthor(objectDID, canAssert: relationship))
        #expect(!OME.Relationship.Validation.relationshipAuthor(subjectDID, canAssert: relationship))
    }
}
