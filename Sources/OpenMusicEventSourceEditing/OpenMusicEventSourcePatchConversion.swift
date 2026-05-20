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

            let participants = try await database.read { db in
                try OME.Participant
                    .where { $0.id.organizerID.eq(request.eventID.organizerID) }
                    .where { $0.id.eventID.eq(request.eventID.eventID) }
                    .fetchAll(db)
            }

            var sourceEvent = sourceEvent
            sourceEvent.participants = try sourceEvent.sourceParticipantFiles(
                from: participants
            )
            return sourceEvent
        }
    }
}

private extension OpenMusicEventSourceEvent {
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

private extension FileContent where Component == ParticipantDTO {
    var sourceParticipantID: OME.ID<OME.Participant> {
        data.id?.participantID ?? OME.ID<OME.Participant>(.init(fileName))
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
