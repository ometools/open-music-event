import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventLexicon
import SQLiteData

public enum ProgramRecordEditing {
    public enum Error: Swift.Error, Equatable {
        case eventUnavailable
        case programUnavailable
        case placeUnavailable
        case placeInUse
        case programInUse
    }

    public static func create(
        eventID: Event.ID,
        title: String,
        description: String? = nil,
        icon: OME.SemanticIcon? = nil,
        eventPlaces: [EventPlace.ID],
        createdAt: Date,
        in db: Database
    ) throws -> Program.ID {
        guard var event = try Event.find(eventID).fetchOne(db) else {
            throw Error.eventUnavailable
        }
        try validatePlaces(eventPlaces, eventID: eventID, in: db)
        let existing = try Program.all.fetchAll(db)
            .filter { $0.id.authority == eventID.authority }
        let previousKey = (existing.map(\.id) + (event.programs ?? []))
            .compactMap(\.rkey)
            .max { $0.rawValue < $1.rawValue }
        let id = try CanonicalRecordID.next(
            collection: Program.lexiconID,
            in: eventID.authority,
            at: createdAt,
            after: previousKey
        )
        var program = try Program(
            id: id,
            event: eventID,
            title: title,
            createdAt: ATProto.DateTime(rawValue: ISO8601DateFormatter().string(from: createdAt)),
            eventPlaces: eventPlaces
        )
        program.description = description
        program.icon = icon
        try program.validateReferences()
        try Program.insert { program }.execute(db)
        event.programs = (event.programs ?? []) + [id]
        try event.validateReferences()
        try Event.upsert { event }.execute(db)
        return id
    }

    public static func update(
        _ programID: Program.ID,
        eventID: Event.ID,
        title: String,
        description: String? = nil,
        icon: OME.SemanticIcon? = nil,
        eventPlaces: [EventPlace.ID],
        in db: Database
    ) throws {
        guard let event = try Event.find(eventID).fetchOne(db) else {
            throw Error.eventUnavailable
        }
        guard var program = try Program.find(programID).fetchOne(db),
              program.event == eventID,
              event.programs?.contains(programID) == true
        else { throw Error.programUnavailable }
        try validatePlaces(eventPlaces, eventID: eventID, in: db)
        let assignedItems = try ProgramItem.where { $0.event.eq(eventID) }.fetchAll(db)
            .filter { $0.program == programID }
        guard assignedItems.allSatisfy({ item in
            item.eventPlace.map(eventPlaces.contains) ?? true
        }) else { throw Error.placeInUse }
        program.title = title
        program.description = description
        program.icon = icon
        program.eventPlaces = eventPlaces
        try program.validateReferences()
        try Program.upsert { program }.execute(db)
    }

    public static func delete(
        _ programID: Program.ID,
        eventID: Event.ID,
        in db: Database
    ) throws {
        guard var event = try Event.find(eventID).fetchOne(db),
              let program = try Program.find(programID).fetchOne(db),
              program.event == eventID,
              event.programs?.contains(programID) == true
        else { throw Error.programUnavailable }
        let assignedItems = try ProgramItem.where { $0.event.eq(eventID) }.fetchAll(db)
        guard !assignedItems.contains(where: { $0.program == programID }) else {
            throw Error.programInUse
        }
        try Program.find(programID).delete().execute(db)
        let remaining = event.programs?.filter { $0 != programID }
        event.programs = remaining?.isEmpty == true ? nil : remaining
        try event.validateReferences()
        try Event.upsert { event }.execute(db)
    }

    private static func validatePlaces(
        _ placeIDs: [EventPlace.ID],
        eventID: Event.ID,
        in db: Database
    ) throws {
        for placeID in placeIDs {
            guard let place = try EventPlace.find(placeID).fetchOne(db),
                  place.event == eventID
            else { throw Error.placeUnavailable }
        }
    }
}
