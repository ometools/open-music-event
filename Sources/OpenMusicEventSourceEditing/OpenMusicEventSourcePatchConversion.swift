import Dependencies
import FileTree
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData

public extension OpenMusicEventSourcePatchConversion {
    static var live: Self {
        Self { sourceEvent, request in
            @Dependency(\.defaultDatabase) var database

            let (
                event,
                stages,
                contributors,
                posters,
                schedules,
                performances,
                performanceContributors
            ) = try await database.read { db in
                let event = try OME.Event
                    .where { $0.id.eq(request.eventID) }
                    .fetchOne(db)
                guard let event else {
                    throw OpenMusicEventSourcePatchConversionError.eventNotFound(request.eventID)
                }

                let stages = try OME.Stage
                    .where { $0.id.organizerID.eq(request.eventID.organizerID) }
                    .where { $0.id.eventID.eq(request.eventID.eventID) }
                    .fetchAll(db)

                let contributors = try OME.Contributor
                    .where { $0.id.organizerID.eq(request.eventID.organizerID) }
                    .where { $0.id.eventID.eq(request.eventID.eventID) }
                    .fetchAll(db)

                let posters = try OME.Poster
                    .where { $0.id.organizerID.eq(request.eventID.organizerID) }
                    .where { $0.id.eventID.eq(request.eventID.eventID) }
                    .fetchAll(db)

                let schedules = try OME.Schedule
                    .where { $0.id.organizerID.eq(request.eventID.organizerID) }
                    .where { $0.id.eventID.eq(request.eventID.eventID) }
                    .fetchAll(db)

                let performances = try OME.Performance
                    .where { $0.id.organizerID.eq(request.eventID.organizerID) }
                    .where { $0.id.eventID.eq(request.eventID.eventID) }
                    .fetchAll(db)

                let performanceContributors = try OME.Performance.Contributors
                    .where { $0.organizerID.eq(request.eventID.organizerID) }
                    .where { $0.eventID.eq(request.eventID.eventID) }
                    .fetchAll(db)

                return (
                    event,
                    stages,
                    contributors,
                    posters,
                    schedules,
                    performances,
                    performanceContributors
                )
            }

            var sourceEvent = sourceEvent
            sourceEvent.event = EventDTO(
                event.sourceDraft(preservingSourceID: sourceEvent.event.id)
            )
            .preservingSourceImageReferences(
                from: sourceEvent.event,
                context: SourceImageReferenceContext(
                    organizerID: request.eventID.organizerID,
                    eventID: request.eventID.eventID,
                    parentKind: .event,
                    parentLocalID: request.eventID.eventID.rawValue.rawValue
                )
            )
            sourceEvent.stages = try sourceEvent.sourceStageFiles(
                from: stages,
                eventID: request.eventID
            )
            sourceEvent.contributors = try sourceEvent.sourceContributorFiles(
                from: contributors,
                eventID: request.eventID
            )
            sourceEvent.posters = try sourceEvent.sourcePosterFiles(
                from: posters,
                eventID: request.eventID
            )
            sourceEvent.schedules = try sourceEvent.sourceScheduleFiles(
                from: schedules,
                performances: performances,
                performanceContributors: performanceContributors,
                eventTimeZone: event.timeZone
            )
            return sourceEvent
        }
    }
}

public extension OpenMusicEventCalendarSourcePatchConversion {
    static var live: Self {
        Self { sourceRepository, request in
            @Dependency(\.defaultDatabase) var database

            let calendar = try await database.read { db in
                try OME.Calendar
                    .where { $0.id.eq(request.calendarID) }
                    .fetchOne(db)
            }
            guard let calendar else {
                throw OpenMusicEventCalendarSourcePatchConversionError.calendarNotFound(request.calendarID)
            }

            var sourceRepository = sourceRepository
            let sourceCalendar = sourceRepository.calendar ?? .defaultCalendar
            sourceRepository.calendar = CalendarDTO(calendar)
                .preservingSourceImageReferences(
                    from: sourceCalendar,
                    context: SourceImageReferenceContext(
                        organizerID: request.calendarID.ownerID,
                        eventID: nil,
                        parentKind: .calendar,
                        parentLocalID: request.calendarID.calendarID.rawValue.rawValue
                    )
                )
            return sourceRepository
        }
    }
}

