import ATProto
import FileTree
import Foundation
import OpenMusicEventLexicon

public extension OME {
    struct SourceDatabaseInsertion: Equatable, Sendable {
        public struct Configuration: Equatable, Sendable {
            public var source: OpenMusicEventSourceRepository
            public var organizerID: OME.Organizer.ID
            public var sourceProvenance: SourceProvenance?
            public var sourceRootURL: URL?

            public init(
                source: OpenMusicEventSourceRepository,
                organizerID: OME.Organizer.ID,
                sourceRootURL: URL? = nil
            ) {
                self.init(
                    source: source,
                    organizerID: organizerID,
                    sourceProvenance: nil,
                    sourceRootURL: sourceRootURL
                )
            }

            public init(
                source: OpenMusicEventSourceRepository,
                organizerID: OME.Organizer.ID,
                sourceProvenance: SourceProvenance?,
                sourceRootURL: URL? = nil
            ) {
                self.source = source
                self.organizerID = organizerID
                self.sourceProvenance = sourceProvenance
                self.sourceRootURL = sourceRootURL
            }
        }

        public enum Error: Swift.Error, Equatable, Sendable {
            case conflictingInferredEventID(
                eventID: OME.Event.ID,
                existingSourceKind: SourceKind?,
                existingSourceReference: String?,
                incomingSourceKind: SourceKind,
                incomingSourceReference: String
            )
            case duplicateEventID(OME.Event.ID)
            case duplicateWorkspaceCollaborator(DID)
            case invalidWorkspaceRelationship(String)
            case invalidLocalTime(String)
            case missingPosterImage(String)
            case missingSourceRootForFileAsset(String)
            case missingScheduleItemEndTime(
                scheduleID: OME.Schedule.ID,
                stageID: OME.ID<OME.Stage>,
                scheduleItemIndex: Int
            )
            case missingScheduleContributorID(
                scheduleID: OME.Schedule.ID,
                stageID: OME.ID<OME.Stage>,
                scheduleItemIndex: Int,
                contributorID: OME.ID<OME.Contributor>
            )
            case missingInlineScheduleDate(OME.Event.ID)
            case duplicateScheduleID(OME.Schedule.ID)
        }

        public struct PendingFileImageAsset: Equatable, Sendable {
            public init(
                assetKey: String,
                sourceURL: URL,
                mimeType: String,
                data: Data
            ) {
                self.assetKey = assetKey
                self.sourceURL = sourceURL
                self.mimeType = mimeType
                self.data = data
            }

            public var assetKey: String
            public var sourceURL: URL
            public var mimeType: String
            public var data: Data
        }

        public struct CommunicationPost: Equatable, Sendable {
            public struct ID: Equatable, Hashable, Sendable {
                public init(
                    organizerID: OME.Organizer.ID,
                    eventID: OME.ID<OME.Event>,
                    channelID: OME.ID<OME.Channel>,
                    postID: OME.ID<CommunicationPost>
                ) {
                    self.organizerID = organizerID
                    self.eventID = eventID
                    self.channelID = channelID
                    self.postID = postID
                }

                public var organizerID: OME.Organizer.ID
                public var eventID: OME.ID<OME.Event>
                public var channelID: OME.ID<OME.Channel>
                public var postID: OME.ID<CommunicationPost>
            }

            public init(
                id: ID,
                title: String,
                contents: String,
                headerImageURL: URL? = nil,
                images: [OME.ImageAsset]? = nil,
                timestamp: Date? = nil,
                isPinned: Bool = false,
                sortIndex: Int
            ) {
                self.id = id
                self.title = title
                self.contents = contents
                self.headerImageURL = headerImageURL
                self.images = images
                self.timestamp = timestamp
                self.isPinned = isPinned
                self.sortIndex = sortIndex
            }

            public var id: ID
            public var title: String
            public var contents: String
            public var headerImageURL: URL?
            public var images: [OME.ImageAsset]?
            public var timestamp: Date?
            public var isPinned: Bool
            public var sortIndex: Int
        }

        public enum EventIDOrigin: String, Codable, Equatable, Sendable {
            case explicit
            case inferred
        }

        public struct EventSourceProvenance: Equatable, Sendable {
            public var eventID: OME.Event.ID
            public var eventIDOrigin: EventIDOrigin
            public var source: SourceProvenance
            public var sourceEventDirectory: String

            public init(
                eventID: OME.Event.ID,
                eventIDOrigin: EventIDOrigin,
                source: SourceProvenance,
                sourceEventDirectory: String
            ) {
                self.eventID = eventID
                self.eventIDOrigin = eventIDOrigin
                self.source = source
                self.sourceEventDirectory = sourceEventDirectory
            }
        }

        public enum SourceKind: String, Codable, Equatable, Sendable {
            case local
            case tangled
        }

        public struct SourceProvenance: Equatable, Sendable {
            public var kind: SourceKind
            public var reference: String
            public var ref: String?

            public init(
                kind: SourceKind,
                reference: String,
                ref: String? = nil
            ) {
                self.kind = kind
                self.reference = reference
                self.ref = ref
            }
        }

