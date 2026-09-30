import Foundation
import ATProtoTypes
import OpenMusicEventLexicon

do {
    try LexiconExporter.run([
        OpenMusicEventLexicon.Event.self,
        OpenMusicEventLexicon.Stage.self,
        EventPlace.self,
        Program.self,
        OpenMusicEventLexicon.Schedule.self,
        ProgramItem.self,
        Contributor.self,
        Social.Post.self,
        Social.Category.self,
        OME.Color.self,
        OME.SemanticIcon.self,
    ])
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
