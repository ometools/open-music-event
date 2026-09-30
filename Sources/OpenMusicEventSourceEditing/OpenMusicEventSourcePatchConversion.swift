import Dependencies
import FileTree
import Foundation
import GRDB
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData

extension OpenMusicEventSourceEventConversion {
    static var live: Self {
        Self { sourceEvent, eventID in
            @Dependency(\.defaultDatabase) var database

            let (sourceRecords, event) = try await database.read { db in
                let sourceRecords = try OpenMusicEventSourceRecords(
                    eventID: eventID,
                    in: db
                )
                guard let event = sourceRecords.event else {
                    throw SourceWorkspacePatchConversionError.eventNotFound(eventID)
                }
                return (sourceRecords, event)
            }

            var sourceEvent = sourceEvent
            let sourceInlineSchedule = sourceEvent.event.schedule
            sourceEvent.event = EventDTO(
                event.sourceDraft(preservingSourceID: sourceEvent.event.id)
            )
            .preservingSourceImageReferences(
                from: sourceEvent.event,
                context: SourceImageReferenceContext(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    parentKind: .event,
                    parentLocalID: eventID.eventID.rawValue.rawValue
                )
            )
            sourceEvent.stages = try sourceEvent.sourceStageFiles(
                from: sourceRecords.stages,
                eventID: eventID
            )
            sourceEvent.contributors = try sourceEvent.sourceContributorFiles(
                from: sourceRecords.contributors,
                eventID: eventID
            )
            sourceEvent.posters = try sourceEvent.sourcePosterFiles(
                from: sourceRecords.posters,
                eventID: eventID
            )
            sourceEvent.channels = try sourceEvent.sourceChannelFiles(
                from: sourceRecords.channels,
                eventID: eventID
            )
            sourceEvent.communicationPosts = try sourceEvent.sourceCommunicationPostDirectories(
                from: sourceRecords.commsPosts
            )
            let sourceSchedules = try sourceEvent.sourceScheduleRendering(
                from: sourceRecords.schedules,
                contributors: sourceRecords.contributors,
                scheduleItems: sourceRecords.scheduleItems,
                performanceDetails: sourceRecords.scheduleItemPerformanceDetails,
                scheduleItemContributors: sourceRecords.scheduleItemContributors,
                event: event,
                sourceInlineSchedule: sourceInlineSchedule
            )
            sourceEvent.event.schedule = sourceSchedules.inlineSchedule
            sourceEvent.schedules = sourceSchedules.scheduleFiles
            return sourceEvent
        }
    }
}