        public var eventSourceProvenances: [EventSourceProvenance]
        public var organizers: [OME.Organizer.Draft]
        public var calendars: [OME.Calendar.Draft]
        public var calendarEntries: [OME.CalendarEntry.Draft]
        public var events: [OME.Event.Draft]
        public var eventOrganizers: [OME.EventOrganizer.Draft]
        public var stages: [OME.Stage.Draft]
        public var schedules: [OME.Schedule.Draft]
        public var contributors: [OME.Contributor.Draft]
        public var channels: [OME.Channel.Draft]
        public var communicationPosts: [CommunicationPost]
        public var posters: [OME.Poster.Draft]
        public var scheduleItems: [OME.ScheduleItem.Draft]
        public var scheduleItemPerformanceDetails: [OME.ScheduleItem.PerformanceDetails.Draft]
        public var scheduleItemContributors: [OME.ScheduleItem.Contributor.Draft]
        public var relationships: [OME.Relationship]
        public var workspaceRelationships: [FileContent<OME.Relationship>]
        public var pendingFileImageAssets: [PendingFileImageAsset]

        public init(_ configuration: Configuration) throws {
            self.organizers = [
                OME.Organizer.Draft(id: configuration.organizerID)
            ]
            self.calendars = []
            self.calendarEntries = []
            self.eventSourceProvenances = []
            self.events = []
            self.eventOrganizers = []
            self.stages = []
            self.schedules = []
            self.contributors = []
            self.channels = []
            self.communicationPosts = []
            self.posters = []
            self.scheduleItems = []
            self.scheduleItemPerformanceDetails = []
            self.scheduleItemContributors = []
            self.relationships = []
            self.workspaceRelationships = []
            self.pendingFileImageAssets = []

            let workspaceReference = OME.Relationship.RecordReference(
                author: configuration.organizerID,
                collection: OME.SourceRecord.nsid,
                rkey: ATProto.Record.Key(rawValue: OME.SourceRecord.canonicalRecordKey)
            )
            var collaboratorIDs: Set<DID> = []
            for relationshipFile in configuration.source.collaborators ?? [] {
                let relationship = relationshipFile.data
                guard relationship.type == OME.Relationship.collection.rawValue,
                      case .collaborator = relationship.workspaceRole,
                      case let .known(.identity(identity)) = relationship.subject,
                      case let .known(.record(object)) = relationship.object,
                      object.uri == workspaceReference.uri,
                      object.cid == nil,
                      OME.Relationship.Validation.relationshipAuthor(
                          configuration.organizerID,
                          canAssert: relationship
                      )
                else {
                    throw Error.invalidWorkspaceRelationship(relationshipFile.fileName)
                }
                guard collaboratorIDs.insert(identity.did).inserted else {
                    throw Error.duplicateWorkspaceCollaborator(identity.did)
                }
                workspaceRelationships.append(relationshipFile)
            }

            let sourceCalendar = configuration.source.calendar ?? CalendarDTO.defaultCalendar
            var calendar = sourceCalendar.recordDraft(ownerID: configuration.organizerID)
            calendar.images = try resolve(
                sourceCalendar.images,
                organizerID: configuration.organizerID,
                eventID: nil,
                parentKind: "calendar",
                parentLocalID: OME.Calendar.defaultID.rawValue.rawValue,
                sourceDirectoryURL: configuration.sourceRootURL
            )
            self.calendars = [calendar]

            var resolvedEventIDs: Set<OME.Event.ID> = []
            for sourceEvent in configuration.source.events {
                try append(
                    sourceEvent: sourceEvent.components,
                    eventDirectoryName: sourceEvent.directoryName,
                    organizerID: configuration.organizerID,
                    sourceRootURL: configuration.sourceRootURL,
                    sourceProvenance: configuration.sourceProvenance,
                    resolvedEventIDs: &resolvedEventIDs
                )
            }
        }

