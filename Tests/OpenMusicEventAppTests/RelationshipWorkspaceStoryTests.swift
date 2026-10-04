import ATProto
import Bluesky
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@testable import OpenMusicEventAppEventViewer

@MainActor
@Suite("Relationship workspace", .serialized)
struct RelationshipWorkspaceStoryTests {
    @Test
    func `record subject CID survives form editing and can be cleared`() throws {
        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let subjectURI = try #require(ATProto.URI(
            "at://did:plc:artist123/events.openmusic.stage/3mrdbziccpcai"
        ))
        let cid = ATProto.CID(rawValue: "bafyreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku")
        let subject = OME.Relationship.RecordReference(uri: subjectURI, cid: cid)
        let relationship = OME.Relationship(
            subject: .record(subject),
            role: .performer,
            object: .record(.init(uri: eventID)),
            createdAt: "2026-09-01T12:00:00Z"
        )

        var form = RelationshipForm.State(eventID: eventID, relationship: relationship)
        #expect(form.subjectRecordCID == cid.description)
        #expect(form.preparedFields?.subject == .known(.record(subject)))

        form.role = "organizer"
        #expect(form.preparedFields?.subject == .known(.record(subject)))

        form.subjectRecordCID = ""
        #expect(form.preparedFields?.subject == .known(.record(.init(uri: subjectURI))))
    }

    @Test
    func `owner adds edits and removes a relationship from its event list`() async throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let event = try Event(
            id: eventID,
            name: "Wicked Woods",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        try await database.write { try Event.insert { event }.execute($0) }

        let store: StoreOf<RelationshipList> = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.date = .constant(Date(timeIntervalSince1970: 1_788_000_000))
        } operation: {
            Store(initialState: RelationshipList.State(eventID: eventID)) {
                RelationshipList()
            }
        }

        await store.send(.addButtonTapped)?.value
        let newForm: StoreOf<RelationshipForm>
        switch RelationshipList.Destination.switch(store: try #require(store.scope(\.destination))) {
        case let .relationshipForm(form): newForm = form
        }
        let identity = ActorIdentity(
            did: try #require(DID("did:plc:alice123")),
            displayName: "Alice",
            source: .canonicalResolution
        )
        await newForm.send(.actorIdentityTapped(identity))?.value
        await newForm.send(.saveButtonTapped)?.value

        let created = try await database.read { db in
            try #require(try OME.Relationship.all.fetchOne(db))
        }
        let id = try #require(created.id)
        #expect(store.eventRelationships.map(\.id) == [id])
        #expect(created.role == .collaborator)

        await store.send(.editButtonTapped(id))?.value
        let editForm: StoreOf<RelationshipForm>
        switch RelationshipList.Destination.switch(store: try #require(store.scope(\.destination))) {
        case let .relationshipForm(form): editForm = form
        }
        await editForm.send(.roleSelected(.organizer))?.value
        await editForm.send(.saveButtonTapped)?.value
        let updated = try await database.read { db in
            try #require(try OME.Relationship.where { $0.id.eq(id) }.fetchOne(db))
        }
        #expect(updated.role == .organizer)
        #expect(updated.id == id)
        #expect(updated.createdAt == created.createdAt)

        await store.send(.deleteButtonTapped(id))?.value
        await store.send(.deleteConfirmed)?.value
        let remaining = try await database.read { try OME.Relationship.all.fetchAll($0) }
        #expect(remaining.isEmpty)
        #expect(store.eventRelationships.isEmpty)
    }
}
