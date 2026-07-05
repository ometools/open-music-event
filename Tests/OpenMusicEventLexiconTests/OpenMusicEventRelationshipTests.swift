import ATProto
import Foundation
import Lexicon
import OpenMusicEventLexicon
import Testing

@Suite("OpenMusicEvent relationships")
struct OpenMusicEventRelationshipTests {
    @Test
    func collectionsExposeNSIDsAndScopes() {
        #expect(OME.RelationshipCollection.relationship.rawValue == "app.openmusicevent.relationship")
        #expect(OME.RelationshipCollection.confirmation.rawValue == "app.openmusicevent.relationship.confirmation")
        #expect(OME.Relationship.nsid == ATProto.NSID("app.openmusicevent.relationship"))
        #expect(OME.RelationshipConfirmation.nsid == ATProto.NSID("app.openmusicevent.relationship.confirmation"))
        #expect(OME.RelationshipCollection.relationship.repoScope == "repo:app.openmusicevent.relationship")
        #expect(OME.RelationshipOAuthScopes.defaultWriteScope.contains("repo:app.openmusicevent.relationship.confirmation"))
    }

    @Test
    func relationshipRecordEncodesCanonicalShape() throws {
        let subjectDID = try #require(DID("did:plc:subject"))
        let objectDID = try #require(DID("did:plc:object"))
        let record = OME.Relationship(
            subject: .identity(did: subjectDID, handle: "alice.example"),
            role: .developer,
            object: .identity(did: objectDID, handle: "app.example"),
            createdAt: "2026-07-04T12:00:00Z"
        )

        let json = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
                as? [String: Any]
        )

        #expect(json["$type"] as? String == "app.openmusicevent.relationship")
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
    func confirmationRecordReferencesRelationship() throws {
        let relationshipURI = try #require(ATProto.URI("at://did:plc:owner/app.openmusicevent.relationship/3relationship"))
        let confirmation = OME.RelationshipConfirmation(
            relationship: .init(uri: relationshipURI, cid: "bafy-relationship"),
            status: .accepted,
            createdAt: "2026-07-04T12:05:00Z"
        )

        let encoded = try JSONEncoder().encode(confirmation)
        let decoded = try JSONDecoder().decode(OME.RelationshipConfirmation.self, from: encoded)

        #expect(decoded.type == "app.openmusicevent.relationship.confirmation")
        #expect(decoded.relationship.uri == relationshipURI)
        #expect(decoded.relationship.cid == "bafy-relationship")
        #expect(decoded.status == .accepted)
    }

    @Test
    func rolesAndStatusesCarryArbitraryStringValues() throws {
        let role = OME.Relationship.Role("translationOf")
        let status = OME.RelationshipConfirmation.Status("disputed")

        #expect(try JSONDecoder().decode(OME.Relationship.Role.self, from: JSONEncoder().encode(role)) == role)
        #expect(try JSONDecoder().decode(OME.RelationshipConfirmation.Status.self, from: JSONEncoder().encode(status)) == status)
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
        #expect(OME.Relationship.Validation.confirmationAuthor(subjectDID, confirms: relationship))
        #expect(!OME.Relationship.Validation.relationshipAuthor(subjectDID, canAssert: relationship))
        #expect(!OME.Relationship.Validation.confirmationAuthor(objectDID, confirms: relationship))
    }
}