        private mutating func append(
            sourceEvent: OpenMusicEventSourceEvent,
            eventDirectoryName: String,
            organizerID: OME.Organizer.ID,
            sourceRootURL: URL?,
            sourceProvenance: SourceProvenance?,
            resolvedEventIDs: inout Set<OME.Event.ID>
        ) throws {
            let eventIDOrigin: EventIDOrigin
            let explicitLocalEventID = sourceEvent.event.id?.eventID
            if explicitLocalEventID != nil {
                eventIDOrigin = .explicit
            } else {
                eventIDOrigin = .inferred
            }
            let eventID = Self.resolvedEventID(
                organizerID: organizerID,
                explicitLocalEventID: explicitLocalEventID,
                eventDirectoryName: eventDirectoryName,
                sourceProvenance: sourceProvenance
            )
            let localEventID = eventID.eventID
            let eventDirectoryURL = sourceRootURL?
                .appending(path: "events", directoryHint: .isDirectory)
                .appending(path: eventDirectoryName, directoryHint: .isDirectory)
            guard resolvedEventIDs.insert(eventID).inserted else {
                throw Error.duplicateEventID(eventID)
            }

            var event = sourceEvent.event.recordDraft
            event.id = eventID
            event.images = try resolve(
                sourceEvent.event.images,
                organizerID: organizerID,
                eventID: localEventID,
                parentKind: "event",
                parentLocalID: localEventID.rawValue.rawValue,
                sourceDirectoryURL: eventDirectoryURL
            )
            events.append(event)
            if let sourceProvenance {
                eventSourceProvenances.append(
                    EventSourceProvenance(
                        eventID: eventID,
                        eventIDOrigin: eventIDOrigin,
                        source: sourceProvenance,
                        sourceEventDirectory: eventDirectoryName
                    )
                )
            }
            eventOrganizers.append(
                OME.EventOrganizer.Draft(
                    id: .init(
                        organizerID: organizerID,
                        eventID: localEventID,
                        eventOrganizerID: organizerID
                    )
                )
            )
            relationships.append(
                OME.Relationship(
                    subject: .identity(did: organizerID),
                    role: .organizer,
                    object: .record(.init(eventID: eventID)),
                    createdAt: Self.pendingRelationshipCreatedAt
                )
            )
            calendarEntries.append(
                OME.CalendarEntry.Draft(
                    id: .init(
                        calendarOwnerID: organizerID,
                        calendarID: OME.Calendar.defaultID,
                        entryID: OME.ID<OME.CalendarEntry>(localEventID.rawValue)
                    ),
                    event: OME.Event.reference(id: eventID),
                    createdAt: .distantPast,
                    note: nil,
                    pinned: false
                )
            )

            let sourceStages = try sourceEvent.stages ?? Self.inferredStageFiles(for: sourceEvent)
            stages.append(
                contentsOf: try sourceStages.map { stage in
                    var draft = stage.data.recordDraft
                    let stageID = draft.id ?? .init(
                        organizerID: organizerID,
                        eventID: localEventID,
                        stageID: Self.localID(stage.fileName)
                    )
                    draft.id = stageID
                    draft.images = try resolve(
                        stage.data.images,
                        organizerID: organizerID,
                        eventID: localEventID,
                        parentKind: "stage",
                        parentLocalID: stageID.stageID.rawValue.rawValue,
                        sourceDirectoryURL: eventDirectoryURL
                    )
                    return draft
                }
            )

            let explicitContributors: [OME.Contributor.Draft] = try sourceEvent.contributors?.map { contributor in
                var draft = contributor.data.recordDraft
                let contributorID = draft.id ?? .init(
                    organizerID: organizerID,
                    eventID: localEventID,
                    contributorID: Self.localID(contributor.fileName)
                )
                draft.id = contributorID
                draft.images = try resolve(
                    contributor.data.images,
                    organizerID: organizerID,
                    eventID: localEventID,
                    parentKind: "contributor",
                    parentLocalID: contributorID.contributorID.rawValue.rawValue,
                    sourceDirectoryURL: eventDirectoryURL
                )
                return draft
            } ?? []

            contributors.append(contentsOf: explicitContributors)

            let scheduleContributorIndex = Self.scheduleContributorIndex(
                for: sourceEvent,
                organizerID: organizerID,
                eventID: localEventID,
                explicitContributors: explicitContributors
            )
            contributors.append(contentsOf: scheduleContributorIndex.generatedContributors)

            var relationshipContributorIDs: Set<OME.ID<OME.Contributor>> = []
            for contributor in explicitContributors + scheduleContributorIndex.generatedContributors {
                guard let contributorID = contributor.id,
                      relationshipContributorIDs.insert(contributorID.contributorID).inserted
                else { continue }

                relationships.append(
                    OME.Relationship(
                        subject: .record(.init(contributorID: contributorID)),
                        role: .contributor,
                        object: .record(.init(eventID: eventID)),
                        createdAt: Self.pendingRelationshipCreatedAt
                    )
                )
            }

            var channelIDsByFileName: [String: OME.ID<OME.Channel>] = [:]
            channels.append(
                contentsOf: sourceEvent.channels?.map { channel in
                    var draft = channel.data
                    let channelID = draft.id ?? .init(
                        organizerID: organizerID,
                        eventID: localEventID,
                        channelID: Self.localID(channel.fileName)
                    )
                    draft.id = channelID
                    channelIDsByFileName[channel.fileName] = channelID.channelID
                    return draft
                } ?? []
            )

            communicationPosts.append(
                contentsOf: try sourceEvent.communicationPosts?.flatMap { channelPosts in
                    let channelID = channelIDsByFileName[channelPosts.directoryName]
                        ?? Self.localID(channelPosts.directoryName)
                    return try channelPosts.components.enumerated().map { index, post in
                        let postID: OME.ID<CommunicationPost> = Self.localID(post.fileName)
                        return CommunicationPost(
                            id: .init(
                                organizerID: organizerID,
                                eventID: localEventID,
                                channelID: channelID,
                                postID: postID
                            ),
                            title: post.data.title,
                            contents: post.data.contents,
                            headerImageURL: post.data.headerImageURL,
                            images: try resolve(
                                post.data.images,
                                organizerID: organizerID,
                                eventID: localEventID,
                                parentKind: "communicationPost",
                                parentLocalID: "\(channelID.rawValue.rawValue)|\(postID.rawValue.rawValue)",
                                sourceDirectoryURL: eventDirectoryURL
                            ),
                            timestamp: post.data.timestamp,
                            isPinned: post.data.isPinned,
                            sortIndex: index
                        )
                    }
                } ?? []
            )

            posters.append(
                contentsOf: try sourceEvent.posters?.map { poster in
                    let draftID = poster.data.id ?? .init(
                        organizerID: organizerID,
                        eventID: localEventID,
                        posterID: Self.localID(poster.fileName)
                    )
                    let localPosterID = draftID.posterID.rawValue.rawValue
                    let resolvedImages = try resolve(
                        [poster.data.image],
                        organizerID: organizerID,
                        eventID: localEventID,
                        parentKind: "poster",
                        parentLocalID: localPosterID,
                        sourceDirectoryURL: eventDirectoryURL
                    )
                    guard let image = resolvedImages?.first else {
                        throw Error.missingPosterImage(poster.fileName)
                    }
                    return OME.Poster.Draft(
                        id: draftID,
                        title: poster.data.title,
                        image: image
                    )
                } ?? []
            )

            var resolvedScheduleIDs: Set<OME.ID<OME.Schedule>> = []
            if let inlineSchedule = sourceEvent.event.schedule {
                try append(
                    sourceSchedule: try SourceSchedule(
                        inlineSchedule,
                        eventID: eventID,
                        eventStartDate: event.startDate
                    ),
                    organizerID: organizerID,
                    eventID: localEventID,
                    timeZone: event.timeZone,
                    scheduleContributorIndex: scheduleContributorIndex,
                    resolvedScheduleIDs: &resolvedScheduleIDs
                )
            }
            for schedule in sourceEvent.schedules ?? [] {
                try append(
                    sourceSchedule: SourceSchedule(schedule.data, scheduleFileName: schedule.fileName),
                    organizerID: organizerID,
                    eventID: localEventID,
                    timeZone: event.timeZone,
                    scheduleContributorIndex: scheduleContributorIndex,
                    resolvedScheduleIDs: &resolvedScheduleIDs
                )
            }
        }

