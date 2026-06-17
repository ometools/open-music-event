import ATProto
import Dependencies
import FileTree
import Foundation
import OpenMusicEventLexicon

public struct SourceActorDIDConversionRequest: Equatable, Sendable {
    public var repositoryURL: URL
    public var eventDirectory: String?
    public var apply: Bool
    public var allowUnresolved: Bool
    public var overrides: [String: String]
    public var resolutionParallelism: Int
    public var resolutionTimeoutSeconds: Int

    public init(
        repositoryURL: URL,
        eventDirectory: String? = nil,
        apply: Bool = false,
        allowUnresolved: Bool = false,
        overrides: [String: String] = [:],
        resolutionParallelism: Int = 16,
        resolutionTimeoutSeconds: Int = 5
    ) {
        self.repositoryURL = repositoryURL.standardizedFileURL
        self.eventDirectory = eventDirectory
        self.apply = apply
        self.allowUnresolved = allowUnresolved
        self.overrides = overrides
        self.resolutionParallelism = max(1, resolutionParallelism)
        self.resolutionTimeoutSeconds = max(1, resolutionTimeoutSeconds)
    }
}

public struct SourceActorDIDConversionLocation: Equatable, Sendable, CustomStringConvertible {
    public var file: String
    public var eventDirectory: String
    public var scheduleFileName: String
    public var stageID: String
    public var performanceIndex: Int
    public var performanceTitle: String
    public var actorIndex: Int

    public init(
        file: String,
        eventDirectory: String,
        scheduleFileName: String,
        stageID: String,
        performanceIndex: Int,
        performanceTitle: String,
        actorIndex: Int
    ) {
        self.file = file
        self.eventDirectory = eventDirectory
        self.scheduleFileName = scheduleFileName
        self.stageID = stageID
        self.performanceIndex = performanceIndex
        self.performanceTitle = performanceTitle
        self.actorIndex = actorIndex
    }

    public var description: String {
        "\(file) stage=\(stageID) performance[\(performanceIndex)] \"\(performanceTitle)\" actor[\(actorIndex)]"
    }
}

public struct SourceActorDIDConversionResult: Equatable, Sendable {
    public struct Replacement: Equatable, Sendable {
        public enum Source: String, Equatable, Sendable {
            case resolved
            case override
        }

        public var location: SourceActorDIDConversionLocation
        public var handle: String
        public var did: String
        public var source: Source

        public init(
            location: SourceActorDIDConversionLocation,
            handle: String,
            did: String,
            source: Source
        ) {
            self.location = location
            self.handle = handle
            self.did = did
            self.source = source
        }
    }

    public struct UnresolvedHandle: Equatable, Sendable {
        public var location: SourceActorDIDConversionLocation
        public var handle: String
        public var errorDescription: String

        public init(
            location: SourceActorDIDConversionLocation,
            handle: String,
            errorDescription: String
        ) {
            self.location = location
            self.handle = handle
            self.errorDescription = errorDescription
        }
    }

    public struct DIDReference: Equatable, Sendable {
        public var location: SourceActorDIDConversionLocation
        public var did: String

        public init(location: SourceActorDIDConversionLocation, did: String) {
            self.location = location
            self.did = did
        }
    }

    public var replacements: [Replacement]
    public var unresolvedHandles: [UnresolvedHandle]
    public var unchangedDIDReferences: [DIDReference]
    public var touchedFiles: [String]
    public var didWrite: Bool

    public init(
        replacements: [Replacement],
        unresolvedHandles: [UnresolvedHandle],
        unchangedDIDReferences: [DIDReference],
        touchedFiles: [String],
        didWrite: Bool
    ) {
        self.replacements = replacements
        self.unresolvedHandles = unresolvedHandles
        self.unchangedDIDReferences = unchangedDIDReferences
        self.touchedFiles = touchedFiles
        self.didWrite = didWrite
    }
}

public enum SourceActorDIDConversionError: Equatable, LocalizedError, Sendable {
    case invalidOverrideHandle(String)
    case invalidOverrideDID(handle: String, did: String)
    case unresolvedHandles([SourceActorDIDConversionResult.UnresolvedHandle])