public enum OpenMusicEventSourcePatchConversionError: Equatable, Error, Sendable {
    case eventNotFound(OME.Event.ID)
}

public enum OpenMusicEventCalendarSourcePatchConversionError: Equatable, Error, Sendable {
    case calendarNotFound(OME.Calendar.ID)
}

private extension OpenMusicEventSourceEvent {
    func sourceScheduleFiles(
        from schedules: [OME.Schedule],
        performances: [OME.Performance],
        performanceContributors: [OME.Performance.Contributors],
        eventTimeZone: TimeZone
    ) throws -> [FileContent<ScheduleDTO>]? {
        let schedulesByID = Dictionary(
            uniqueKeysWithValues: schedules.map { ($0.id.scheduleID, $0) }
        )
        let performancesByScheduleID = Dictionary(
            grouping: performances.compactMap { performance in
                performance.scheduleID.map { ($0, performance) }
            },
            by: \.0
        )
        .mapValues { pairs in
            pairs.map(\.1)
        }
        let contributorsByPerformanceID = Dictionary(
            grouping: performanceContributors,
            by: \.performanceID
        )
        var consumedScheduleIDs: Set<OME.ID<OME.Schedule>> = []
        var files: [FileContent<ScheduleDTO>] = []

        for file in self.schedules ?? [] {
            let scheduleID = file.sourceScheduleID
            guard let schedule = schedulesByID[scheduleID] else {
                continue
            }

            consumedScheduleIDs.insert(scheduleID)
            files.append(
                try file.map { sourceSchedule in
                    schedule.sourceDTO(
                        preservingSourceID: sourceSchedule.id,
                        preservingSourceEventID: sourceSchedule.eventID,
                        performances: sourcePerformances(
                            scheduleID: scheduleID,
                            performances: performancesByScheduleID[scheduleID] ?? [],
                            performanceContributors: contributorsByPerformanceID,
                            sourceSchedule: sourceSchedule,
                            eventTimeZone: eventTimeZone
                        ),
                        eventTimeZone: eventTimeZone
                    )
                }
            )
        }

        let additions = schedules
            .filter { !consumedScheduleIDs.contains($0.id.scheduleID) }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date.description < rhs.date.description }
                if lhs.startsAt != rhs.startsAt {
                    return (lhs.startsAt ?? .distantFuture) < (rhs.startsAt ?? .distantFuture)
                }
                return lhs.id.scheduleID.rawValue.rawValue < rhs.id.scheduleID.rawValue.rawValue
            }

        for schedule in additions {
            let scheduleID = schedule.id.scheduleID
            files.append(
                try FileContent(
                    fileName: scheduleID.rawValue.rawValue,
                    fileType: "yml",
                    data: schedule.sourceDTO(
                        preservingSourceID: nil,
                        preservingSourceEventID: nil,
                        performances: sourcePerformances(
                            scheduleID: scheduleID,
                            performances: performancesByScheduleID[scheduleID] ?? [],
                            performanceContributors: contributorsByPerformanceID,
                            sourceSchedule: nil,
                            eventTimeZone: eventTimeZone
                        ),
                        eventTimeZone: eventTimeZone
                    )
                )
            )
        }

        return files.isEmpty ? nil : files
    }

    func sourceStageFiles(
        from stages: [OME.Stage],
        eventID: OME.Event.ID
    ) throws -> [FileContent<StageDTO>]? {
        let stagesByID = Dictionary(
            uniqueKeysWithValues: stages.map { ($0.id.stageID, $0) }
        )
        var consumedStageIDs: Set<OME.ID<OME.Stage>> = []
        var files: [FileContent<StageDTO>] = []

        for file in self.stages ?? [] {
            let stageID = file.sourceStageID
            guard let stage = stagesByID[stageID] else {
                continue
            }

            consumedStageIDs.insert(stageID)
            files.append(
                try file.map { sourceStage in
                    StageDTO(
                        stage.sourceDraft(
                            preservingSourceID: sourceStage.id
                        )
                    )
                    .preservingSourceImageReferences(
                        from: sourceStage,
                        context: SourceImageReferenceContext(
                            organizerID: eventID.organizerID,
                            eventID: eventID.eventID,
                            parentKind: .stage,
                            parentLocalID: stageID.rawValue.rawValue
                        )
                    )
                }
            )
        }

        let additions = stages
            .filter { !consumedStageIDs.contains($0.id.stageID) }
            .sorted { lhs, rhs in
                lhs.id.stageID.rawValue.rawValue < rhs.id.stageID.rawValue.rawValue
            }

        for stage in additions {
            files.append(
                try FileContent(
                    fileName: stage.id.stageID.rawValue.rawValue,
                    fileType: "yml",
                    data: StageDTO(
                        stage.sourceDraft(preservingSourceID: nil)
                    )
                )
            )
        }

        return files.isEmpty ? nil : files
    }

    func sourcePosterFiles(
        from posters: [OME.Poster],
        eventID: OME.Event.ID
    ) throws -> [FileContent<PosterDTO>]? {
        let postersByID = Dictionary(
            uniqueKeysWithValues: posters.map { ($0.id.posterID, $0) }
        )
        var consumedPosterIDs: Set<OME.ID<OME.Poster>> = []
        var files: [FileContent<PosterDTO>] = []

        for file in self.posters ?? [] {
            let posterID = file.sourcePosterID
            guard let poster = postersByID[posterID] else {
                continue
            }

            consumedPosterIDs.insert(posterID)
            files.append(
                try file.map { sourcePoster in
                    PosterDTO(
                        poster.sourceDraft(
                            preservingSourceID: sourcePoster.id
                        )
                    )
                    .preservingSourceImageReference(
                        from: sourcePoster,
                        context: SourceImageReferenceContext(
                            organizerID: eventID.organizerID,
                            eventID: eventID.eventID,
                            parentKind: .poster,
                            parentLocalID: posterID.rawValue.rawValue
                        )
                    )
                }
            )
        }

        let additions = posters
            .filter { !consumedPosterIDs.contains($0.id.posterID) }
            .sorted { lhs, rhs in
                lhs.id.posterID.rawValue.rawValue < rhs.id.posterID.rawValue.rawValue
            }

        for poster in additions {
            files.append(
                try FileContent(
                    fileName: poster.id.posterID.rawValue.rawValue,
                    fileType: "yml",
                    data: PosterDTO(
                        poster.sourceDraft(preservingSourceID: nil)
                    )
                )
            )
        }

        return files.isEmpty ? nil : files
    }

    func sourceContributorFiles(
        from contributors: [OME.Contributor],
        eventID: OME.Event.ID
    ) throws -> [FileContent<ContributorDTO>]? {
        let contributorsByID = Dictionary(
            uniqueKeysWithValues: contributors.map { ($0.id.contributorID, $0) }
        )
        var consumedContributorIDs: Set<OME.ID<OME.Contributor>> = []
        var files: [FileContent<ContributorDTO>] = []

        for file in self.contributors ?? [] {
            let contributorID = file.sourceContributorID
            guard let contributor = contributorsByID[contributorID] else {
                continue
            }

            consumedContributorIDs.insert(contributorID)
            files.append(
                try file.map { sourceContributor in
                    ContributorDTO(
                        contributor.sourceDraft(
                            preservingSourceID: sourceContributor.id
                        )
                    )
                    .preservingSourceImageReferences(
                        from: sourceContributor,
                        context: SourceImageReferenceContext(
                            organizerID: eventID.organizerID,
                            eventID: eventID.eventID,
                            parentKind: .contributor,
                            parentLocalID: contributorID.rawValue.rawValue
                        )
                    )
                }
            )
        }

        let additions = contributors
            .filter { !consumedContributorIDs.contains($0.id.contributorID) }
            .filter {
                !(event.usesScheduleContributorListing
                    && $0.isScheduleDerivedContributor
                    && !$0.hasSourceProfileContent)
            }
            .sorted { lhs, rhs in
                lhs.id.contributorID.rawValue.rawValue < rhs.id.contributorID.rawValue.rawValue
            }

        for contributor in additions {
            files.append(
                try FileContent(
                    fileName: contributor.id.contributorID.rawValue.rawValue,
                    fileType: "md",
                    data: ContributorDTO(
                        contributor.sourceDraft(preservingSourceID: nil)
                    )
                )
            )
        }

        return files.isEmpty ? nil : files
    }
}