public extension SourceWorkspacePatchConversion {
    static var live: Self {
        Self { sourceRepository, request in
            @Dependency(\.defaultDatabase) var database
            let workspace = request.workspace
            let calendarID = OME.Calendar.ID(
                ownerID: workspace.organizerID,
                calendarID: OME.Calendar.defaultID
            )
            let eventConversion = OpenMusicEventSourceEventConversion.live

            let (calendar, sourceEvents, collaborators) = try await database.read { db in
                let calendar = try OME.Calendar
                    .where { $0.id.eq(calendarID) }
                    .fetchOne(db)
                let sourceEvents = try EventSourceProvenanceRecord
                    .where { $0.id.organizerID.eq(workspace.organizerID) }
                    .fetchAll(db)
                    .filter { $0.workspace?.id == workspace.id }
                    .sorted { lhs, rhs in
                        lhs.sourceEventDirectory < rhs.sourceEventDirectory
                    }
                let collaborators = try WorkspaceRelationshipRecord
                    .where { $0.id.workspaceID.eq(workspace.id) }
                    .fetchAll(db)
                    .sorted { $0.recordKey < $1.recordKey }
                return (calendar, sourceEvents, collaborators)
            }
            guard let calendar else {
                throw SourceWorkspacePatchConversionError.calendarNotFound(calendarID)
            }

            var sourceRepository = sourceRepository
            let sourceCalendar = sourceRepository.calendar
            let updatedCalendar = CalendarDTO(calendar)
                .preservingSourceImageReferences(
                    from: sourceCalendar ?? .defaultCalendar,
                    context: SourceImageReferenceContext(
                        organizerID: workspace.organizerID,
                        eventID: nil,
                        parentKind: .calendar,
                        parentLocalID: calendarID.calendarID.rawValue.rawValue
                    )
                )
            sourceRepository.calendar = if sourceCalendar == nil,
                                           updatedCalendar == .defaultCalendar {
                nil
            } else {
                updatedCalendar
            }
            let existingCollaborators = Dictionary(
                uniqueKeysWithValues: (sourceRepository.collaborators ?? []).map {
                    ($0.fileName, $0)
                }
            )
            let collaboratorFiles = try collaborators.map { collaborator in
                if let existing = existingCollaborators[collaborator.recordKey] {
                    return try existing.map { _ in collaborator.relationship }
                }
                return try FileContent(
                    fileName: collaborator.recordKey,
                    fileType: "yml",
                    data: collaborator.relationship
                )
            }
            sourceRepository.collaborators = collaboratorFiles.isEmpty ? nil : collaboratorFiles
            var eventsByDirectory = Dictionary(
                uniqueKeysWithValues: sourceRepository.events.map { ($0.directoryName, $0) }
            )
            for sourceEvent in sourceEvents {
                let existingSourceEvent = eventsByDirectory[sourceEvent.sourceEventDirectory]?.components
                    ?? .emptyForNewSourcePatch
                let updatedSourceEvent = try await eventConversion.update(
                    existingSourceEvent,
                    sourceEvent.id
                )
                eventsByDirectory[sourceEvent.sourceEventDirectory] = DirectoryContent(
                    directoryName: sourceEvent.sourceEventDirectory,
                    components: updatedSourceEvent
                )
            }
            let updatedSourceEvents = sourceRepository.events.map { event in
                eventsByDirectory[event.directoryName] ?? event
            }
            let existingSourceEventDirectories = Set(sourceRepository.events.map(\.directoryName))
            let addedSourceEvents = sourceEvents
                .filter { !existingSourceEventDirectories.contains($0.sourceEventDirectory) }
                .compactMap { eventsByDirectory[$0.sourceEventDirectory] }
            sourceRepository.events = updatedSourceEvents + addedSourceEvents
            return sourceRepository
        }
    }
}

public enum SourceWorkspacePatchConversionError: Equatable, Error, Sendable {
    case eventNotFound(OME.Event.ID)
    case calendarNotFound(OME.Calendar.ID)
}

private struct OpenMusicEventSourceRecords {
    var event: OME.Event?
    var stages: [OME.Stage] = []
    var contributors: [OME.Contributor] = []
    var posters: [OME.Poster] = []
    var schedules: [OME.Schedule] = []
    var scheduleItems: [OME.ScheduleItem] = []
    var scheduleItemPerformanceDetails: [OME.ScheduleItem.PerformanceDetails] = []
    var channels: [OME.Channel] = []
    var commsPosts: [CommsPost] = []
    var scheduleItemContributors: [OME.ScheduleItem.Contributor] = []

    init() {}