    public var errorDescription: String? {
        switch self {
        case let .invalidOverrideHandle(handle):
            return "Invalid override handle: \(handle)"

        case let .invalidOverrideDID(handle, did):
            return "Override for \(handle) must be a DID, got: \(did)"

        case let .unresolvedHandles(handles):
            return "Could not resolve \(handles.count) contributor actor handle(s). Pass --allow-unresolved to apply resolved replacements anyway."
        }
    }
}

public enum SourceActorDIDConversionProgress: Equatable, Sendable {
    case readingRepository(URL)
    case repositoryRead(eventCount: Int)
    case validatingOverrides(count: Int)
    case discoveringActors(eventDirectory: String?)
    case actorsDiscovered(
        actorReferenceCount: Int,
        handleReferenceCount: Int,
        didReferenceCount: Int,
        uniqueHandleCount: Int,
        scheduleFileCount: Int
    )
    case resolvingHandles(
        uniqueHandleCount: Int,
        overrideCount: Int,
        parallelism: Int,
        timeoutSeconds: Int
    )
    case resolvingHandle(handle: String, index: Int, total: Int)
    case handleResolved(
        handle: String,
        index: Int,
        total: Int,
        source: SourceActorDIDConversionResult.Replacement.Source
    )
    case handleResolutionFailed(
        handle: String,
        index: Int,
        total: Int,
        errorDescription: String
    )
    case buildingResult
    case checkingApplyPreconditions(unresolvedHandleCount: Int)
    case applying(replacementCount: Int, scheduleFileCount: Int)
    case writingScheduleFile(String)
    case finished(didWrite: Bool)
}

public typealias SourceActorDIDConversionProgressHandler = (SourceActorDIDConversionProgress) -> Void

public struct SourceActorDIDConverter: Sendable {
    public init() {}

    public func convert(
        _ request: SourceActorDIDConversionRequest,
        progress: SourceActorDIDConversionProgressHandler? = nil
    ) async throws -> SourceActorDIDConversionResult {
        progress?(.readingRepository(request.repositoryURL))
        var repository = try OpenMusicEventSourceRepositoryFileTree()
            .read(from: request.repositoryURL)
            .output
            .requiredValue
        progress?(.repositoryRead(eventCount: repository.events.count))
        progress?(.validatingOverrides(count: request.overrides.count))
        let normalizedOverrides = try normalizedOverrides(request.overrides)
        progress?(.discoveringActors(eventDirectory: request.eventDirectory))
        let occurrences = actorOccurrences(in: repository, eventDirectory: request.eventDirectory)
        let handleReferences = occurrences.compactMap { occurrence -> String? in
            guard case let .handle(handle) = occurrence.actor.identifier else {
                return nil
            }
            return handle.rawValue
        }
        let handles = Set(handleReferences)
        progress?(
            .actorsDiscovered(
                actorReferenceCount: occurrences.count,
                handleReferenceCount: handleReferences.count,
                didReferenceCount: occurrences.count - handleReferences.count,
                uniqueHandleCount: handles.count,
                scheduleFileCount: Set(occurrences.map(\.location.file)).count
            )
        )

        let resolutions = try await resolutions(
            for: handles,
            overrides: normalizedOverrides,
            parallelism: request.resolutionParallelism,
            timeoutSeconds: request.resolutionTimeoutSeconds,
            progress: progress
        )
        progress?(.buildingResult)
        var result = conversionResult(
            occurrences: occurrences,
            resolutions: resolutions,
            didWrite: false
        )

        if request.apply {
            progress?(
                .checkingApplyPreconditions(
                    unresolvedHandleCount: result.unresolvedHandles.count
                )
            )
        }

        if request.apply,
           !request.allowUnresolved,
           !result.unresolvedHandles.isEmpty {
            throw SourceActorDIDConversionError.unresolvedHandles(result.unresolvedHandles)
        }

        if request.apply {
            progress?(
                .applying(
                    replacementCount: result.replacements.count,
                    scheduleFileCount: result.touchedFiles.count
                )
            )
            try apply(
                occurrences: occurrences,
                resolutions: resolutions,
                to: &repository,
                repositoryURL: request.repositoryURL,
                progress: progress
            )
            result.didWrite = !result.replacements.isEmpty
        }

        progress?(.finished(didWrite: result.didWrite))
        return result
    }

