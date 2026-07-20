import Dependencies
import FileTree
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSourceClone

public struct OpenMusicEventSourceValidationRequest: Equatable, Sendable {
    public var source: String
    public var organizerID: OME.Organizer.ID?
    public var ref: String
    public var outputURL: URL?

    public init(
        source: String,
        organizerID: OME.Organizer.ID? = nil,
        ref: String = "HEAD",
        outputURL: URL? = nil
    ) {
        self.source = source
        self.organizerID = organizerID
        self.ref = ref
        self.outputURL = outputURL
    }

    public var resolvedRef: String {
        let trimmedRef = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedRef.isEmpty ? "HEAD" : trimmedRef
    }

    public func tangledSourceProvenance() throws -> OME.SourceDatabaseInsertion.SourceProvenance? {
        switch try SourceRepositoryLocation(parsing: source) {
        case .local:
            return nil

        case let .tangled(repository):
            return OME.SourceDatabaseInsertion.SourceProvenance(
                kind: .tangled,
                reference: repository.normalizedReference,
                ref: resolvedRef
            )

        case let .tangledRepositoryURI(repository):
            return OME.SourceDatabaseInsertion.SourceProvenance(
                kind: .tangled,
                reference: repository.normalizedReference,
                ref: resolvedRef
            )
        }
    }
}

public struct OpenMusicEventSourceValidationResult: Equatable, Sendable {
    public var repositoryURL: URL
    public var organizerID: OME.Organizer.ID
    public var insertion: OME.SourceDatabaseInsertion
    public var insertedEventIDs: [OME.Event.ID]
    public var summary: SourceValidationSummary

    public init(
        repositoryURL: URL,
        organizerID: OME.Organizer.ID,
        insertion: OME.SourceDatabaseInsertion,
        insertedEventIDs: [OME.Event.ID]? = nil,
        summary: SourceValidationSummary
    ) {
        self.repositoryURL = repositoryURL
        self.organizerID = organizerID
        self.insertion = insertion
        self.insertedEventIDs = insertedEventIDs ?? insertion.events.compactMap(\.id)
        self.summary = summary
    }
}

public struct OpenMusicEventSourceValidator: Sendable {
    public var request: OpenMusicEventSourceValidationRequest

    public init(_ request: OpenMusicEventSourceValidationRequest) {
        self.request = request
    }

    public func validate() async throws -> OpenMusicEventSourceValidationResult {
        let location = try SourceRepositoryLocation(parsing: request.source)
        let organizerID = try await resolvedOrganizerID(for: location)
        let (repositoryURL, cleanupURL) = try await resolvedRepositoryURL(for: location)
        let sourceProvenance = OME.SourceDatabaseInsertion.SourceProvenance(
            location: location,
            ref: request.resolvedRef
        )
        defer {
            if let cleanupURL {
                try? FileManager.default.removeItem(at: cleanupURL)
            }
        }

        let sourceResult = try OpenMusicEventSourceRepositoryFileTree().read(from: repositoryURL)
        let source = try sourceResult.output.requiredValue
        let insertion = try OME.SourceDatabaseInsertion(
            .init(
                source: source,
                organizerID: organizerID,
                sourceProvenance: sourceProvenance,
                sourceRootURL: repositoryURL
            )
        )

        return OpenMusicEventSourceValidationResult(
            repositoryURL: repositoryURL,
            organizerID: organizerID,
            insertion: insertion,
            summary: SourceValidationSummary(source: source, insertion: insertion)
        )
    }

    private func resolvedOrganizerID(for location: SourceRepositoryLocation) async throws -> OME.Organizer.ID {
        if let organizerID = request.organizerID {
            return organizerID
        }

        switch location {
        case .local:
            throw OpenMusicEventSourceValidationError.missingOrganizerIDForLocalSource

        case let .tangled(repository):
            let did = try await repository.resolvedOwnerDID()
            guard let organizerID = OME.Organizer.ID(did) else {
                throw OpenMusicEventSourceValidationError.invalidResolvedOrganizerID(did)
            }
            return organizerID

        case let .tangledRepositoryURI(repository):
            let did = try await repository.resolvedOwnerDID()
            guard let organizerID = OME.Organizer.ID(did) else {
                throw OpenMusicEventSourceValidationError.invalidResolvedOrganizerID(did)
            }
            return organizerID
        }
    }

    private func resolvedRepositoryURL(for location: SourceRepositoryLocation) async throws -> (repositoryURL: URL, cleanupURL: URL?) {
        switch location {
        case let .local(repositoryURL):
            guard request.outputURL == nil else {
                throw OpenMusicEventSourceValidationError.outputRequiresTangledSource
            }
            return (repositoryURL, nil)

        case let .tangled(repository):
            return try await resolvedTangledRepositoryURL(repository)

        case let .tangledRepositoryURI(repository):
            return try await resolvedTangledRepositoryURL(repository.repositoryReference)
        }
    }