private enum SourceImageParentKind: String, Sendable {
    case calendar
    case event
    case stage
    case contributor
    case poster
}

private struct SourceImageReferenceContext: Sendable {
    var organizerID: OME.Organizer.ID
    var eventID: OME.ID<OME.Event>?
    var parentKind: SourceImageParentKind
    var parentLocalID: String

    func assetKey(for sourceImage: SourceImageAsset) -> String {
        // Mirrors source insertion's inferred key for source file image assets.
        if let assetKey = sourceImage.assetKey {
            return assetKey
        }

        var components = [organizerID.description]
        if let eventID {
            components.append(eventID.rawValue.rawValue)
        }
        components.append(contentsOf: [
            parentKind.rawValue,
            parentLocalID,
            sourceImage.role.rawValue,
            sourceImage.appearance?.rawValue ?? "default",
        ])
        return components
            .joined(separator: "|")
    }
}

private extension EventDTO {
    func preservingSourceImageReferences(
        from source: EventDTO,
        context: SourceImageReferenceContext
    ) -> Self {
        var dto = self
        dto.images = images?.preservingSourceImageReferences(
            from: source.images,
            context: context
        )
        return dto
    }
}

private extension StageDTO {
    func preservingSourceImageReferences(
        from source: StageDTO,
        context: SourceImageReferenceContext
    ) -> Self {
        var dto = self
        dto.images = images?.preservingSourceImageReferences(
            from: source.images,
            context: context
        )
        return dto
    }
}