        private static func inferredStageFiles(
            for sourceEvent: OpenMusicEventSourceEvent
        ) throws -> [FileContent<StageDTO>] {
            let inlineScheduleItems = sourceEvent.event.schedule.map { [$0.scheduleItems] } ?? []
            let scheduleFileItems = sourceEvent.schedules?.map(\.data.scheduleItems) ?? []
            let stageIDs = Set(
                (inlineScheduleItems + scheduleFileItems)
                    .flatMap(\.keys)
            )
            let fileNames = stageIDs.isEmpty
                ? [OME.Stage.singletonID.rawValue.rawValue]
                : stageIDs.sorted()
            return try fileNames.map { fileName in
                try FileContent(
                    fileName: fileName,
                    fileType: "yml",
                    data: StageDTO(
                        name: Self.inferredStageName(for: fileName),
                        color: OME.Stage.singletonColor
                    )
                )
            }
        }

        private static func inferredStageName(for fileName: String) -> String {
            let words = fileName
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map { word in
                    word.prefix(1).uppercased() + String(word.dropFirst())
                }
            return words.isEmpty ? OME.Stage.singletonName : words.joined(separator: " ")
        }

        private struct SourceSchedule {
            var id: OME.ID<OME.Schedule>
            var date: LocalDate
            var startsAt: String?
            var endsAt: String?
            var customTitle: String?
            var scheduleItems: ScheduleDTO.ScheduleItems

            init(
                _ schedule: ScheduleDTO,
                scheduleFileName: String
            ) {
                self.id = schedule.id ?? SourceDatabaseInsertion.localID(scheduleFileName)
                self.date = schedule.date
                self.startsAt = schedule.startsAt
                self.endsAt = schedule.endsAt
                self.customTitle = schedule.customTitle
                self.scheduleItems = schedule.scheduleItems
            }

            init(
                _ schedule: InlineScheduleDTO,
                eventID: OME.Event.ID,
                eventStartDate: LocalDate?
            ) throws {
                guard let date = schedule.date ?? eventStartDate else {
                    throw Error.missingInlineScheduleDate(eventID)
                }
                self.id = OME.Schedule.singletonID
                self.date = date
                self.startsAt = schedule.startsAt
                self.endsAt = schedule.endsAt
                self.customTitle = schedule.customTitle
                self.scheduleItems = schedule.scheduleItems
            }
        }

