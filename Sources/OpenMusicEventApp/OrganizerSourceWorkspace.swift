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
    public var loadRolloverOptions: @Sendable (OrganizerSourceWorkspaceRolloverOptionsRequest) async throws -> OrganizerSourceWorkspaceRolloverOptions

    public init(
        createEvent: @escaping @Sendable (OrganizerSourceWorkspaceCreateEventRequest) async throws -> OMERecord.Event.ID,
        loadRolloverOptions: @escaping @Sendable (OrganizerSourceWorkspaceRolloverOptionsRequest) async throws -> OrganizerSourceWorkspaceRolloverOptions = { _ in
            OrganizerSourceWorkspaceRolloverOptions(sourceEvents: [])
        }
    ) {
        self.createEvent = createEvent
        self.loadRolloverOptions = loadRolloverOptions
    }
}

public struct OrganizerSourceWorkspaceRolloverOptionsRequest: Equatable, Sendable {
    public var organizerID: OMERecord.Organizer.ID
    public var sourceBaselineID: SourceBaselineRecord.ID

    public init(
        organizerID: OMERecord.Organizer.ID,
        sourceBaselineID: SourceBaselineRecord.ID
    ) {
        self.organizerID = organizerID
        self.sourceBaselineID = sourceBaselineID
    }
}

public struct OrganizerSourceWorkspaceRolloverStage: Equatable, Identifiable, Sendable {
    public var id: OMERecord.Stage.ID
    public var name: String
    public var sortIndex: Int?

    public init(
        id: OMERecord.Stage.ID,
        name: String,
        sortIndex: Int?
    ) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
    }
}

public struct OrganizerSourceWorkspaceRolloverSourceEvent: Equatable, Identifiable, Sendable {
    public var endDate: LocalDate?
    public var id: OMERecord.Event.ID
    public var name: String
    public var sourceEventDirectory: String
    public var stages: [OrganizerSourceWorkspaceRolloverStage]
    public var startDate: LocalDate?

    public init(
        endDate: LocalDate?,
        id: OMERecord.Event.ID,
        name: String,
        sourceEventDirectory: String,
        stages: [OrganizerSourceWorkspaceRolloverStage],
        startDate: LocalDate?
    ) {
        self.endDate = endDate
        self.id = id
        self.name = name
        self.sourceEventDirectory = sourceEventDirectory
        self.stages = stages
        self.startDate = startDate
    }
}

public struct OrganizerSourceWorkspaceRolloverOptions: Equatable, Sendable {
    public var sourceEvents: [OrganizerSourceWorkspaceRolloverSourceEvent]

    public init(sourceEvents: [OrganizerSourceWorkspaceRolloverSourceEvent]) {
        self.sourceEvents = sourceEvents
    }
}

public struct OrganizerSourceWorkspaceRollover: Equatable, Sendable {
    public var copySiteMapAndTheme: Bool
    public var copyChannelDefinitions: Bool
    public var copyVenueDetails: Bool
    public var selectedStageIDs: Set<OMERecord.Stage.ID>
    public var sourceEventID: OMERecord.Event.ID

    public init(
        sourceEventID: OMERecord.Event.ID,
        selectedStageIDs: Set<OMERecord.Stage.ID>,
        copyVenueDetails: Bool,
        copySiteMapAndTheme: Bool,
        copyChannelDefinitions: Bool
    ) {
        self.copySiteMapAndTheme = copySiteMapAndTheme
        self.copyChannelDefinitions = copyChannelDefinitions
        self.copyVenueDetails = copyVenueDetails
        self.selectedStageIDs = selectedStageIDs
        self.sourceEventID = sourceEventID
    }
}

public struct OrganizerSourceWorkspaceCreateEventRequest: Equatable, Sendable {
    public var calendarID: OMERecord.Calendar.ID
    public var endDate: LocalDate?
    public var eventDirectoryName: String
    public var eventName: String
    public var organizerID: OMERecord.Organizer.ID
    public var rollover: OrganizerSourceWorkspaceRollover?
    public var sourceBaselineID: SourceBaselineRecord.ID
    public var startDate: LocalDate?
    public var timeZone: TimeZone