private extension ContributorDTO {
    func preservingSourceImageReferences(
        from source: ContributorDTO,
        context: SourceImageReferenceContext
    ) -> Self {
        var dto = self
        dto.images = images?.preservingSourceImageReferences(
            from: source.images,
            context: context
        )
        return dto
    }
}

private extension CalendarDTO {
    func preservingSourceImageReferences(
        from source: CalendarDTO,
        context: SourceImageReferenceContext
    ) -> Self {
        var dto = self
        dto.images = images?.preservingSourceImageReferences(
            from: source.images,
            context: context
        )
        return dto
    }

    func removingLocalFileURLImages() -> Self {
        var dto = self
        dto.images = dto.images?.removingLocalFileURLImages()
        return dto
    }
}

private extension PosterDTO {
    func preservingSourceImageReference(
        from source: PosterDTO,
        context: SourceImageReferenceContext
    ) -> Self {
        var dto = self
        if dto.image.canPreserveSourceImageReference(
            from: source.image,
            context: context
        ) {
            dto.image = dto.image.preservingSourceImageReference(
                from: source.image
            )
        }
        return dto
    }
}

private extension Array where Element == SourceImageAsset {
    func preservingSourceImageReferences(
        from source: [SourceImageAsset]?,
        context: SourceImageReferenceContext
    ) -> [SourceImageAsset] {
        guard var source else { return self }
        return map { image in
            guard let sourceIndex = source.firstIndex(where: {
                image.canPreserveSourceImageReference(
                    from: $0,
                    context: context
                )
            }) else {
                return image
            }

            let sourceImage = source.remove(at: sourceIndex)
            return image.preservingSourceImageReference(from: sourceImage)
        }
    }