    init(
        eventID: OME.Event.ID,
        in db: Database
    ) throws {
        var records = Self()

        for projection in OME.sourceEventProjections {
            switch projection.fileFamily {
            case .event:
                records.event = try OME.Event
                    .where { $0.id.eq(eventID) }
                    .fetchOne(db)

            case .stage:
                records.stages = try OME.Stage
                    .where { $0.id.organizerID.eq(eventID.organizerID) }
                    .where { $0.id.eventID.eq(eventID.eventID) }
                    .fetchAll(db)

            case .contributor:
                records.contributors = try OME.Contributor
                    .where { $0.id.organizerID.eq(eventID.organizerID) }
                    .where { $0.id.eventID.eq(eventID.eventID) }
                    .fetchAll(db)

            case .schedule:
                switch projection.recordType.descriptor.id {
                case OME.Schedule.tableName:
                    records.schedules = try OME.Schedule
                        .where { $0.id.organizerID.eq(eventID.organizerID) }
                        .where { $0.id.eventID.eq(eventID.eventID) }
                        .fetchAll(db)

                case OME.ScheduleItem.tableName:
                    records.scheduleItems = try OME.ScheduleItem
                        .where { $0.id.organizerID.eq(eventID.organizerID) }
                        .where { $0.id.eventID.eq(eventID.eventID) }
                        .fetchAll(db)

                case OME.ScheduleItem.PerformanceDetails.tableName:
                    records.scheduleItemPerformanceDetails = try OME.ScheduleItem.PerformanceDetails
                        .where { $0.id.organizerID.eq(eventID.organizerID) }
                        .where { $0.id.eventID.eq(eventID.eventID) }
                        .fetchAll(db)

                case OME.ScheduleItem.Contributor.tableName:
                    records.scheduleItemContributors = try OME.ScheduleItem.Contributor
                        .where { $0.id.organizerID.eq(eventID.organizerID) }
                        .where { $0.id.eventID.eq(eventID.eventID) }
                        .fetchAll(db)

                default:
                    preconditionFailure(
                        "Unhandled schedule source projection: \(projection.recordType.descriptor.id)"
                    )
                }

            case .channel:
                records.channels = try OME.Channel
                    .where { $0.id.organizerID.eq(eventID.organizerID) }
                    .where { $0.id.eventID.eq(eventID.eventID) }
                    .fetchAll(db)

            case .communicationPost:
                records.commsPosts = try CommsPost
                    .where { $0.id.organizerID.eq(eventID.organizerID) }
                    .where { $0.id.eventID.eq(eventID.eventID) }
                    .fetchAll(db)

            case .poster:
                records.posters = try OME.Poster
                    .where { $0.id.organizerID.eq(eventID.organizerID) }
                    .where { $0.id.eventID.eq(eventID.eventID) }
                    .fetchAll(db)

            case .calendar, .collaborator:
                break
            }
        }

        self = records
    }
}

private struct SourceScheduleRendering {
    var inlineSchedule: InlineScheduleDTO?
    var scheduleFiles: [FileContent<ScheduleDTO>]?
}

