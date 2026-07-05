import Dependencies
import FileTree
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import OpenMusicEventTimeZones
import SQLiteData

public struct OrganizerSourceWorkspaceClient: Sendable {
    public var createEvent: @Sendable (OrganizerSourceWorkspaceCreateEventRequest) async throws -> OMERecord.Event.ID

    public init(
        createEvent: @escaping @Sendable (OrganizerSourceWorkspaceCreateEventRequest) async throws -> OMERecord.Event.ID
    ) {
        self.createEvent = createEvent
    }
}

public struct OrganizerSourceWorkspaceCreateEventRequest: Equatable, Sendable {
    public var calendarID: OMERecord.Calendar.ID
    public var endDate: LocalDate?
    public var eventDirectoryName: String
    public var eventName: String
    public var organizerID: OMERecord.Organizer.ID
    public var sourceBaselineID: SourceBaselineRecord.ID
    public var startDate: LocalDate?
    public var timeZone: TimeZone

    public init(
        calendarID: OMERecord.Calendar.ID,
        endDate: LocalDate? = nil,
        eventDirectoryName: String,
        eventName: String,
        organizerID: OMERecord.Organizer.ID,
        sourceBaselineID: SourceBaselineRecord.ID,
        startDate: LocalDate? = nil,
        timeZone: TimeZone
    ) {
        self.calendarID = calendarID
        self.endDate = endDate
        self.eventDirectoryName = eventDirectoryName
        self.eventName = eventName
        self.organizerID = organizerID
        self.sourceBaselineID = sourceBaselineID
        self.startDate = startDate
        self.timeZone = timeZone
    }
}

public enum OrganizerSourceWorkspaceError: Equatable, Error, Sendable {
    case eventDirectoryAlreadyExists(String)
    case eventImportFailed(String)
    case invalidEventDirectoryName(String)
    case sourceBaselineNotFound(SourceBaselineRecord.ID)
}