        private mutating func append(
            sourceSchedule: SourceSchedule,
            organizerID: OME.Organizer.ID,
            eventID: OME.ID<OME.Event>,
            timeZone: TimeZone,
            scheduleContributorIndex: ScheduleContributorIndex,
            resolvedScheduleIDs: inout Set<OME.ID<OME.Schedule>>
        ) throws {
            let scheduleID = sourceSchedule.id
            let scopedScheduleID = OME.Schedule.ID(
                organizerID: organizerID,
                eventID: eventID,
                scheduleID: scheduleID
            )
            guard resolvedScheduleIDs.insert(scheduleID).inserted else {
                throw Error.duplicateScheduleID(scopedScheduleID)
            }

            schedules.append(
                OME.Schedule.Draft(
                    id: scopedScheduleID,
                    date: sourceSchedule.date,
                    startsAt: try sourceSchedule.startsAt?.localTimeDate(
                        on: sourceSchedule.date,
                        in: timeZone
                    ),
                    endsAt: try sourceSchedule.endsAt?.localTimeDate(
                        on: sourceSchedule.date,
                        in: timeZone
                    ),
                    customTitle: sourceSchedule.customTitle
                )
            )

            for stageIDString in sourceSchedule.scheduleItems.keys.sorted() {
                let sourceScheduleItems = sourceSchedule.scheduleItems[stageIDString] ?? []
                let stageID = OME.ID<OME.Stage>(.init(stageIDString))
                let resolvedStarts = try sourceScheduleItems.resolvedStartTimes(
                    on: sourceSchedule.date,
                    in: timeZone
                )

                for (offset, sourceScheduleItem) in sourceScheduleItems.enumerated() {
                    let index = offset + 1
                    let scheduleItemID = sourceScheduleItem.id
                        .map { OME.ID<OME.ScheduleItem>($0.rawValue) }
                        ?? Self.localID("\(scheduleID.rawValue.rawValue)-\(stageID.rawValue.rawValue)-\(index)")
                    let scopedScheduleItemID = OME.ScheduleItem.ID(
                        organizerID: organizerID,
                        eventID: eventID,
                        scheduleItemID: scheduleItemID
                    )
                    let startTime = resolvedStarts[offset]
                    let endTime: Date

                    if let explicitEndTime = sourceScheduleItem.endTime {
                        endTime = try explicitEndTime.localTimeDate(
                            on: sourceSchedule.date,
                            in: timeZone
                        ).advancedPast(startTime, in: timeZone)
                    } else if sourceScheduleItems.indices.contains(offset + 1) {
                        endTime = resolvedStarts[offset + 1]
                    } else {
                        throw Error.missingScheduleItemEndTime(
                            scheduleID: scopedScheduleID,
                            stageID: stageID,
                            scheduleItemIndex: index
                        )
                    }

                    scheduleItems.append(
                        OME.ScheduleItem.Draft(
                            id: scopedScheduleItemID,
                            stageID: stageID,
                            scheduleID: scheduleID,
                            kind: sourceScheduleItem.kind,
                            startTime: startTime,
                            endTime: endTime,
                            title: sourceScheduleItem.title,
                            description: sourceScheduleItem.description
                        )
                    )

                    if case .known(.performance) = sourceScheduleItem.kind {
                        scheduleItemPerformanceDetails.append(
                            OME.ScheduleItem.PerformanceDetails.Draft(
                                id: scopedScheduleItemID,
                                recordings: sourceScheduleItem.recordings ?? []
                            )
                        )
                    }

                    for (sortIndex, contributor) in (sourceScheduleItem.contributors ?? []).enumerated() {
                        let contributorID = try Self.contributorID(
                            for: contributor,
                            in: scheduleContributorIndex,
                            scheduleID: scopedScheduleID,
                            stageID: stageID,
                            scheduleItemIndex: index
                        )
                        let contributorActor = Self.actor(for: contributor)
                        scheduleItemContributors.append(
                            OME.ScheduleItem.Contributor.Draft(
                                id: .init(
                                    scheduleItemID: scopedScheduleItemID,
                                    sortIndex: sortIndex
                                ),
                                contributorID: contributorID,
                                anonymousName: Self.anonymousName(for: contributor),
                                contributorActor: contributorActor,
                                billing: contributor.billing,
                                role: contributor.role
                            )
                        )

                        guard case .known(.performance) = sourceScheduleItem.kind else { continue }
                        let scopedPerformanceID = OME.Performance.ID(
                            organizerID: organizerID,
                            eventID: eventID,
                            performanceID: OME.ID<OME.Performance>(scheduleItemID.rawValue)
                        )
                        if let relationship = Self.performanceContributorRelationship(
                            performanceID: scopedPerformanceID,
                            contributorID: contributorID,
                            contributorActor: contributorActor,
                            role: contributor.role
                        ) {
                            relationships.append(relationship)
                        }
                    }
                }
            }
        }

        private struct ScheduleContributorIndex {
            var generatedContributors: [OME.Contributor.Draft] = []
            var contributorIDs: Set<OME.ID<OME.Contributor>> = []
            var names: [String: OME.ID<OME.Contributor>] = [:]
            var actors: [OME.Contributor.Actor: OME.ID<OME.Contributor>] = [:]

            func contains(contributorID: OME.ID<OME.Contributor>) -> Bool {
                contributorIDs.contains(contributorID)
            }

            func contributorID(forName name: String) -> OME.ID<OME.Contributor>? {
                Self.nameKey(name).flatMap { names[$0] }
            }

            func contributorID(forActor actor: OME.Contributor.Actor) -> OME.ID<OME.Contributor>? {
                actors[actor]
            }