    private func resolvedTangledRepositoryURL(
        _ repository: TangledRepositoryReference
    ) async throws -> (repositoryURL: URL, cleanupURL: URL?) {
        @Dependency(\.tangledSourceCheckout) var tangledSourceCheckout

        let outputURL: URL
        let cleanupURL: URL?
        if let requestOutputURL = request.outputURL {
            outputURL = requestOutputURL
            cleanupURL = nil
        } else {
            @Dependency(\.uuid) var uuid
            outputURL = TangledSourceCloner.temporaryOutputURL(uuid: uuid())
            cleanupURL = outputURL
        }

        do {
            _ = try await tangledSourceCheckout.checkout(
                TangledSourceCheckoutRequest(
                    repository: repository,
                    ref: request.resolvedRef,
                    outputURL: outputURL
                )
            )
        } catch {
            if let cleanupURL {
                try? FileManager.default.removeItem(at: cleanupURL)
            }
            throw error
        }
        return (outputURL, cleanupURL)
    }
}

private extension OME.SourceDatabaseInsertion.SourceProvenance {
    init(
        location: SourceRepositoryLocation,
        ref: String
    ) {
        switch location {
        case let .local(url):
            self.init(
                kind: .local,
                reference: url.standardizedFileURL.path()
            )

        case let .tangled(repository):
            self.init(
                kind: .tangled,
                reference: repository.normalizedReference,
                ref: ref
            )

        case let .tangledRepositoryURI(repository):
            self.init(
                kind: .tangled,
                reference: repository.normalizedReference,
                ref: ref
            )
        }
    }
}

public enum OpenMusicEventSourceValidationError: Equatable, LocalizedError, Sendable {
    case invalidOrganizerID(String)
    case invalidResolvedOrganizerID(String)
    case missingOrganizerIDForLocalSource
    case outputRequiresTangledSource

    public var errorDescription: String? {
        switch self {
        case let .invalidOrganizerID(organizerID):
            return "Invalid organizer ID: \(organizerID)"

        case let .invalidResolvedOrganizerID(organizerID):
            return "Repository owner did not resolve to a valid organizer DID: \(organizerID)"

        case .missingOrganizerIDForLocalSource:
            return "Cannot infer organizer ID from a local source path. Pass --organizer-id."

        case .outputRequiresTangledSource:
            return "--output can only be used when validating a Tangled repository reference."
        }
    }
}

public struct SourceValidationSummary: CustomStringConvertible, Equatable, Sendable {
    public struct Event: Equatable, Sendable {
        public var eventID: String
        public var name: String

        public init(eventID: String, name: String) {
            self.eventID = eventID
            self.name = name
        }
    }

    public var events: [Event]
    public var stageCount: Int
    public var scheduleCount: Int
    public var contributorCount: Int
    public var channelCount: Int
    public var posterCount: Int
    public var performanceCount: Int
    public var performanceContributorCount: Int

    public init(
        events: [Event],
        stageCount: Int,
        scheduleCount: Int,
        contributorCount: Int,
        channelCount: Int,
        posterCount: Int,
        performanceCount: Int,
        performanceContributorCount: Int
    ) {
        self.events = events
        self.stageCount = stageCount
        self.scheduleCount = scheduleCount
        self.contributorCount = contributorCount
        self.channelCount = channelCount
        self.posterCount = posterCount
        self.performanceCount = performanceCount
        self.performanceContributorCount = performanceContributorCount
    }

    public init(
        source: OpenMusicEventSourceRepository,
        insertion: OME.SourceDatabaseInsertion
    ) {
        self.events = zip(source.events, insertion.events).map { sourceEvent, insertedEvent in
            Event(
                eventID: insertedEvent.id?.eventID.rawValue.rawValue ?? sourceEvent.directoryName,
                name: insertedEvent.name
            )
        }
        self.stageCount = insertion.stages.count
        self.scheduleCount = insertion.schedules.count
        self.contributorCount = insertion.contributors.count
        self.channelCount = insertion.channels.count
        self.posterCount = insertion.posters.count
        self.performanceCount = insertion.performances.count
        self.performanceContributorCount = insertion.performanceContributors.count
    }

    public var description: String {
        """
        Source repository is valid and inserted.
        Events: \(events.count)
        Stages: \(stageCount)
        Schedules: \(scheduleCount)
        Contributors: \(contributorCount)
        Channels: \(channelCount)
        Posters: \(posterCount)
        Performances: \(performanceCount)
        Performance contributors: \(performanceContributorCount)
        """
    }
}