    func removingLocalFileURLImages() -> [SourceImageAsset]? {
        let images = filter { !$0.source.isLocalFileURL }
        return images.isEmpty ? nil : images
    }
}

private extension SourceImageAsset {
    func preservingSourceImageReference(
        from sourceImage: SourceImageAsset
    ) -> Self {
        var image = self
        image.assetKey = sourceImage.assetKey
        image.source = sourceImage.source
        return image
    }

    func canPreserveSourceImageReference(
        from sourceImage: SourceImageAsset,
        context: SourceImageReferenceContext
    ) -> Bool {
        guard role == sourceImage.role,
              appearance == sourceImage.appearance
        else { return false }

        if let assetKey,
           assetKey == context.assetKey(for: sourceImage) {
            return true
        }

        return source.isEquivalentSourceImageReference(to: sourceImage.source)
    }
}

private extension SourceImageRef {
    var isLocalFileURL: Bool {
        switch self {
        case .file:
            return false

        case let .url(url):
            return url.isFileURL
        }
    }

    func isEquivalentSourceImageReference(to other: SourceImageRef) -> Bool {
        switch (self, other) {
        case let (.file(lhs), .file(rhs)):
            return lhs.normalizedSourcePath == rhs.normalizedSourcePath

        case let (.url(lhs), .url(rhs)):
            if lhs.isFileURL && rhs.isFileURL {
                return lhs.standardizedFileURL == rhs.standardizedFileURL
            }
            return lhs.absoluteString == rhs.absoluteString

        case let (.file(path), .url(url)),
             let (.url(url), .file(path)):
            return url.isFileURL
                && url.standardizedFileURL.path.hasSuffix(path.normalizedSourcePath)
        }
    }
}

private extension String {
    var normalizedSourcePath: String {
        var path = self
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }
        return path
    }
}

private func sourcePerformances(
    scheduleID: OME.ID<OME.Schedule>,
    performances: [OME.Performance],
    performanceContributors: [OME.ID<OME.Performance>: [OME.Performance.Contributors]],
    sourceSchedule: ScheduleDTO?,
    eventTimeZone: TimeZone
) -> [String: [ScheduleDTO.Performance]] {
    let sourcePerformances = sourceSchedule?.sourcePerformancesByID(
        scheduleID: scheduleID
    ) ?? [:]
    let performancesByStageID = Dictionary(
        grouping: performances,
        by: \.stageID
    )

    return Dictionary(
        uniqueKeysWithValues: performancesByStageID.keys.sorted {
            $0.rawValue.rawValue < $1.rawValue.rawValue
        }
        .map { stageID in
            let performances = performancesByStageID[stageID] ?? []
            let sortedPerformances = performances.sorted { lhs, rhs in
                if lhs.startTime != rhs.startTime { return lhs.startTime < rhs.startTime }
                if lhs.endTime != rhs.endTime { return lhs.endTime < rhs.endTime }
                return lhs.id.performanceID.rawValue.rawValue < rhs.id.performanceID.rawValue.rawValue
            }
            return (
                stageID.rawValue.rawValue,
                sortedPerformances.enumerated().map { offset, performance in
                    let inferredID = OME.ID<OME.Performance>(
                        .init("\(scheduleID.rawValue.rawValue)-\(stageID.rawValue.rawValue)-\(offset + 1)")
                    )
                    let sourcePerformance = sourcePerformances[performance.id.performanceID]
                    let nextPerformance = sortedPerformances.indices.contains(offset + 1)
                        ? sortedPerformances[offset + 1]
                        : nil
                    return performance.sourceDTO(
                        inferredID: inferredID,
                        preservingSource: sourcePerformance,
                        nextPerformance: nextPerformance,
                        contributors: performanceContributors[performance.id.performanceID] ?? [],
                        eventTimeZone: eventTimeZone
                    )
                }
            )
        }
    )
}