    private func normalizedOverrides(
        _ overrides: [String: String]
    ) throws -> [String: String] {
        var normalized: [String: String] = [:]

        for (handle, did) in overrides {
            guard let actor = OMERecord.Contributor.Actor(handle),
                  case let .handle(normalizedHandle) = actor.identifier
            else {
                throw SourceActorDIDConversionError.invalidOverrideHandle(handle)
            }
            guard DID(did) != nil else {
                throw SourceActorDIDConversionError.invalidOverrideDID(
                    handle: normalizedHandle.rawValue,
                    did: did
                )
            }
            normalized[normalizedHandle.rawValue] = did
        }

        return normalized
    }

    private func resolutions(
        for handles: Set<String>,
        overrides: [String: String],
        parallelism: Int,
        timeoutSeconds: Int,
        progress: SourceActorDIDConversionProgressHandler?
    ) async throws -> [String: Resolution] {
        @Dependency(Atmosphere.Account.Client.self) var accountClient
        let resolveHandle = accountClient.resolveHandle

        var resolutions: [String: Resolution] = [:]
        let sortedHandles = handles.sorted()
        progress?(
            .resolvingHandles(
                uniqueHandleCount: sortedHandles.count,
                overrideCount: sortedHandles.filter { overrides[$0] != nil }.count,
                parallelism: parallelism,
                timeoutSeconds: timeoutSeconds
            )
        )

        for batchStart in stride(from: 0, to: sortedHandles.count, by: parallelism) {
            let batchEnd = min(batchStart + parallelism, sortedHandles.count)
            let batch = sortedHandles[batchStart..<batchEnd]

            await withTaskGroup(of: HandleResolutionResult.self) { group in
                for (offset, handle) in batch.enumerated() {
                    let index = batchStart + offset + 1

                    if let did = overrides[handle] {
                        resolutions[handle] = .resolved(
                            did: did,
                            source: .override
                        )
                        progress?(
                            .handleResolved(
                                handle: handle,
                                index: index,
                                total: sortedHandles.count,
                                source: .override
                            )
                        )
                        continue
                    }

                    progress?(
                        .resolvingHandle(
                            handle: handle,
                            index: index,
                            total: sortedHandles.count
                        )
                    )
                    group.addTask {
                        HandleResolutionResult(
                            handle: handle,
                            index: index,
                            resolution: await self.resolveHandle(
                                handle,
                                resolveHandle: resolveHandle,
                                timeoutSeconds: timeoutSeconds
                            )
                        )
                    }
                }

                while let result = await group.next() {
                    resolutions[result.handle] = result.resolution
                    switch result.resolution {
                    case let .resolved(_, source):
                        progress?(
                            .handleResolved(
                                handle: result.handle,
                                index: result.index,
                                total: sortedHandles.count,
                                source: source
                            )
                        )

                    case let .unresolved(errorDescription):
                        progress?(
                            .handleResolutionFailed(
                                handle: result.handle,
                                index: result.index,
                                total: sortedHandles.count,
                                errorDescription: errorDescription
                            )
                        )
                    }
                }
            }
        }

        return resolutions
    }