    public init(
        calendarID: OMERecord.Calendar.ID,
        endDate: LocalDate? = nil,
        eventDirectoryName: String,
        eventName: String,
        organizerID: OMERecord.Organizer.ID,
        rollover: OrganizerSourceWorkspaceRollover? = nil,
        sourceBaselineID: SourceBaselineRecord.ID,
        startDate: LocalDate? = nil,
        timeZone: TimeZone
    ) {
        self.calendarID = calendarID
        self.endDate = endDate
        self.eventDirectoryName = eventDirectoryName
        self.eventName = eventName
        self.organizerID = organizerID
        self.rollover = rollover
        self.sourceBaselineID = sourceBaselineID
        self.startDate = startDate
        self.timeZone = timeZone
    }
}

public enum OrganizerSourceWorkspaceError: Equatable, Error, Sendable {
    case eventDirectoryAlreadyExists(String)
    case eventImportFailed(String)
    case invalidEventDirectoryName(String)
    case rolloverRequiresDurableSelection
    case rolloverRequiresStages
    case rolloverSourceEventNotFound(OMERecord.Event.ID)
    case sourceBaselineNotFound(SourceBaselineRecord.ID)
}

extension OrganizerSourceWorkspaceClient {
    public static var live: Self {
        Self(
            createEvent: { request in
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

            if let rollover = request.rollover {
                guard !rollover.selectedStageIDs.isEmpty else {
                    throw OrganizerSourceWorkspaceError.rolloverRequiresStages
                }
                guard rollover.copyVenueDetails
                    || rollover.copySiteMapAndTheme
                    || rollover.copyChannelDefinitions
                else {
                    throw OrganizerSourceWorkspaceError.rolloverRequiresDurableSelection
                }
            }

            try await sourceEditModePreparation.prepare(request.sourceBaselineID)

            let sourceProvenance = sourceBaseline.sourceProvenance
            let repositoryURL = try sourceRepositoryStorage.repositoryURL(sourceProvenance)
            let rolloverSource: (event: OpenMusicEventSourceEvent, provenance: EventSourceProvenanceRecord)?
            if let rollover = request.rollover {
                let sourceProvenanceRecord = try await database.read { db in
                    try EventSourceProvenanceRecord
                        .where { $0.id.eq(rollover.sourceEventID) }
                        .where { $0.sourceBaselineID.eq(request.sourceBaselineID) }
                        .fetchOne(db)
                }
                guard let sourceProvenanceRecord else {
                    throw OrganizerSourceWorkspaceError.rolloverSourceEventNotFound(
                        rollover.sourceEventID
                    )
                }
                let sourceEventURL = repositoryURL
                    .appending(path: "events", directoryHint: .isDirectory)
                    .appending(
                        path: sourceProvenanceRecord.sourceEventDirectory,
                        directoryHint: .isDirectory
                    )
                do {
                    rolloverSource = (
                        try readSourceEvent(at: sourceEventURL),
                        sourceProvenanceRecord
                    )
                } catch {
                    throw OrganizerSourceWorkspaceError.eventImportFailed(
                        sourceProvenanceRecord.sourceEventDirectory
                    )
                }
            } else {
                rolloverSource = nil
            }
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
                let sourceFile = try makeSourceFile(
                    event: event,
                    request: request,
                    rolloverSource: rolloverSource
                )
                if let rolloverSource {
                    try copySourceImageFiles(
                        in: sourceFile,
                        from: repositoryURL
                            .appending(path: "events", directoryHint: .isDirectory)
                            .appending(
                                path: rolloverSource.provenance.sourceEventDirectory,
                                directoryHint: .isDirectory
                            ),
                        to: eventDirectoryURL
                    )
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

                    if !insertion.channels.isEmpty {
                        try OMERecord.Channel.insert {
                            insertion.channels
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

                    let workspace = EditingWorkspaceRecord(
                        teamSourceBaseline: sourceBaseline,
                        organizerID: importedEventID.organizerID
                    )
                    try EditingWorkspaceRecord.insert {
                        workspace
                    } onConflict: {
                        $0.id
                    }
                    .execute(db)

                    try EventEditingWorkspaceRecord.insert {
                        EventEditingWorkspaceRecord(
                            id: importedEventID,
                            workspaceID: workspace.id
                        )
                    }
                    .execute(db)
                }

                return importedEventID
            } catch {
                try? FileManager.default.removeItem(at: eventDirectoryURL)
                throw error
            }
            },
            loadRolloverOptions: { request in
                @Dependency(\.defaultDatabase) var database

                let sourceEvents = try await database.read { db in
                    let sourceProvenances = try EventSourceProvenanceRecord
                        .where { $0.sourceBaselineID.eq(request.sourceBaselineID) }
                        .where { $0.id.organizerID.eq(request.organizerID) }
                        .fetchAll(db)
                        .sorted { $0.sourceEventDirectory < $1.sourceEventDirectory }

                    var rolloverEvents: [OrganizerSourceWorkspaceRolloverSourceEvent] = []
                    for provenance in sourceProvenances {
                        let event = try OMERecord.Event
                            .where { event in event.id.eq(provenance.id) }
                            .fetchOne(db)
                        guard let event else { continue }
                        let stages = try OMERecord.Stage
                            .where { $0.id.organizerID.eq(provenance.id.organizerID) }
                            .where { $0.id.eventID.eq(provenance.id.eventID) }
                            .order { ($0.sortIndex.asc(nulls: .last), $0.name.collate(.nocase)) }
                            .fetchAll(db)
                            .map {
                                OrganizerSourceWorkspaceRolloverStage(
                                    id: $0.id,
                                    name: $0.name,
                                    sortIndex: $0.sortIndex
                                )
                            }
                        guard !stages.isEmpty else { continue }
                        rolloverEvents.append(OrganizerSourceWorkspaceRolloverSourceEvent(
                            endDate: event.endDate,
                            id: event.id,
                            name: event.name,
                            sourceEventDirectory: provenance.sourceEventDirectory,
                            stages: stages,
                            startDate: event.startDate
                        ))
                    }
                    return rolloverEvents.sorted { lhs, rhs in
                        if let lhsStartDate = lhs.startDate {
                            if let rhsStartDate = rhs.startDate {
                                if lhsStartDate != rhsStartDate {
                                    return lhsStartDate > rhsStartDate
                                }
                            } else {
                                return true
                            }
                        } else if rhs.startDate != nil {
                            return false
                        }

                        if let lhsEndDate = lhs.endDate {
                            if let rhsEndDate = rhs.endDate {
                                if lhsEndDate != rhsEndDate {
                                    return lhsEndDate > rhsEndDate
                                }
                            } else {
                                return true
                            }
                        } else if rhs.endDate != nil {
                            return false
                        }

                        return lhs.sourceEventDirectory > rhs.sourceEventDirectory
                    }
                }
                return OrganizerSourceWorkspaceRolloverOptions(sourceEvents: sourceEvents)
            }
        )
    }
}

private func readSourceEvent(at url: URL) throws -> OpenMusicEventSourceEvent {
    try OpenMusicEventSourceEventFileTree()
        .read(from: url)
        .output
        .requiredValue
}

private func makeSourceFile(
    event: OMERecord.Event.Draft,
    request: OrganizerSourceWorkspaceCreateEventRequest,
    rolloverSource: (event: OpenMusicEventSourceEvent, provenance: EventSourceProvenanceRecord)?
) throws -> OpenMusicEventSourceEvent {
    var sourceFile = OpenMusicEventSourceEvent(event: event)
    sourceFile.event.id = nil

    guard let rollover = request.rollover, let rolloverSource else {
        sourceFile.stages = [try EventSingletonStage.sourceFile()]
        if request.startDate != nil {
            sourceFile.event.schedule = InlineScheduleDTO(scheduleItems: [:])
        }
        return sourceFile
    }

    guard let sourceStages = rolloverSource.event.stages else {
        throw OrganizerSourceWorkspaceError.rolloverRequiresStages
    }
    let selectedStageIDs = rollover.selectedStageIDs
    let stages = sourceStages.filter { stage in
        let stageID = stage.data.id ?? OMERecord.Stage.ID(
            organizerID: request.organizerID,
            eventID: rollover.sourceEventID.eventID,
            stageID: OMERecord.ID<OMERecord.Stage>(.init(stage.fileName))
        )
        return selectedStageIDs.contains(
            OMERecord.Stage.ID(
                organizerID: request.organizerID,
                eventID: rollover.sourceEventID.eventID,
                stageID: stageID.stageID
            )
        )
    }.map { stage in
        var stage = stage
        stage.data.id = nil
        stage.data.lineup = nil
        stage.data.images = resetImageAssetKeys(stage.data.images)
        return stage
    }
    guard stages.count == selectedStageIDs.count else {
        throw OrganizerSourceWorkspaceError.rolloverRequiresStages
    }
    sourceFile.stages = stages

    if rollover.copyVenueDetails {
        sourceFile.event.description = rolloverSource.event.event.description
        sourceFile.event.locations = rolloverSource.event.event.locations
        sourceFile.event.uris = rolloverSource.event.event.uris
        sourceFile.event.contactNumbers = rolloverSource.event.event.contactNumbers
        sourceFile.event.reportingLinks = rolloverSource.event.event.reportingLinks
    }

    if rollover.copySiteMapAndTheme {
        sourceFile.event.images = resetImageAssetKeys(rolloverSource.event.event.images)
        sourceFile.event.categoryConfigs = rolloverSource.event.event.categoryConfigs
    }

    if rollover.copyChannelDefinitions {
        sourceFile.channels = rolloverSource.event.channels?.map { channel in
            var channel = channel
            channel.data.id = nil
            channel.data.defaultNotificationState = .unsubscribed
            channel.data.notificationsRequired = false
            return channel
        }
    }

    sourceFile.contributors = nil
    sourceFile.posters = nil
    sourceFile.schedules = nil
    if request.startDate != nil {
        sourceFile.event.schedule = InlineScheduleDTO(scheduleItems: [:])
    }
    return sourceFile
}

private func resetImageAssetKeys(
    _ images: [SourceImageAsset]?
) -> [SourceImageAsset]? {
    images?.map { image in
        var image = image
        image.assetKey = nil
        return image
    }
}

private func copySourceImageFiles(
    in sourceEvent: OpenMusicEventSourceEvent,
    from sourceEventURL: URL,
    to destinationEventURL: URL
) throws {
    var paths: [String] = []
    if let images = sourceEvent.event.images {
        paths += images.compactMap(sourceImageFilePath)
    }
    if let stages = sourceEvent.stages {
        for stage in stages {
            if let images = stage.data.images {
                paths += images.compactMap(sourceImageFilePath)
            }
        }
    }

    let sourceRootURL = sourceEventURL.standardizedFileURL
    for path in Set(paths) {
        let sourceURL = sourceEventURL.appending(path: path).standardizedFileURL
        guard sourceURL.path.hasPrefix(sourceRootURL.path + "/") else {
            throw OrganizerSourceWorkspaceError.eventImportFailed(path)
        }
        let destinationURL = destinationEventURL.appending(path: path)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }
}

private func sourceImageFilePath(_ image: SourceImageAsset) -> String? {
    guard case let .file(path) = image.source else { return nil }
    return path
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
