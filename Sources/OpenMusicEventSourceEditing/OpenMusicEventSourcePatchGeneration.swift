import Dependencies
import FileTree
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData
import SourceEditing

public struct OpenMusicEventSourcePatchRequest: Equatable, Sendable {
    public var eventID: OME.Event.ID

    public init(eventID: OME.Event.ID) {
        self.eventID = eventID
    }
}

public struct OpenMusicEventCalendarSourcePatchRequest: Equatable, Sendable {
    public var calendarID: OME.Calendar.ID
    public var sourceBaselineID: SourceBaselineRecord.ID

    public init(
        calendarID: OME.Calendar.ID,
        sourceBaselineID: SourceBaselineRecord.ID
    ) {
        self.calendarID = calendarID
        self.sourceBaselineID = sourceBaselineID
    }
}

public enum OpenMusicEventSourceTarget: Equatable, Hashable, Identifiable, Sendable {
    case calendar(OME.Calendar.ID, SourceBaselineRecord.ID)
    case event(OME.Event.ID)

    public var id: String {
        switch self {
        case let .calendar(calendarID, sourceBaselineID):
            "calendar:\(calendarID.ownerID):\(calendarID.calendarID.rawValue.rawValue):\(sourceBaselineID.rawValue)"
        case let .event(eventID):
            "event:\(eventID.organizerID):\(eventID.eventID.rawValue.rawValue)"
        }
    }

    public var calendarSourcePatchRequest: OpenMusicEventCalendarSourcePatchRequest? {
        guard case let .calendar(calendarID, sourceBaselineID) = self else { return nil }
        return OpenMusicEventCalendarSourcePatchRequest(
            calendarID: calendarID,
            sourceBaselineID: sourceBaselineID
        )
    }

    public var eventID: OME.Event.ID? {
        guard case let .event(eventID) = self else { return nil }
        return eventID
    }

    public var eventSourcePatchRequest: OpenMusicEventSourcePatchRequest? {
        guard case let .event(eventID) = self else { return nil }
        return OpenMusicEventSourcePatchRequest(eventID: eventID)
    }

    public var organizerID: OME.Organizer.ID {
        switch self {
        case let .calendar(calendarID, _):
            calendarID.ownerID
        case let .event(eventID):
            eventID.organizerID
        }
    }

    public var sourceBaselineID: SourceBaselineRecord.ID? {
        guard case let .calendar(_, sourceBaselineID) = self else { return nil }
        return sourceBaselineID
    }
}

public enum OpenMusicEventSourcePatchGenerationError: Equatable, Error, Sendable {
    case notSourceBacked(OME.Event.ID)
    case sourceBaselineNotFound(SourceBaselineRecord.ID)
}

public struct OpenMusicEventSourcePatchLocationResolver: Sendable {
    public var resolve: @Sendable (OpenMusicEventSourcePatchRequest) async throws -> SourcePatchLocation

    public init(
        resolve: @escaping @Sendable (OpenMusicEventSourcePatchRequest) async throws -> SourcePatchLocation
    ) {
        self.resolve = resolve
    }
}

public struct OpenMusicEventCalendarSourcePatchLocationResolver: Sendable {
    public var resolve: @Sendable (OpenMusicEventCalendarSourcePatchRequest) async throws -> SourcePatchLocation

    public init(
        resolve: @escaping @Sendable (OpenMusicEventCalendarSourcePatchRequest) async throws -> SourcePatchLocation
    ) {
        self.resolve = resolve
    }
}

public struct OpenMusicEventSourcePatchConversion: Sendable {
    public var update: @Sendable (
        OpenMusicEventSourceEvent,
        OpenMusicEventSourcePatchRequest
    ) async throws -> OpenMusicEventSourceEvent

    public init(
        update: @escaping @Sendable (
            OpenMusicEventSourceEvent,
            OpenMusicEventSourcePatchRequest
        ) async throws -> OpenMusicEventSourceEvent
    ) {
        self.update = update
    }
}

public struct OpenMusicEventCalendarSourcePatchConversion: Sendable {
    public var update: @Sendable (
        OpenMusicEventSourceRepository,
        OpenMusicEventCalendarSourcePatchRequest
    ) async throws -> OpenMusicEventSourceRepository

    public init(
        update: @escaping @Sendable (
            OpenMusicEventSourceRepository,
            OpenMusicEventCalendarSourcePatchRequest
        ) async throws -> OpenMusicEventSourceRepository
    ) {
        self.update = update
    }
}

public extension OpenMusicEventSourcePatchConversion {
    static var identity: Self {
        Self { sourceEvent, _ in sourceEvent }
    }
}

public extension OpenMusicEventCalendarSourcePatchConversion {
    static var identity: Self {
        Self { sourceRepository, _ in sourceRepository }
    }
}