    private func resolveHandle(
        _ handle: String,
        resolveHandle: @escaping @Sendable (Atmosphere.Account.Handle) async throws -> (Atmosphere.Account, DID.Document),
        timeoutSeconds: Int
    ) async -> Resolution {
        await withTaskGroup(of: Resolution.self, returning: Resolution.self) { group in
            group.addTask {
                do {
                    let (account, _) = try await resolveHandle(
                        Atmosphere.Account.Handle(handle)
                    )
                    return .resolved(
                        did: account.id.rawValue.description,
                        source: .resolved
                    )
                } catch {
                    return .unresolved(String(describing: error))
                }
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(Int64(timeoutSeconds)))
                return .unresolved("Timed out after \(timeoutSeconds) second(s).")
            }

            guard let result = await group.next() else {
                return .unresolved("No resolution result.")
            }
            group.cancelAll()
            return result
        }
    }

    private func actorOccurrences(
        in repository: OpenMusicEventSourceRepository,
        eventDirectory: String?
    ) -> [SourceScheduleActorOccurrence] {
        var occurrences: [SourceScheduleActorOccurrence] = []

        for eventIndex in repository.events.indices {
            let event = repository.events[eventIndex]
            if let eventDirectory, event.directoryName != eventDirectory {
                continue
            }
            guard let schedules = event.components.schedules else {
                continue
            }

            for scheduleIndex in schedules.indices {
                let schedule = schedules[scheduleIndex]
                for stageID in schedule.data.performances.keys.sorted() {
                    guard let performances = schedule.data.performances[stageID] else {
                        continue
                    }
                    for performanceIndex in performances.indices {
                        let performance = performances[performanceIndex]
                        guard let contributors = performance.contributors else {
                            continue
                        }

                        for contributorIndex in contributors.indices {
                            guard case let .actor(actor) = contributors[contributorIndex].subject else {
                                continue
                            }
                            let location = SourceActorDIDConversionLocation(
                                file: "events/\(event.directoryName)/schedules/\(schedule.path.rawValue)",
                                eventDirectory: event.directoryName,
                                scheduleFileName: schedule.path.rawValue,
                                stageID: stageID,
                                performanceIndex: performanceIndex,
                                performanceTitle: performance.title,
                                actorIndex: contributorIndex
                            )
                            occurrences.append(
                                SourceScheduleActorOccurrence(
                                    eventIndex: eventIndex,
                                    scheduleIndex: scheduleIndex,
                                    stageID: stageID,
                                    performanceIndex: performanceIndex,
                                    actorIndex: contributorIndex,
                                    location: location,
                                    actor: actor
                                )
                            )
                        }
                    }
                }
            }
        }

        return occurrences
    }

    private func conversionResult(
        occurrences: [SourceScheduleActorOccurrence],
        resolutions: [String: Resolution],
        didWrite: Bool
    ) -> SourceActorDIDConversionResult {
        var replacements: [SourceActorDIDConversionResult.Replacement] = []
        var unresolvedHandles: [SourceActorDIDConversionResult.UnresolvedHandle] = []
        var unchangedDIDReferences: [SourceActorDIDConversionResult.DIDReference] = []

        for occurrence in occurrences {
            switch occurrence.actor.identifier {
            case let .did(did):
                unchangedDIDReferences.append(
                    .init(
                        location: occurrence.location,
                        did: did.description
                    )
                )

            case let .handle(handle):
                switch resolutions[handle.rawValue] {
                case let .resolved(did, source):
                    replacements.append(
                        .init(
                            location: occurrence.location,
                            handle: handle.rawValue,
                            did: did,
                            source: source
                        )
                    )

                case let .unresolved(errorDescription):
                    unresolvedHandles.append(
                        .init(
                            location: occurrence.location,
                            handle: handle.rawValue,
                            errorDescription: errorDescription
                        )
                    )

                case nil:
                    break
                }
            }
        }

        return SourceActorDIDConversionResult(
            replacements: replacements,
            unresolvedHandles: unresolvedHandles,
            unchangedDIDReferences: unchangedDIDReferences,
            touchedFiles: Array(Set(replacements.map(\.location.file))).sorted(),
            didWrite: didWrite
        )
    }

    private func apply(
        occurrences: [SourceScheduleActorOccurrence],
        resolutions: [String: Resolution],
        to repository: inout OpenMusicEventSourceRepository,
        repositoryURL: URL,
        progress: SourceActorDIDConversionProgressHandler?
    ) throws {
        var changedSchedules = Set<ScheduleKey>()

        for occurrence in occurrences {
            guard case let .handle(handle) = occurrence.actor.identifier,
                  case let .resolved(did, _) = resolutions[handle.rawValue],
                  let replacementActor = OMERecord.Contributor.Actor(did)
            else { continue }

            replaceActor(
                in: &repository,
                at: occurrence,
                with: replacementActor
            )
            changedSchedules.insert(
                ScheduleKey(
                    eventIndex: occurrence.eventIndex,
                    scheduleIndex: occurrence.scheduleIndex
                )
            )
        }

        try writeChangedSchedules(
            changedSchedules,
            from: repository,
            to: repositoryURL,
            progress: progress
        )
    }

    private func replaceActor(
        in repository: inout OpenMusicEventSourceRepository,
        at occurrence: SourceScheduleActorOccurrence,
        with actor: OMERecord.Contributor.Actor
    ) {
        var event = repository.events[occurrence.eventIndex]
        guard var schedules = event.components.schedules,
              schedules.indices.contains(occurrence.scheduleIndex)
        else { return }

        var schedule = schedules[occurrence.scheduleIndex]
        var performancesByStage = schedule.data.performances
        guard var performances = performancesByStage[occurrence.stageID],
              performances.indices.contains(occurrence.performanceIndex)
        else { return }

        var performance = performances[occurrence.performanceIndex]
        guard var contributors = performance.contributors,
              contributors.indices.contains(occurrence.actorIndex)
        else { return }

        contributors[occurrence.actorIndex].subject = .actor(actor)
        performance.contributors = contributors
        performances[occurrence.performanceIndex] = performance
        performancesByStage[occurrence.stageID] = performances
        schedule.data.performances = performancesByStage
        schedules[occurrence.scheduleIndex] = schedule
        event.components.schedules = schedules
        repository.events[occurrence.eventIndex] = event
    }

    private func writeChangedSchedules(
        _ changedSchedules: Set<ScheduleKey>,
        from repository: OpenMusicEventSourceRepository,
        to repositoryURL: URL,
        progress: SourceActorDIDConversionProgressHandler?
    ) throws {
        let groupedByEvent = Dictionary(grouping: changedSchedules, by: \.eventIndex)

        for (eventIndex, scheduleKeys) in groupedByEvent.sorted(by: { $0.key < $1.key }) {
            let event = repository.events[eventIndex]
            guard let schedules = event.components.schedules else {
                continue
            }

            let changedScheduleFiles = scheduleKeys
                .sorted { $0.scheduleIndex < $1.scheduleIndex }
                .map { schedules[$0.scheduleIndex] }
            for schedule in changedScheduleFiles {
                progress?(
                    .writingScheduleFile(
                        "events/\(event.directoryName)/schedules/\(schedule.path.rawValue)"
                    )
                )
            }
            let schedulesURL = repositoryURL
                .appending(path: "events", directoryHint: .isDirectory)
                .appending(path: event.directoryName, directoryHint: .isDirectory)
                .appending(path: "schedules", directoryHint: .isDirectory)

            _ = try File.Many(withExtension: "yml")
                .map(FileContentConversion(YamlConversion<ScheduleDTO>()))
                .write(changedScheduleFiles, to: schedulesURL)
        }
    }
}

private enum Resolution: Equatable, Sendable {
    case resolved(
        did: String,
        source: SourceActorDIDConversionResult.Replacement.Source
    )
    case unresolved(String)
}

private struct HandleResolutionResult: Sendable {
    var handle: String
    var index: Int
    var resolution: Resolution
}

private struct SourceScheduleActorOccurrence: Sendable {
    var eventIndex: Int
    var scheduleIndex: Int
    var stageID: String
    var performanceIndex: Int
    var actorIndex: Int
    var location: SourceActorDIDConversionLocation
    var actor: OMERecord.Contributor.Actor
}

private struct ScheduleKey: Hashable, Sendable {
    var eventIndex: Int
    var scheduleIndex: Int
}