extension OrganizerSourceWorkspaceClient {
    public static var live: Self {
        Self { request in
            @Dependency(\.date) var date
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.sourceEditModePreparation) var sourceEditModePreparation
            @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage

            let eventDirectoryName = request.eventDirectoryName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard OrganizerSourcePathComponent.isValid(eventDirectoryName) else {
                throw OrganizerSourceWorkspaceError.invalidEventDirectoryName(eventDirectoryName)
            }

            let sourceBaseline = try await database.read { db in
                try SourceBaselineRecord
                    .where { $0.id.eq(request.sourceBaselineID) }
                    .fetchOne(db)
            }
            guard let sourceBaseline else {
                throw OrganizerSourceWorkspaceError.sourceBaselineNotFound(request.sourceBaselineID)
            }

            let duplicateCount = try await database.read { db in
                try EventSourceProvenanceRecord
                    .where { $0.sourceBaselineID.eq(request.sourceBaselineID) }
                    .where { $0.sourceEventDirectory.eq(eventDirectoryName) }
                    .fetchCount(db)
            }
            guard duplicateCount == 0 else {
                throw OrganizerSourceWorkspaceError.eventDirectoryAlreadyExists(eventDirectoryName)
            }

            try await sourceEditModePreparation.prepare(request.sourceBaselineID)

            let sourceProvenance = sourceBaseline.sourceProvenance
            let repositoryURL = try sourceRepositoryStorage.repositoryURL(sourceProvenance)
            let eventDirectoryURL = repositoryURL
                .appending(path: "events", directoryHint: .isDirectory)
                .appending(path: eventDirectoryName, directoryHint: .isDirectory)

            guard !FileManager.default.fileExists(atPath: eventDirectoryURL.path) else {
                throw OrganizerSourceWorkspaceError.eventDirectoryAlreadyExists(eventDirectoryName)
            }

            try FileManager.default.createDirectory(
                at: eventDirectoryURL,
                withIntermediateDirectories: true
            )

            do {
                let importedEventID = OMERecord.Event.ID(
                    organizerID: request.organizerID,
                    eventID: OMERecord.SourceDatabaseInsertion.inferredEventID(
                        eventDirectoryName: eventDirectoryName,
                        sourceProvenance: sourceProvenance
                    )
                )
                let event = makeEventDraft(
                    id: importedEventID,
                    name: request.eventName,
                    startDate: request.startDate,
                    endDate: request.endDate,
                    timeZone: request.timeZone
                )
                var sourceFile = OpenMusicEventSourceEvent(event: event)
                sourceFile.event.id = nil
                sourceFile.stages = [try EventSingletonStage.sourceFile()]
                if request.startDate != nil {
                    sourceFile.event.schedule = InlineScheduleDTO(performances: [:])
                }
                _ = try OpenMusicEventSourceEventFileTree()
                    .write(sourceFile, to: eventDirectoryURL)

                let importedSourceFile = try OpenMusicEventSourceEventFileTree()
                    .read(from: eventDirectoryURL)
                    .output
                    .requiredValue
                let insertion = try OMERecord.SourceDatabaseInsertion(
                    OMERecord.SourceDatabaseInsertion.Configuration(
                        source: OpenMusicEventSourceRepository(
                            events: [
                                DirectoryContent(
                                    directoryName: eventDirectoryName,
                                    components: importedSourceFile
                                )
                            ]
                        ),
                        organizerID: request.organizerID,
                        sourceProvenance: sourceProvenance,
                        sourceRootURL: repositoryURL
                    )
                )
                guard let importedEvent = insertion.events.first(where: { $0.id == importedEventID }) else {
                    throw OrganizerSourceWorkspaceError.eventImportFailed(eventDirectoryName)
                }

                try await database.write { db in
                    try insertOrganizerIfNeeded(request.organizerID, in: db)

                    try OMERecord.Event.insert {
                        importedEvent
                    }
                    .execute(db)

                    if !insertion.stages.isEmpty {
                        try OMERecord.Stage.insert {
                            insertion.stages
                        }
                        .execute(db)
                    }

                    if !insertion.schedules.isEmpty {
                        try OMERecord.Schedule.insert {
                            insertion.schedules
                        }
                        .execute(db)
                    }

                    try OMERecord.EventOrganizer.insert {
                        OMERecord.EventOrganizer.Draft(
                            id: .init(
                                organizerID: importedEventID.organizerID,
                                eventID: importedEventID.eventID,
                                eventOrganizerID: request.organizerID
                            )
                        )
                    } onConflict: {
                        (
                            $0.id.organizerID,
                            $0.id.eventID,
                            $0.id.eventOrganizerID
                        )
                    }
                    .execute(db)

                    try OMERecord.CalendarEntry.insert {
                        OMERecord.CalendarEntry.Draft(
                            id: .init(
                                calendarOwnerID: request.calendarID.ownerID,
                                calendarID: request.calendarID.calendarID,
                                entryID: OMERecord.ID<OMERecord.CalendarEntry>(
                                    importedEventID.eventID.rawValue
                                )
                            ),
                            event: OMERecord.Event.reference(id: importedEventID),
                            createdAt: date(),
                            note: nil,
                            pinned: false
                        )
                    }
                    .execute(db)

                    try EventSourceProvenanceRecord.insert {
                        EventSourceProvenanceRecord(
                            id: importedEventID,
                            sourceBaselineID: sourceBaseline.id,
                            sourceKind: sourceProvenance.kind,
                            sourceReference: sourceProvenance.reference,
                            ref: sourceProvenance.ref,
                            eventIDOrigin: .inferred,
                            sourceEventDirectory: eventDirectoryName
                        )
                    }
                    .execute(db)
                }

                return importedEventID
            } catch {
                try? FileManager.default.removeItem(at: eventDirectoryURL)
                throw error
            }
        }
    }
}

enum OrganizerSourcePathComponent {
    static func isValid(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
    }
}

private func insertOrganizerIfNeeded(
    _ organizerID: OMERecord.Organizer.ID,
    in db: Database
) throws {
    let exists = try OMERecord.Organizer
        .where { $0.id.eq(organizerID) }
        .fetchOne(db) != nil
    guard !exists else { return }

    try OMERecord.Organizer.insert {
        OMERecord.Organizer.Draft(id: organizerID)
    }
    .execute(db)
}

private func makeEventDraft(
    id: OMERecord.Event.ID,
    name: String,
    startDate: LocalDate?,
    endDate: LocalDate?,
    timeZone: TimeZone
) -> OMERecord.Event.Draft {
    OMERecord.Event.Draft(
        id: id,
        name: name,
        description: nil,
        startDate: startDate,
        endDate: endDate,
        status: .known(.planned),
        mode: .known(.inPerson),
        locations: nil,
        uris: nil,
        timeZone: timeZone,
        imageURL: nil,
        iconImageURL: nil,
        siteMapImageURL: nil,
        contactNumbers: nil,
        categoryConfigs: nil
    )
}

private enum OrganizerSourceWorkspaceClientKey: DependencyKey {
    static var liveValue: OrganizerSourceWorkspaceClient {
        .live
    }

    static var testValue: OrganizerSourceWorkspaceClient {
        OrganizerSourceWorkspaceClient { _ in
            throw OrganizerSourceWorkspaceError.eventImportFailed("test")
        }
    }
}

public extension DependencyValues {
    var organizerSourceWorkspace: OrganizerSourceWorkspaceClient {
        get { self[OrganizerSourceWorkspaceClientKey.self] }
        set { self[OrganizerSourceWorkspaceClientKey.self] = newValue }
    }
}