public extension OpenMusicEventSourcePatchLocationResolver {
    static var openMusicEvent: Self {
        Self { request in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage

            let provenance = try await database.read { db in
                let provenance = try EventSourceProvenanceRecord
                    .where { $0.id.eq(request.eventID) }
                    .fetchOne(db)
                guard let provenance else {
                    throw OpenMusicEventSourcePatchGenerationError.notSourceBacked(request.eventID)
                }
                return provenance
            }
            return SourcePatchLocation(
                repositoryURL: try sourceRepositoryStorage.repositoryURL(provenance.sourceProvenance),
                relativePath: "events/\(provenance.sourceEventDirectory)",
                remote: SourcePatchLocation.Remote(
                    kind: provenance.sourceKind.rawValue,
                    reference: provenance.sourceReference,
                    ref: provenance.ref
                )
            )
        }
    }
}

public extension OpenMusicEventCalendarSourcePatchLocationResolver {
    static var openMusicEvent: Self {
        Self { request in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage

            let sourceBaseline = try await database.read { db in
                try SourceBaselineRecord
                    .where { $0.id.eq(request.sourceBaselineID) }
                    .fetchOne(db)
            }
            guard let sourceBaseline else {
                throw OpenMusicEventSourcePatchGenerationError.sourceBaselineNotFound(request.sourceBaselineID)
            }

            return SourcePatchLocation(
                repositoryURL: try sourceRepositoryStorage.repositoryURL(sourceBaseline.sourceProvenance),
                relativePath: nil,
                remote: SourcePatchLocation.Remote(
                    kind: sourceBaseline.sourceKind.rawValue,
                    reference: sourceBaseline.sourceReference,
                    ref: sourceBaseline.ref
                )
            )
        }
    }
}

public extension OpenMusicEventSourceTarget {
    func resolveLocation(
        calendarSourcePatchLocationResolver: OpenMusicEventCalendarSourcePatchLocationResolver,
        sourcePatchLocationResolver: OpenMusicEventSourcePatchLocationResolver
    ) async throws -> SourcePatchLocation {
        switch self {
        case let .calendar(calendarID, sourceBaselineID):
            try await calendarSourcePatchLocationResolver.resolve(
                OpenMusicEventCalendarSourcePatchRequest(
                    calendarID: calendarID,
                    sourceBaselineID: sourceBaselineID
                )
            )

        case let .event(eventID):
            try await sourcePatchLocationResolver.resolve(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }
    }
}

public extension SourcePatchGenerator where Request == OpenMusicEventSourcePatchRequest {
    static var openMusicEvent: Self {
        Self { request in
            @Dependency(\.openMusicEventSourcePatchLocationResolver) var resolver
            @Dependency(\.openMusicEventSourcePatchConversion) var conversion
            @Dependency(\.sourcePatchDiffer) var sourcePatchDiffer
            @Dependency(\.sourceWorkingTreeMaterializer) var sourceWorkingTreeMaterializer

            let location = try await resolver.resolve(request)
            guard let eventRelativePath = location.relativePath else {
                return try await Self.existingOpenMusicEvent.generate(request)
            }
            let existingEventURL = try location.repositoryURL.appendingValidatedRelativePath(eventRelativePath)

            guard !FileManager.default.fileExists(atPath: existingEventURL.path) else {
                return try await Self.existingOpenMusicEvent.generate(request)
            }

            let workingTree = try sourceWorkingTreeMaterializer.materialize(
                location.repositoryURL,
                nil
            )
            defer {
                try? FileManager.default.removeItem(at: workingTree.workingRepositoryURL)
            }

            let workingEventURL = try workingTree.workingRepositoryURL
                .appendingValidatedRelativePath(eventRelativePath)
            try FileManager.default.createDirectory(
                at: workingEventURL,
                withIntermediateDirectories: true
            )
            let sourceEvent = try await conversion.update(.emptyForNewSourcePatch, request)
            let materializedSourceEvent = try sourceEvent
                .materializingLocalImageFiles(at: workingEventURL)
            _ = try OpenMusicEventSourceEventFileTree()
                .write(materializedSourceEvent, to: workingEventURL)

            return try sourcePatchDiffer.diff(
                workingTree.originalURL,
                workingTree.workingURL,
                workingTree.originalRepositoryURL
            )
        }
    }