private struct SourcePerformance {
    var id: OME.ID<OME.Performance>?
    var hasExplicitEndTime: Bool
    var contributorIDs: [OME.ID<OME.Contributor>]?
    var contributorNames: [String]?
    var contributorActors: [OME.Contributor.Actor]?
}

private extension ScheduleDTO {
    func sourcePerformancesByID(
        scheduleID: OME.ID<OME.Schedule>
    ) -> [OME.ID<OME.Performance>: SourcePerformance] {
        Dictionary(
            uniqueKeysWithValues: performances.flatMap { stageID, performances in
                performances.enumerated().map { offset, performance in
                    let performanceID = performance.id
                        ?? OME.ID<OME.Performance>(
                            .init("\(scheduleID.rawValue.rawValue)-\(stageID)-\(offset + 1)")
                        )
                    return (
                        performanceID,
                        SourcePerformance(
                            id: performance.id,
                            hasExplicitEndTime: performance.endTime != nil,
                            contributorIDs: performance.contributorIDs,
                            contributorNames: performance.contributorNames,
                            contributorActors: performance.contributorActors
                        )
                    )
                }
            }
        )
    }
}

private extension FileContent where Component == ScheduleDTO {
    var sourceScheduleID: OME.ID<OME.Schedule> {
        data.id ?? OME.ID<OME.Schedule>(.init(fileName))
    }
}

private extension FileContent where Component == PosterDTO {
    var sourcePosterID: OME.ID<OME.Poster> {
        data.id?.posterID ?? OME.ID<OME.Poster>(.init(fileName))
    }
}

private extension FileContent where Component == StageDTO {
    var sourceStageID: OME.ID<OME.Stage> {
        data.id?.stageID ?? OME.ID<OME.Stage>(.init(fileName))
    }
}

private extension FileContent where Component == ContributorDTO {
    var sourceContributorID: OME.ID<OME.Contributor> {
        data.id?.contributorID ?? OME.ID<OME.Contributor>(.init(fileName))
    }
}

private extension OME.Event {
    func sourceDraft(
        preservingSourceID id: OME.Event.ID?
    ) -> OME.Event.Draft {
        OME.Event.Draft(
            id: id,
            name: name,
            description: description,
            startDate: startDate,
            endDate: endDate,
            status: status,
            mode: mode,
            locations: locations,
            uris: uris,
            timeZone: timeZone,
            images: images,
            contactNumbers: contactNumbers,
            categoryConfigs: categoryConfigs,
            policies: policies,
            reportingLink: reportingLink
        )
    }
}

private extension OME.Schedule {
    func sourceDTO(
        preservingSourceID id: OME.ID<OME.Schedule>?,
        preservingSourceEventID eventID: OME.ID<OME.Event>?,
        performances: [String: [ScheduleDTO.Performance]],
        eventTimeZone: TimeZone
    ) -> ScheduleDTO {
        ScheduleDTO(
            id: id,
            eventID: eventID,
            date: date,
            startsAt: startsAt?.sourceLocalTime(in: eventTimeZone),
            endsAt: endsAt?.sourceLocalTime(in: eventTimeZone),
            customTitle: customTitle,
            performances: performances
        )
    }
}