private extension OpenMusicEventSourceEvent {
    func sourceScheduleRendering(
        from schedules: [OME.Schedule],
        contributors: [OME.Contributor],
        scheduleItems: [OME.ScheduleItem],
        performanceDetails: [OME.ScheduleItem.PerformanceDetails],
        scheduleItemContributors: [OME.ScheduleItem.Contributor],
        event: OME.Event,
        sourceInlineSchedule: InlineScheduleDTO?
    ) throws -> SourceScheduleRendering {
        let schedulesByID = Dictionary(
            uniqueKeysWithValues: schedules.map { ($0.id.scheduleID, $0) }
        )
        let scheduleItemsByScheduleID = Dictionary(
            grouping: scheduleItems.compactMap { scheduleItem in
                scheduleItem.scheduleID.map { ($0, scheduleItem) }
            },
            by: \.0
        )
        .mapValues { pairs in
            pairs.map(\.1)
        }
        let performanceDetailsByScheduleItemID = Dictionary(
            uniqueKeysWithValues: performanceDetails.map { ($0.id.scheduleItemID, $0) }
        )
        let contributorsByScheduleItemID = Dictionary(
            grouping: scheduleItemContributors,
            by: \.id.scheduleItemID
        )
        let contributorIDsWithDID = Set(
            contributors.compactMap { contributor in
                contributor.did == nil ? nil : contributor.id.contributorID
            }
        )
        var consumedScheduleIDs: Set<OME.ID<OME.Schedule>> = []
        var files: [FileContent<ScheduleDTO>] = []

        if schedules.count == 1,
           let schedule = schedules.first,
           schedule.id.scheduleID == OME.Schedule.singletonID,
           sourceInlineSchedule != nil || (self.schedules ?? []).isEmpty {
            let scheduleID = schedule.id.scheduleID
            return SourceScheduleRendering(
                inlineSchedule: schedule.inlineSourceDTO(
                    scheduleItems: sourceScheduleItems(
                        scheduleID: scheduleID,
                        scheduleItems: scheduleItemsByScheduleID[scheduleID] ?? [],
                        sourceStageOrder: sourceInlineSchedule.map {
                            Array($0.scheduleItems.keys)
                        } ?? [],
                        performanceDetails: performanceDetailsByScheduleItemID,
                        contributorIDsWithDID: contributorIDsWithDID,
                        scheduleItemContributors: contributorsByScheduleItemID,
                        sourceScheduleItemsByID: sourceInlineSchedule?.sourceScheduleItemsByID(
                            scheduleID: scheduleID
                        ) ?? [:],
                        eventTimeZone: event.timeZone
                    ),
                    eventStartDate: event.startDate,
                    eventTimeZone: event.timeZone
                ),
                scheduleFiles: nil
            )
        }

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
                        scheduleItems: sourceScheduleItems(
                            scheduleID: scheduleID,
                            scheduleItems: scheduleItemsByScheduleID[scheduleID] ?? [],
                            sourceStageOrder: Array(sourceSchedule.scheduleItems.keys),
                            performanceDetails: performanceDetailsByScheduleItemID,
                            contributorIDsWithDID: contributorIDsWithDID,
                            scheduleItemContributors: contributorsByScheduleItemID,
                            sourceScheduleItemsByID: sourceSchedule.sourceScheduleItemsByID(
                                scheduleID: scheduleID
                            ),
                            eventTimeZone: event.timeZone
                        ),
                        eventTimeZone: event.timeZone
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
                        scheduleItems: sourceScheduleItems(
                            scheduleID: scheduleID,
                            scheduleItems: scheduleItemsByScheduleID[scheduleID] ?? [],
                            sourceStageOrder: [],
                            performanceDetails: performanceDetailsByScheduleItemID,
                            contributorIDsWithDID: contributorIDsWithDID,
                            scheduleItemContributors: contributorsByScheduleItemID,
                            sourceScheduleItemsByID: sourceInlineSchedule?.sourceScheduleItemsByID(
                                scheduleID: scheduleID
                            ) ?? [:],
                            eventTimeZone: event.timeZone
                        ),
                        eventTimeZone: event.timeZone
                    )
                )
            )
        }

        return SourceScheduleRendering(
            inlineSchedule: nil,
            scheduleFiles: files.isEmpty ? nil : files
        )
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

        var inferredStageNamesByID: [OME.ID<OME.Stage>: String] = [:]
        if self.stages == nil {
            let inlineScheduleItems = event.schedule.map { [$0.scheduleItems] } ?? []
            let scheduleFileItems = schedules?.map(\.data.scheduleItems) ?? []
            let stageFileNames = Set(
                (inlineScheduleItems + scheduleFileItems).flatMap(\.keys)
            )
            let inferredFileNames = stageFileNames.isEmpty
                ? [OME.Stage.singletonID.rawValue.rawValue]
                : stageFileNames.sorted()
            for fileName in inferredFileNames {
                let words = fileName
                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .map { word in
                        word.prefix(1).uppercased() + String(word.dropFirst())
                    }
                inferredStageNamesByID[OME.ID<OME.Stage>(.init(fileName))] = words.isEmpty
                    ? OME.Stage.singletonName
                    : words.joined(separator: " ")
            }
        }

        let additions = stages
            .filter { !consumedStageIDs.contains($0.id.stageID) }
            .filter { stage in
                guard let inferredName = inferredStageNamesByID[stage.id.stageID] else {
                    return true
                }
                return stage.name != inferredName
                    || stage.color != OME.Stage.singletonColor
                    || stage.category != nil
                    || stage.sortIndex != nil
                    || stage.images != nil
                    || stage.systemIconName != nil
                    || stage.iconShortCode != nil
                    || stage.lineup != nil
            }
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

    func sourceChannelFiles(
        from channels: [OME.Channel],
        eventID: OME.Event.ID
    ) throws -> [FileContent<ChannelDTO>]? {
        let channelsByID = Dictionary(
            uniqueKeysWithValues: channels.map { ($0.id.channelID, $0) }
        )
        var consumedChannelIDs: Set<OME.ID<OME.Channel>> = []
        var files: [FileContent<ChannelDTO>] = []

        for file in self.channels ?? [] {
            let channelID = file.sourceChannelID
            guard let channel = channelsByID[channelID] else {
                continue
            }

            consumedChannelIDs.insert(channelID)
            files.append(
                try file.map { sourceChannel in
                    channel.sourceDraft(
                        preservingSourceID: sourceChannel.id
                    )
                }
            )
        }

        let additions = channels
            .filter { !consumedChannelIDs.contains($0.id.channelID) }
            .sorted { lhs, rhs in
                lhs.id.channelID.rawValue.rawValue < rhs.id.channelID.rawValue.rawValue
            }

        for channel in additions {
            files.append(
                try FileContent(
                    fileName: channel.id.channelID.rawValue.rawValue,
                    fileType: "yml",
                    data: channel.sourceDraft(preservingSourceID: nil)
                )
            )
        }

        return files.isEmpty ? nil : files
    }

    func sourceCommunicationPostDirectories(
        from posts: [CommsPost]
    ) throws -> [DirectoryContent<[FileContent<CommunicationPostDTO>]>]? {
        let sourceDirectoriesByChannelID = Dictionary(
            uniqueKeysWithValues: (communicationPosts ?? []).map {
                ($0.directoryName, $0)
            }
        )
        let postsByChannelID = Dictionary(grouping: posts, by: \.id.channelID)
        let directories = try postsByChannelID
            .keys
            .sorted { $0.rawValue.rawValue < $1.rawValue.rawValue }
            .map { channelID in
                let directoryName = channelID.rawValue.rawValue
                let sourceFilesByPostID = Dictionary(
                    uniqueKeysWithValues: (
                        sourceDirectoriesByChannelID[directoryName]?.components ?? []
                    ).map { ($0.fileName, $0) }
                )
                let files = try (postsByChannelID[channelID] ?? [])
                    .sorted { lhs, rhs in
                        if lhs.sortIndex != rhs.sortIndex {
                            return lhs.sortIndex < rhs.sortIndex
                        }
                        return lhs.id.postID.rawValue < rhs.id.postID.rawValue
                    }
                    .map { post in
                        let fileName = post.id.postID.rawValue
                        let dto = CommunicationPostDTO(post)
                        if let sourceFile = sourceFilesByPostID[fileName] {
                            return try sourceFile.map { sourcePost in
                                dto.preservingSourceImageReferences(
                                    from: sourcePost,
                                    context: SourceImageReferenceContext(
                                        organizerID: post.id.organizerID,
                                        eventID: post.id.eventID,
                                        parentKind: .communicationPost,
                                        parentLocalID: "\(post.id.channelID.rawValue.rawValue)|\(fileName)"
                                    )
                                )
                            }
                        }
                        return try FileContent(
                            fileName: fileName,
                            fileType: "md",
                            data: dto
                        )
                    }
                return DirectoryContent(
                    directoryName: directoryName,
                    components: files
                )
            }

        return directories.isEmpty ? nil : directories
    }
}

