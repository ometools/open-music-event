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

            let (event, stages, participants, posters) = try await database.read { db in
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

                let participants = try OME.Participant
                    .where { $0.id.organizerID.eq(request.eventID.organizerID) }
                    .where { $0.id.eventID.eq(request.eventID.eventID) }
                    .fetchAll(db)

                let posters = try OME.Poster
                    .where { $0.id.organizerID.eq(request.eventID.organizerID) }
                    .where { $0.id.eventID.eq(request.eventID.eventID) }
                    .fetchAll(db)

                return (event, stages, participants, posters)
            }

            var sourceEvent = sourceEvent
            sourceEvent.event = EventDTO(
                event.sourceDraft(preservingSourceID: sourceEvent.event.id)
            )
            sourceEvent.stages = try sourceEvent.sourceStageFiles(
                from: stages
            )
            sourceEvent.participants = try sourceEvent.sourceParticipantFiles(
                from: participants
            )
            sourceEvent.posters = try sourceEvent.sourcePosterFiles(
                from: posters
            )
            return sourceEvent
        }
    }
}

public enum OpenMusicEventSourcePatchConversionError: Equatable, Error, Sendable {
    case eventNotFound(OME.Event.ID)
}

private extension OpenMusicEventSourceEvent {
    func sourceStageFiles(
        from stages: [OME.Stage]
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
        from posters: [OME.Poster]
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

    func sourceParticipantFiles(
        from participants: [OME.Participant]
    ) throws -> [FileContent<ParticipantDTO>]? {
        let participantsByID = Dictionary(
            uniqueKeysWithValues: participants.map { ($0.id.participantID, $0) }
        )
        var consumedParticipantIDs: Set<OME.ID<OME.Participant>> = []
        var files: [FileContent<ParticipantDTO>] = []

        for file in self.participants ?? [] {
            let participantID = file.sourceParticipantID
            guard let participant = participantsByID[participantID] else {
                continue
            }

            consumedParticipantIDs.insert(participantID)
            files.append(
                try file.map { sourceParticipant in
                    ParticipantDTO(
                        participant.sourceDraft(
                            preservingSourceID: sourceParticipant.id
                        )
                    )
                }
            )
        }

        let additions = participants
            .filter { !consumedParticipantIDs.contains($0.id.participantID) }
            .sorted { lhs, rhs in
                lhs.id.participantID.rawValue.rawValue < rhs.id.participantID.rawValue.rawValue
            }

        for participant in additions {
            files.append(
                try FileContent(
                    fileName: participant.id.participantID.rawValue.rawValue,
                    fileType: "md",
                    data: ParticipantDTO(
                        participant.sourceDraft(preservingSourceID: nil)
                    )
                )
            )
        }

        return files.isEmpty ? nil : files
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

private extension FileContent where Component == ParticipantDTO {
    var sourceParticipantID: OME.ID<OME.Participant> {
        data.id?.participantID ?? OME.ID<OME.Participant>(.init(fileName))
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
            categoryConfigs: categoryConfigs
        )
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

private extension OME.Participant {
    func sourceDraft(
        preservingSourceID id: OME.Participant.ID?
    ) -> OME.Participant.Draft {
        OME.Participant.Draft(
            id: id,
            name: name,
            bio: bio,
            images: images,
            kind: kind,
            links: links
        )
    }
}
