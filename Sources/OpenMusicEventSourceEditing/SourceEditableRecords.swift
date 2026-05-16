import OpenMusicEventLexicon
import SourceEditing

public extension OME {
    static var sourceRecordTableTypes: [any SourceEditableTable.Type] {
        [
            Event.self,
            Stage.self,
            Participant.self,
            Schedule.self,
            Channel.self,
            Poster.self,
        ]
    }

    static var sourceRecordTypes: [AnySourceEditableRecordType] {
        [
            Event.sourceRecordType,
            Stage.sourceRecordType,
            Participant.sourceRecordType,
            Schedule.sourceRecordType,
            Channel.sourceRecordType,
            Poster.sourceRecordType,
        ]
    }

    static var sourceTableDescriptors: [SourceTableDescriptor] {
        sourceRecordTypes.map(\.descriptor)
    }
}

extension OME.Event: SourceEditableTable {}
extension OME.Stage: SourceEditableTable {}
extension OME.Participant: SourceEditableTable {}
extension OME.Schedule: SourceEditableTable {}
extension OME.Channel: SourceEditableTable {}
extension OME.Poster: SourceEditableTable {}