            mutating func addGeneratedContributor(
                for contributor: ScheduleDTO.ScheduleItem.Contributor,
                organizerID: OME.Organizer.ID,
                eventID: OME.ID<OME.Event>,
                usedContributorIDs: inout Set<OME.ID<OME.Contributor>>
            ) {
                switch contributor.subject {
                case .id:
                    return

                case let .name(name):
                    guard let displayName = SourceDatabaseInsertion.scheduleContributorDisplayName(forName: name),
                          let key = Self.nameKey(displayName),
                          names[key] == nil
                    else { return }

                    let contributorID = SourceDatabaseInsertion.generatedScheduleContributorID(
                        prefix: "schedule-name",
                        value: displayName,
                        usedContributorIDs: &usedContributorIDs
                    )
                    names[key] = contributorID
                    generatedContributors.append(
                        OME.Contributor.Draft(
                            id: .init(
                                organizerID: organizerID,
                                eventID: eventID,
                                contributorID: contributorID
                            ),
                            name: displayName,
                            did: nil,
                            bio: nil,
                            images: nil,
                            links: nil
                        )
                    )
                    contributorIDs.insert(contributorID)

                case let .actor(actor):
                    guard actors[actor] == nil else { return }

                    let displayName = actor.description
                    let contributorID = SourceDatabaseInsertion.generatedScheduleContributorID(
                        prefix: "schedule-actor",
                        value: displayName,
                        usedContributorIDs: &usedContributorIDs
                    )
                    actors[actor] = contributorID
                    generatedContributors.append(
                        OME.Contributor.Draft(
                            id: .init(
                                organizerID: organizerID,
                                eventID: eventID,
                                contributorID: contributorID
                            ),
                            name: displayName,
                            did: actor.didValue,
                            bio: nil,
                            images: nil,
                            links: nil
                        )
                    )
                    contributorIDs.insert(contributorID)
                }
            }

            mutating func addGeneratedScheduleContributors(
                from scheduleItemsByStageID: ScheduleDTO.ScheduleItems,
                organizerID: OME.Organizer.ID,
                eventID: OME.ID<OME.Event>,
                usedContributorIDs: inout Set<OME.ID<OME.Contributor>>
            ) {
                for stageID in scheduleItemsByStageID.keys.sorted() {
                    for scheduleItem in scheduleItemsByStageID[stageID] ?? [] {
                        for contributor in scheduleItem.contributors ?? [] {
                            addGeneratedContributor(
                                for: contributor,
                                organizerID: organizerID,
                                eventID: eventID,
                                usedContributorIDs: &usedContributorIDs
                            )
                        }
                    }
                }
            }

            static func nameKey(_ name: String) -> String? {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed.lowercased()
            }
        }

        private static func scheduleContributorIndex(
            for sourceEvent: OpenMusicEventSourceEvent,
            organizerID: OME.Organizer.ID,
            eventID: OME.ID<OME.Event>,
            explicitContributors: [OME.Contributor.Draft]
        ) -> ScheduleContributorIndex {
            var index = ScheduleContributorIndex(
                contributorIDs: Set(explicitContributors.compactMap { $0.id?.contributorID })
            )
            guard sourceEvent.event.policies?.contributors?.usesScheduleContributorListing == true else {
                return index
            }

            var usedContributorIDs = index.contributorIDs

            for contributor in explicitContributors {
                guard let contributorID = contributor.id?.contributorID,
                      let key = ScheduleContributorIndex.nameKey(contributor.name),
                      index.names[key] == nil
                else { continue }

                index.names[key] = contributorID
            }

            if let inlineSchedule = sourceEvent.event.schedule {
                index.addGeneratedScheduleContributors(
                    from: inlineSchedule.scheduleItems,
                    organizerID: organizerID,
                    eventID: eventID,
                    usedContributorIDs: &usedContributorIDs
                )
            }

            for schedule in sourceEvent.schedules ?? [] {
                index.addGeneratedScheduleContributors(
                    from: schedule.data.scheduleItems,
                    organizerID: organizerID,
                    eventID: eventID,
                    usedContributorIDs: &usedContributorIDs
                )
            }

            return index
        }

        private static func contributorID(
            for contributor: ScheduleDTO.ScheduleItem.Contributor,
            in index: ScheduleContributorIndex,
            scheduleID: OME.Schedule.ID,
            stageID: OME.ID<OME.Stage>,
            scheduleItemIndex: Int
        ) throws -> OME.ID<OME.Contributor>? {
            switch contributor.subject {
            case let .id(contributorID):
                guard index.contains(contributorID: contributorID) else {
                    throw Error.missingScheduleContributorID(
                        scheduleID: scheduleID,
                        stageID: stageID,
                        scheduleItemIndex: scheduleItemIndex,
                        contributorID: contributorID
                    )
                }
                return contributorID
            case let .name(name):
                return index.contributorID(forName: name)
            case let .actor(actor):
                return index.contributorID(forActor: actor)
            }
        }

        private static func anonymousName(
            for contributor: ScheduleDTO.ScheduleItem.Contributor
        ) -> String? {
            guard case let .name(name) = contributor.subject else { return nil }
            return name
        }

