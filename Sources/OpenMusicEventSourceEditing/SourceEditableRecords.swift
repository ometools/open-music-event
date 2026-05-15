import OpenMusicEventLexicon
import SourceEditing

public extension OME {
    static var sourceRecordTypes: [any SourceEditableTable.Type] {
        [
            Event.self,
            Stage.self,
            Participant.self,
            Schedule.self,
            Channel.self,
            Poster.self,
        ]
    }

    static var sourceTableDescriptors: [SourceTableDescriptor] {
        [
            Event.sourceDescriptor,
            Stage.sourceDescriptor,
            Participant.sourceDescriptor,
            Schedule.sourceDescriptor,
            Channel.sourceDescriptor,
            Poster.sourceDescriptor,
        ]
    }
}

extension OME.Event: SourceEditableTable {}
extension OME.Stage: SourceEditableTable {}
extension OME.Participant: SourceEditableTable {}
extension OME.Schedule: SourceEditableTable {}
extension OME.Channel: SourceEditableTable {}
extension OME.Poster: SourceEditableTable {}
