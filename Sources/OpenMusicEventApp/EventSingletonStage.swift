import FileTree
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData

enum EventSingletonStage {
    static func draft(eventID: OMERecord.Event.ID) -> OMERecord.Stage.Draft {
        OMERecord.Stage.Draft(
            id: OMERecord.Stage.ID(
                organizerID: eventID.organizerID,
                eventID: eventID.eventID,
                stageID: OMERecord.Stage.singletonID
            ),
            name: OMERecord.Stage.singletonName,
            color: OMERecord.Stage.singletonColor,
            category: nil,
            sortIndex: nil,
            images: nil,
            systemIconName: nil,
            iconShortCode: nil,
            lineup: nil
        )
    }

    static func insert(eventID: OMERecord.Event.ID, in db: Database) throws {
        try OMERecord.Stage.insert {
            draft(eventID: eventID)
        }
        .execute(db)
    }

    static func sourceFile() throws -> FileContent<StageDTO> {
        try FileContent(
            fileName: OMERecord.Stage.singletonID.rawValue.rawValue,
            fileType: "yml",
            data: StageDTO(
                name: OMERecord.Stage.singletonName,
                color: OMERecord.Stage.singletonColor
            )
        )
    }
}