        private static func actor(
            for contributor: ScheduleDTO.ScheduleItem.Contributor
        ) -> OME.Contributor.Actor? {
            guard case let .actor(actor) = contributor.subject else { return nil }
            return actor
        }

        private static func performanceContributorRelationship(
            performanceID: OME.Performance.ID,
            contributorID: OME.ID<OME.Contributor>?,
            contributorActor: OME.Contributor.Actor?,
            role: OME.Performance.Contributors.Role?
        ) -> OME.Relationship? {
            let subject: OME.Relationship.Entity
            if let contributorID {
                subject = .record(
                    .init(
                        contributorID: .init(
                            organizerID: performanceID.organizerID,
                            eventID: performanceID.eventID,
                            contributorID: contributorID
                        )
                    )
                )
            } else if let did = contributorActor?.didValue {
                subject = .identity(did: did)
            } else {
                return nil
            }

            return OME.Relationship(
                subject: subject,
                role: role.map { OME.Relationship.Role($0.rawValue) } ?? .performer,
                object: .record(.init(performanceID: performanceID)),
                createdAt: pendingRelationshipCreatedAt
            )
        }

        private static func scheduleContributorDisplayName(forName name: String) -> String? {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        private static func generatedScheduleContributorID(
            prefix: String,
            value: String,
            usedContributorIDs: inout Set<OME.ID<OME.Contributor>>
        ) -> OME.ID<OME.Contributor> {
            let encodedValue = value.addingPercentEncoding(
                withAllowedCharacters: generatedContributorIDAllowedCharacters
            ) ?? value
            let baseID = "\(prefix)-\(encodedValue)"
            var candidate = OME.ID<OME.Contributor>(.init(baseID))
            var suffix = 2

            while usedContributorIDs.contains(candidate) {
                candidate = OME.ID<OME.Contributor>(.init("\(baseID)-\(suffix)"))
                suffix += 1
            }

            usedContributorIDs.insert(candidate)
            return candidate
        }

        private static var generatedContributorIDAllowedCharacters: CharacterSet {
            CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        }

        private static let pendingRelationshipCreatedAt = "1970-01-01T00:00:00Z"

        private mutating func resolve(
            _ sourceImages: [SourceImageAsset]?,
            organizerID: OME.Organizer.ID,
            eventID: OME.ID<OME.Event>?,
            parentKind: String,
            parentLocalID: String,
            sourceDirectoryURL: URL?
        ) throws -> [OME.ImageAsset]? {
            let images = try sourceImages?.bundlingAppearancePairs().flatMap { image in
                try image.payloads.map { variant in
                    let assetKey = variant.payload.assetKey
                        ?? makeAssetKey(
                            organizerID: organizerID,
                            eventID: eventID,
                            parentKind: parentKind,
                            parentLocalID: parentLocalID,
                            role: image.role,
                            appearance: variant.appearance
                        )

                    let resolvedSource: OME.ImageAsset.Source
                    switch variant.payload.source {
                    case let .url(url):
                        resolvedSource = .url(url)

                    case let .file(path):
                        guard let sourceDirectoryURL else {
                            throw Error.missingSourceRootForFileAsset(path)
                        }

                        let sourceURL = sourceDirectoryURL
                            .appending(path: path)
                            .standardizedFileURL
                        let data = try Data(contentsOf: sourceURL)
                        pendingFileImageAssets.append(
                            PendingFileImageAsset(
                                assetKey: assetKey,
                                sourceURL: sourceURL,
                                mimeType: sourceURL.inferredImageMimeType,
                                data: data
                            )
                        )
                        resolvedSource = .url(sourceURL)
                    }

                    return OME.ImageAsset(
                        assetKey: assetKey,
                        source: resolvedSource,
                        role: image.role,
                        renderKind: image.renderKind,
                        appearance: variant.appearance,
                        materializationPolicy: image.materializationPolicy,
                        thumbhash: variant.payload.thumbhash,
                        focalPoint: variant.payload.focalPoint
                    )
                }
            }

            guard let images, !images.isEmpty else { return nil }
            return images
        }

        private func makeAssetKey(
            organizerID: OME.Organizer.ID,
            eventID: OME.ID<OME.Event>?,
            parentKind: String,
            parentLocalID: String,
            role: OME.ImageAsset.Role,
            appearance: OME.ImageAsset.Appearance?
        ) -> String {
            var components = [organizerID.description]
            if let eventID {
                components.append(eventID.rawValue.rawValue)
            }
            components.append(contentsOf: [
                parentKind,
                parentLocalID,
                role.rawValue,
                appearance?.rawValue ?? "default",
            ])
            return components.joined(separator: "|")
        }

        private static func localID<Record>(_ string: String) -> OME.ID<Record> {
            OME.ID<Record>(.init(string))
        }

        public static func resolvedEventID(
            organizerID: OME.Organizer.ID,
            explicitLocalEventID: OME.ID<OME.Event>?,
            eventDirectoryName: String,
            sourceProvenance: SourceProvenance?
        ) -> OME.Event.ID {
            OME.Event.ID(
                organizerID: organizerID,
                eventID: explicitLocalEventID ?? inferredEventID(
                    eventDirectoryName: eventDirectoryName,
                    sourceProvenance: sourceProvenance
                )
            )
        }

        public static func inferredEventID(
            eventDirectoryName: String,
            sourceProvenance: SourceProvenance?
        ) -> OME.ID<OME.Event> {
            let rawValue = if let sourceProvenance {
                "\(sourceProvenance.inferredEventIDPrefix)-\(eventDirectoryName)"
            } else {
                eventDirectoryName
            }
            return OME.ID<OME.Event>(.init(rawValue))
        }
    }
}

private extension OME.SourceDatabaseInsertion.SourceProvenance {
    var inferredEventIDPrefix: String {
        switch kind {
        case .local:
            return URL(fileURLWithPath: reference).lastPathComponent

        case .tangled:
            return reference
                .split(separator: "/", omittingEmptySubsequences: true)
                .last
                .map(String.init)
                ?? reference
        }
    }
}

private extension OME.Contributor.Actor {
    var didValue: DID? {
        if case let .did(did) = identifier {
            return did
        }
        return nil
    }
}

private extension Array where Element == ScheduleDTO.ScheduleItem {
    func resolvedStartTimes(on date: LocalDate, in timeZone: TimeZone) throws -> [Date] {
        var resolved: [Date] = []
        resolved.reserveCapacity(count)

        for scheduleItem in self {
            var startTime = try scheduleItem.startTime.localTimeDate(
                on: date,
                in: timeZone
            )
            if let previousStartTime = resolved.last {
                startTime = startTime.advancedPast(previousStartTime, in: timeZone)
            }
            resolved.append(startTime)
        }

        return resolved
    }
}

private extension String {
    func localTimeDate(on date: LocalDate, in timeZone: TimeZone) throws -> Date {
        let parts = split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              let second = parts.count == 3 ? Int(parts[2]) : 0,
              let date = date.at(hour: hour, minute: minute, second: second, in: timeZone)
        else {
            throw OME.SourceDatabaseInsertion.Error.invalidLocalTime(self)
        }

        return date
    }
}

private extension Date {
    func advancedPast(_ previousDate: Date, in timeZone: TimeZone) -> Date {
        var date = self
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        while date <= previousDate {
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date)
            else { break }
            date = nextDate
        }
        return date
    }
}