    private static var existingOpenMusicEvent: Self {
        .live(
            resolveLocation: { request in
                @Dependency(\.openMusicEventSourcePatchLocationResolver) var resolver
                return try await resolver.resolve(request)
            },
            read: { sourceURL in
                try OpenMusicEventSourceEventFileTree()
                    .read(from: sourceURL)
                    .output
                    .requiredValue
            },
            update: { sourceEvent, request in
                @Dependency(\.openMusicEventSourcePatchConversion) var conversion
                return try await conversion.update(sourceEvent, request)
            },
            rewrite: { sourceEvent, workingURL in
                let materializedSourceEvent = try sourceEvent
                    .materializingLocalImageFiles(at: workingURL)
                _ = try OpenMusicEventSourceEventFileTree()
                    .rewrite(materializedSourceEvent, at: workingURL)
            }
        )
    }
}

public extension SourcePatchGenerator where Request == OpenMusicEventCalendarSourcePatchRequest {
    static var openMusicEventCalendar: Self {
        .live(
            resolveLocation: { request in
                @Dependency(\.openMusicEventCalendarSourcePatchLocationResolver) var resolver
                return try await resolver.resolve(request)
            },
            read: { sourceURL in
                try OpenMusicEventSourceRepositoryFileTree()
                    .read(from: sourceURL)
                    .output
                    .requiredValue
            },
            update: { sourceRepository, request in
                @Dependency(\.openMusicEventCalendarSourcePatchConversion) var conversion
                return try await conversion.update(sourceRepository, request)
            },
            rewrite: { sourceRepository, workingURL in
                let materializedSourceRepository = try sourceRepository
                    .materializingLocalImageFiles(at: workingURL)
                _ = try OpenMusicEventSourceRepositoryFileTree()
                    .rewrite(materializedSourceRepository, at: workingURL)
            }
        )
    }
}

public extension DependencyValues {
    var openMusicEventSourcePatchLocationResolver: OpenMusicEventSourcePatchLocationResolver {
        get { self[OpenMusicEventSourcePatchLocationResolverKey.self] }
        set { self[OpenMusicEventSourcePatchLocationResolverKey.self] = newValue }
    }

    var openMusicEventSourcePatchConversion: OpenMusicEventSourcePatchConversion {
        get { self[OpenMusicEventSourcePatchConversionKey.self] }
        set { self[OpenMusicEventSourcePatchConversionKey.self] = newValue }
    }

    var openMusicEventCalendarSourcePatchLocationResolver: OpenMusicEventCalendarSourcePatchLocationResolver {
        get { self[OpenMusicEventCalendarSourcePatchLocationResolverKey.self] }
        set { self[OpenMusicEventCalendarSourcePatchLocationResolverKey.self] = newValue }
    }

    var openMusicEventCalendarSourcePatchConversion: OpenMusicEventCalendarSourcePatchConversion {
        get { self[OpenMusicEventCalendarSourcePatchConversionKey.self] }
        set { self[OpenMusicEventCalendarSourcePatchConversionKey.self] = newValue }
    }
}

private enum OpenMusicEventSourcePatchLocationResolverKey: DependencyKey {
    static var liveValue: OpenMusicEventSourcePatchLocationResolver {
        .openMusicEvent
    }

    static var testValue: OpenMusicEventSourcePatchLocationResolver {
        .openMusicEvent
    }
}

private enum OpenMusicEventSourcePatchConversionKey: DependencyKey {
    static var liveValue: OpenMusicEventSourcePatchConversion {
        .live
    }

    static var testValue: OpenMusicEventSourcePatchConversion {
        .identity
    }
}

private enum OpenMusicEventCalendarSourcePatchLocationResolverKey: DependencyKey {
    static var liveValue: OpenMusicEventCalendarSourcePatchLocationResolver {
        .openMusicEvent
    }

    static var testValue: OpenMusicEventCalendarSourcePatchLocationResolver {
        .openMusicEvent
    }
}

private enum OpenMusicEventCalendarSourcePatchConversionKey: DependencyKey {
    static var liveValue: OpenMusicEventCalendarSourcePatchConversion {
        .live
    }

    static var testValue: OpenMusicEventCalendarSourcePatchConversion {
        .identity
    }
}

extension OpenMusicEventSourceEvent {
    static var emptyForNewSourcePatch: Self {
        OpenMusicEventSourceEvent(
            event: EventDTO(
                id: nil,
                name: "",
                description: nil,
                startDate: nil,
                endDate: nil,
                status: nil,
                mode: nil,
                locations: nil,
                uris: nil,
                timeZone: TimeZone(secondsFromGMT: 0)!,
                images: nil,
                contactNumbers: nil,
                categoryConfigs: nil
            )
        )
    }
}

private extension URL {
    func appendingValidatedRelativePath(_ relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/") else {
            throw SourceWorkingTreeMaterializerError.invalidRelativePath(relativePath)
        }

        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty,
              !components.contains("."),
              !components.contains("..")
        else {
            throw SourceWorkingTreeMaterializerError.invalidRelativePath(relativePath)
        }

        return components.reduce(self.standardizedFileURL) { url, component in
            url.appending(path: component)
        }
        .standardizedFileURL
    }
}