private extension OME.Performance {
    func sourceDTO(
        inferredID: OME.ID<OME.Performance>,
        preservingSource source: SourcePerformance?,
        nextPerformance: OME.Performance?,
        contributors: [OME.Performance.Contributors],
        eventTimeZone: TimeZone
    ) -> ScheduleDTO.Performance {
        let contributorIDs = contributors.compactMap { contributor in
            contributor.anonymousName == nil && contributor.contributorActor == nil
                ? contributor.contributorID
                : nil
        }
        let contributorNames = contributors.compactMap(\.anonymousName)
        let contributorActors = contributors.compactMap(\.contributorActor)
        return ScheduleDTO.Performance(
            id: source?.id ?? (id.performanceID == inferredID ? nil : id.performanceID),
            title: title,
            description: description,
            startTime: startTime.sourceLocalTime(in: eventTimeZone),
            endTime: sourceEndTime(
                preservingSource: source,
                nextPerformance: nextPerformance,
                eventTimeZone: eventTimeZone
            ),
            contributorIDs: contributorIDs.sourceOrdered(
                preserving: source?.contributorIDs,
                by: { $0.rawValue.rawValue }
            ),
            contributorNames: contributorNames.sourceOrdered(
                preserving: source?.contributorNames,
                by: { $0 }
            ),
            contributorActors: contributorActors.sourceOrdered(
                preserving: source?.contributorActors,
                by: { $0.description }
            ),
            recordings: recordings.isEmpty ? nil : recordings
        )
    }

    func sourceEndTime(
        preservingSource source: SourcePerformance?,
        nextPerformance: OME.Performance?,
        eventTimeZone: TimeZone
    ) -> String? {
        if source?.hasExplicitEndTime == false,
           nextPerformance?.startTime == endTime {
            return nil
        }
        return endTime.sourceLocalTime(in: eventTimeZone)
    }
}

private extension Array {
    func sourceOrdered<Key: Hashable & Comparable>(
        preserving source: [Element]?,
        by key: (Element) -> Key
    ) -> [Element]? {
        guard !isEmpty else { return nil }
        if let source,
           source.count == count,
           Set(source.map(key)) == Set(map(key)) {
            return source
        }
        return sorted { key($0) < key($1) }
    }
}

private extension Date {
    func sourceLocalTime(in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute, .second], from: self)
        if let second = components.second, second != 0 {
            return "\(Self.twoDigits(components.hour ?? 0)):\(Self.twoDigits(components.minute ?? 0)):\(Self.twoDigits(second))"
        }
        return "\(Self.twoDigits(components.hour ?? 0)):\(Self.twoDigits(components.minute ?? 0))"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

private extension EventDTO {
    var usesScheduleContributorListing: Bool {
        if case .known(.scheduleContributors)? = policies?.contributors?.listing {
            return true
        }
        return false
    }
}

private extension OME.Stage {
    func sourceDraft(
        preservingSourceID id: OME.Stage.ID?
    ) -> OME.Stage.Draft {
        OME.Stage.Draft(
            id: id,
            name: name,
            color: color,
            category: category,
            sortIndex: sortIndex,
            images: images,
            systemIconName: systemIconName,
            iconShortCode: iconShortCode,
            lineup: lineup
        )
    }
}

private extension OME.Poster {
    func sourceDraft(
        preservingSourceID id: OME.Poster.ID?
    ) -> OME.Poster.Draft {
        OME.Poster.Draft(
            id: id,
            title: title,
            image: image
        )
    }
}

private extension OME.Contributor {
    var hasSourceProfileContent: Bool {
        bio?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || images?.isEmpty == false
            || kind != nil
            || links?.isEmpty == false
    }

    var isScheduleDerivedContributor: Bool {
        id.contributorID.rawValue.rawValue.hasPrefix("schedule-name-")
            || id.contributorID.rawValue.rawValue.hasPrefix("schedule-actor-")
    }

    func sourceDraft(
        preservingSourceID id: OME.Contributor.ID?
    ) -> OME.Contributor.Draft {
        OME.Contributor.Draft(
            id: id,
            name: name,
            bio: bio,
            images: images,
            kind: kind,
            links: links
        )
    }
}