private extension CommunicationPostDTO {
    init(_ post: CommsPost) {
        self.init(
            title: post.title,
            contents: post.contents,
            headerImageURL: post.headerImageURL,
            images: post.images?.sourceImageAssets(),
            timestamp: post.timestamp,
            isPinned: post.isPinned,
            delivery: post.delivery
        )
    }
}

private enum SourceImageParentKind: String, Sendable {
    case calendar
    case event
    case stage
    case contributor
    case poster
    case communicationPost
}

private struct SourceImageReferenceContext: Sendable {
    var organizerID: OME.Organizer.ID
    var eventID: OME.ID<OME.Event>?
    var parentKind: SourceImageParentKind
    var parentLocalID: String

    func assetKey(
        for sourceImage: SourceImageAsset,
        variant: SourceImageAsset.VariantPayload
    ) -> String {
        // Mirrors source insertion's inferred key for source file image assets.
        if let assetKey = variant.payload.assetKey {
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
            variant.appearance?.rawValue ?? "default",
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

private extension CommunicationPostDTO {
    func preservingSourceImageReferences(
        from source: CommunicationPostDTO,
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
        let images = bundlingAppearancePairs()
        guard var source = source?.bundlingAppearancePairs() else { return images }
        return images.map { image in
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
        let images = filter { !$0.hasLocalFileURL }
        return images.isEmpty ? nil : images
    }
}

private extension SourceImageAsset {
    func preservingSourceImageReference(
        from sourceImage: SourceImageAsset
    ) -> Self {
        mapPayloads { payload, appearance in
            guard let sourcePayload = sourceImage.payload(for: appearance) else {
                return payload
            }
            var payload = payload
            payload.assetKey = sourcePayload.assetKey
            payload.source = sourcePayload.source
            return payload
        }
    }

    func canPreserveSourceImageReference(
        from sourceImage: SourceImageAsset,
        context: SourceImageReferenceContext
    ) -> Bool {
        guard role == sourceImage.role,
              renderKind == sourceImage.renderKind,
              materializationPolicy == sourceImage.materializationPolicy,
              payloads.map(\.appearance) == sourceImage.payloads.map(\.appearance)
        else { return false }

        for variant in payloads {
            guard let sourcePayload = sourceImage.payload(for: variant.appearance) else {
                return false
            }

            let sourceVariant = SourceImageAsset.VariantPayload(
                appearance: variant.appearance,
                payload: sourcePayload
            )
            if let assetKey = variant.payload.assetKey,
               assetKey == context.assetKey(for: sourceImage, variant: sourceVariant) {
                continue
            }

            guard variant.payload.source.isEquivalentSourceImageReference(to: sourcePayload.source) else {
                return false
            }
        }

        return true
    }

    var hasLocalFileURL: Bool {
        payloads.contains {
            $0.payload.source.isLocalFileURL
        }
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

private func sourceScheduleItems(
    scheduleID: OME.ID<OME.Schedule>,
    scheduleItems: [OME.ScheduleItem],
    sourceStageOrder: [String],
    performanceDetails: [OME.ID<OME.ScheduleItem>: OME.ScheduleItem.PerformanceDetails],
    contributorIDsWithDID: Set<OME.ID<OME.Contributor>>,
    scheduleItemContributors: [OME.ID<OME.ScheduleItem>: [OME.ScheduleItem.Contributor]],
    sourceScheduleItemsByID: [OME.ID<OME.ScheduleItem>: SourceScheduleItem],
    eventTimeZone: TimeZone
) -> ScheduleDTO.ScheduleItems {
    let scheduleItemsByStageID = Dictionary(
        grouping: scheduleItems,
        by: \.stageID
    )
    let stageIDsBySourceID = Dictionary(
        uniqueKeysWithValues: scheduleItemsByStageID.keys.map {
            ($0.rawValue.rawValue, $0)
        }
    )
    let preservedStageIDs = sourceStageOrder.compactMap { stageIDsBySourceID[$0] }
    let preservedStageIDSet = Set(preservedStageIDs)
    let addedStageIDs = scheduleItemsByStageID.keys
        .filter { !preservedStageIDSet.contains($0) }
        .sorted { $0.rawValue.rawValue < $1.rawValue.rawValue }

    return ScheduleDTO.ScheduleItems(
        uniqueKeysWithValues: (preservedStageIDs + addedStageIDs).map { stageID in
            let scheduleItems = scheduleItemsByStageID[stageID] ?? []
            let sortedScheduleItems = scheduleItems.sorted { lhs, rhs in
                if lhs.startTime != rhs.startTime { return lhs.startTime < rhs.startTime }
                if lhs.endTime != rhs.endTime { return lhs.endTime < rhs.endTime }
                return lhs.id.scheduleItemID.rawValue.rawValue < rhs.id.scheduleItemID.rawValue.rawValue
            }
            return (
                stageID.rawValue.rawValue,
                sortedScheduleItems.enumerated().map { offset, scheduleItem in
                    let inferredID = OME.ID<OME.ScheduleItem>(
                        .init("\(scheduleID.rawValue.rawValue)-\(stageID.rawValue.rawValue)-\(offset + 1)")
                    )
                    let nextScheduleItem = sortedScheduleItems.indices.contains(offset + 1)
                        ? sortedScheduleItems[offset + 1]
                        : nil
                    return scheduleItem.sourceDTO(
                        inferredID: inferredID,
                        preservingSource: sourceScheduleItemsByID[scheduleItem.id.scheduleItemID],
                        nextScheduleItem: nextScheduleItem,
                        performanceDetails: performanceDetails[scheduleItem.id.scheduleItemID],
                        contributors: scheduleItemContributors[scheduleItem.id.scheduleItemID] ?? [],
                        contributorIDsWithDID: contributorIDsWithDID,
                        eventTimeZone: eventTimeZone
                    )
                }
            )
        }
    )
}

private struct SourceScheduleItem {
    var id: ScheduleDTO.ScheduleItem.ID?
    var hasExplicitEndTime: Bool
    var contributors: [ScheduleDTO.ScheduleItem.Contributor]?
}

private extension ScheduleDTO {
    func sourceScheduleItemsByID(
        scheduleID: OME.ID<OME.Schedule>
    ) -> [OME.ID<OME.ScheduleItem>: SourceScheduleItem] {
        sourceScheduleItemLookup(
            scheduleID: scheduleID,
            scheduleItems: scheduleItems
        )
    }
}

private extension InlineScheduleDTO {
    func sourceScheduleItemsByID(
        scheduleID: OME.ID<OME.Schedule>
    ) -> [OME.ID<OME.ScheduleItem>: SourceScheduleItem] {
        sourceScheduleItemLookup(
            scheduleID: scheduleID,
            scheduleItems: scheduleItems
        )
    }
}

private func sourceScheduleItemLookup(
    scheduleID: OME.ID<OME.Schedule>,
    scheduleItems: ScheduleDTO.ScheduleItems
) -> [OME.ID<OME.ScheduleItem>: SourceScheduleItem] {
    Dictionary(
        uniqueKeysWithValues: scheduleItems.flatMap { stageID, scheduleItems in
            scheduleItems.enumerated().map { offset, scheduleItem in
                let scheduleItemID = scheduleItem.id
                    .map { OME.ID<OME.ScheduleItem>($0.rawValue) }
                    ?? OME.ID<OME.ScheduleItem>(
                        .init("\(scheduleID.rawValue.rawValue)-\(stageID)-\(offset + 1)")
                    )
                return (
                    scheduleItemID,
                    SourceScheduleItem(
                        id: scheduleItem.id,
                        hasExplicitEndTime: scheduleItem.endTime != nil,
                        contributors: scheduleItem.contributors
                    )
                )
            }
        }
    )
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

private extension FileContent where Component == ChannelDTO {
    var sourceChannelID: OME.ID<OME.Channel> {
        data.id?.channelID ?? OME.ID<OME.Channel>(.init(fileName))
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
            reportingLinks: reportingLinks
        )
    }
}

private extension OME.Schedule {
    func sourceDTO(
        preservingSourceID id: OME.ID<OME.Schedule>?,
        preservingSourceEventID eventID: OME.ID<OME.Event>?,
        scheduleItems: ScheduleDTO.ScheduleItems,
        eventTimeZone: TimeZone
    ) -> ScheduleDTO {
        ScheduleDTO(
            id: id,
            eventID: eventID,
            date: date,
            startsAt: startsAt?.sourceLocalTime(in: eventTimeZone),
            endsAt: endsAt?.sourceLocalTime(in: eventTimeZone),
            customTitle: customTitle,
            scheduleItems: scheduleItems
        )
    }

    func inlineSourceDTO(
        scheduleItems: ScheduleDTO.ScheduleItems,
        eventStartDate: LocalDate?,
        eventTimeZone: TimeZone
    ) -> InlineScheduleDTO {
        InlineScheduleDTO(
            date: date == eventStartDate ? nil : date,
            startsAt: startsAt?.sourceLocalTime(in: eventTimeZone),
            endsAt: endsAt?.sourceLocalTime(in: eventTimeZone),
            customTitle: customTitle,
            scheduleItems: scheduleItems
        )
    }
}

private extension OME.ScheduleItem {
    func sourceDTO(
        inferredID: OME.ID<OME.ScheduleItem>,
        preservingSource source: SourceScheduleItem?,
        nextScheduleItem: OME.ScheduleItem?,
        performanceDetails: OME.ScheduleItem.PerformanceDetails?,
        contributors: [OME.ScheduleItem.Contributor],
        contributorIDsWithDID: Set<OME.ID<OME.Contributor>>,
        eventTimeZone: TimeZone
    ) -> ScheduleDTO.ScheduleItem {
        let contributorCredits = contributors
            .sorted { lhs, rhs in
                if lhs.id.sortIndex != rhs.id.sortIndex { return lhs.id.sortIndex < rhs.id.sortIndex }
                return lhs.sourceOrderKey < rhs.sourceOrderKey
            }
            .compactMap {
                $0.sourceContributorCredit(contributorIDsWithDID: contributorIDsWithDID)
            }
        return ScheduleDTO.ScheduleItem(
            kind: kind,
            id: source?.id ?? (
                id.scheduleItemID == inferredID
                    ? nil
                    : ScheduleDTO.ScheduleItem.ID(id.scheduleItemID.rawValue)
            ),
            title: title,
            description: description,
            startTime: startTime.sourceLocalTime(in: eventTimeZone),
            endTime: sourceEndTime(
                preservingSource: source,
                nextScheduleItem: nextScheduleItem,
                eventTimeZone: eventTimeZone
            ),
            contributors: contributorCredits.sourceOrdered(
                preserving: source?.contributors,
                by: \.sourceOrderKey
            ),
            recordings: sourceRecordings(performanceDetails: performanceDetails)
        )
    }

    func sourceRecordings(
        performanceDetails: OME.ScheduleItem.PerformanceDetails?
    ) -> [ExternalPlatform.Asset]? {
        guard case .known(.performance) = kind,
              performanceDetails?.recordings.isEmpty == false
        else { return nil }
        return performanceDetails?.recordings
    }

    func sourceEndTime(
        preservingSource source: SourceScheduleItem?,
        nextScheduleItem: OME.ScheduleItem?,
        eventTimeZone: TimeZone
    ) -> String? {
        if source?.hasExplicitEndTime == false,
           nextScheduleItem?.startTime == endTime {
            return nil
        }
        return endTime.sourceLocalTime(in: eventTimeZone)
    }
}

private extension OME.ScheduleItem.Contributor {
    var sourceOrderKey: String {
        if let anonymousName {
            return "name:\(anonymousName)"
        }
        if let contributorActor {
            return "actor:\(contributorActor.description)"
        }
        if let contributorID {
            return "id:\(contributorID.rawValue.rawValue)"
        }
        return ""
    }

    func sourceContributorCredit(
        contributorIDsWithDID: Set<OME.ID<OME.Contributor>>
    ) -> ScheduleDTO.ScheduleItem.Contributor? {
        let subject: ScheduleDTO.ScheduleItem.Contributor.Subject

        if let anonymousName {
            subject = .name(anonymousName)
        } else if let contributorID,
                  contributorActor == nil || contributorIDsWithDID.contains(contributorID) {
            subject = .id(contributorID)
        } else if let contributorActor {
            subject = .actor(contributorActor)
        } else {
            return nil
        }

        return ScheduleDTO.ScheduleItem.Contributor(
            subject: subject,
            billing: billing,
            role: role
        )
    }
}

private extension ScheduleDTO.ScheduleItem.Contributor {
    var sourceOrderKey: String {
        switch subject {
        case let .id(id):
            return "id:\(id.rawValue.rawValue)"
        case let .name(name):
            return "name:\(name)"
        case let .actor(actor):
            return "actor:\(actor.description)"
        }
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
    func sourceDraft(
        preservingSourceID id: OME.Contributor.ID?
    ) -> OME.Contributor.Draft {
        OME.Contributor.Draft(
            id: id,
            name: name,
            did: did,
            bio: bio,
            images: images,
            links: links
        )
    }
}

private extension OME.Channel {
    func sourceDraft(
        preservingSourceID id: OME.Channel.ID?
    ) -> OME.Channel.Draft {
        OME.Channel.Draft(
            id: id,
            name: name,
            description: description,
            iconImageURL: iconImageURL,
            headerImageURL: headerImageURL,
            sortIndex: sortIndex,
            defaultNotificationState: defaultNotificationState,
            notificationsRequired: notificationsRequired
        )
    }
}