private extension OME.Event.ContributorPolicies {
    var usesScheduleContributorListing: Bool {
        if case .known(.scheduleContributors)? = listing {
            return true
        }
        return false
    }
}

extension OME.SourceDatabaseInsertion.Error: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .conflictingInferredEventID(
            eventID,
            _,
            _,
            incomingSourceKind,
            incomingSourceReference
        ):
            return """
            Inferred event ID '\(eventID.eventID.rawValue.rawValue)' for organizer '\(eventID.organizerID)' already belongs to another source. Add an explicit event ID to import \(incomingSourceKind.rawValue) source \(incomingSourceReference).
            """

        case let .duplicateEventID(eventID):
            return "Source resolves more than one event to '\(eventID.eventID.rawValue.rawValue)' for organizer '\(eventID.organizerID)'. Give each event a unique explicit ID."

        case let .duplicateWorkspaceCollaborator(actorID):
            return "Workspace source contains more than one collaborator relationship for '\(actorID)'. Keep one active relationship per collaborator."

        case let .invalidWorkspaceRelationship(fileName):
            return "Collaborator file '\(fileName)' must contain a collaborator relationship from an actor DID to this workspace's source record."

        case let .invalidLocalTime(value):
            return "Invalid local time: \(value)"

        case let .missingPosterImage(fileName):
            return "Poster \(fileName) is missing an image asset."

        case let .missingSourceRootForFileAsset(path):
            return "Cannot resolve file-backed image asset without a source root URL: \(path)"

        case let .missingScheduleItemEndTime(scheduleID, stageID, scheduleItemIndex):
            return "Missing end time for schedule item \(scheduleItemIndex) in schedule '\(scheduleID.scheduleID.rawValue.rawValue)' on stage '\(stageID.rawValue.rawValue)'."

        case let .missingScheduleContributorID(scheduleID, stageID, scheduleItemIndex, contributorID):
            return "Missing contributor '\(contributorID.rawValue.rawValue)' for schedule item \(scheduleItemIndex) in schedule '\(scheduleID.scheduleID.rawValue.rawValue)' on stage '\(stageID.rawValue.rawValue)'. Add a contributor file for this ID or use a name/actor schedule contributor."

        case let .missingInlineScheduleDate(eventID):
            return "Inline schedule for event '\(eventID.eventID.rawValue.rawValue)' is missing a date. Add schedule.date or event.startDate."

        case let .duplicateScheduleID(scheduleID):
            return "Source resolves more than one schedule to '\(scheduleID.scheduleID.rawValue.rawValue)' for event '\(scheduleID.eventID.rawValue.rawValue)'. Give each schedule a unique ID."
        }
    }
}

private extension URL {
    var inferredImageMimeType: String {
        switch pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        case "svg":
            return "image/svg+xml"
        default:
            return "application/octet-stream"
        }
    }
}
