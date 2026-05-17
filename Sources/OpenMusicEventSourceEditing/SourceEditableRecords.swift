import CustomDump
import Foundation
import Lexicon
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
            Event.sourceRecordType(
                projection: SourceComparableEvent.init,
                semanticallyEqualColumn: { columnName, baseline, working in
                    columnName == "images"
                        && sourceComparableImages(baseline.images) == sourceComparableImages(working.images)
                }
            ),
            Stage.sourceRecordType(
                projection: SourceComparableStage.init,
                semanticallyEqualColumn: { columnName, baseline, working in
                    columnName == "images"
                        && sourceComparableImages(baseline.images) == sourceComparableImages(working.images)
                }
            ),
            Participant.sourceRecordType(
                projection: SourceComparableParticipant.init,
                semanticallyEqualColumn: { columnName, baseline, working in
                    columnName == "images"
                        && sourceComparableImages(baseline.images) == sourceComparableImages(working.images)
                }
            ),
            Schedule.sourceRecordType,
            Channel.sourceRecordType,
            Poster.sourceRecordType(
                projection: SourceComparablePoster.init,
                semanticallyEqualColumn: { columnName, baseline, working in
                    columnName == "image"
                        && baseline.image.sourceComparable == working.image.sourceComparable
                }
            ),
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

private extension SourceEditableTable where QueryOutput: Sendable {
    static func sourceRecordType<Projection: Equatable & Sendable>(
        projection: @escaping (QueryOutput) -> Projection,
        semanticallyEqualColumn: @escaping (String, QueryOutput, QueryOutput) -> Bool
    ) -> AnySourceEditableRecordType {
        AnySourceEditableRecordType(
            descriptor: sourceDescriptor,
            resolveRecordChange: { change, db, baselineSchemaName in
                let baselineRecord = try sourceRecord(
                    for: change,
                    schemaName: baselineSchemaName,
                    in: db
                )
                let workingRecord = try sourceRecord(
                    for: change,
                    schemaName: "main",
                    in: db
                )

                var resolvedChange = change
                if let baselineRecord, let workingRecord {
                    resolvedChange.fieldChanges.removeAll { fieldChange in
                        semanticallyEqualColumn(
                            fieldChange.columnName,
                            baselineRecord,
                            workingRecord
                        )
                    }
                }
                guard !resolvedChange.fieldChanges.isEmpty else {
                    return nil
                }

                let includedColumnNames = Set(resolvedChange.fieldChanges.map(\.columnName))
                let baseline = SourceComparableRecordSnapshot(
                    record: baselineRecord.map(projection),
                    includedColumnNames: includedColumnNames
                )
                let working = SourceComparableRecordSnapshot(
                    record: workingRecord.map(projection),
                    includedColumnNames: includedColumnNames
                )
                resolvedChange.recordDiff = diff(baseline, working) ?? ""
                return resolvedChange
            }
        )
    }
}

private struct SourceComparableRecordSnapshot<Record: Sendable>: Sendable, CustomDumpRepresentable {
    var record: Record?
    var includedColumnNames: Set<String>

    var customDumpValue: Any {
        if let record {
            SourceComparableRecordDump(
                record: record,
                includedColumnNames: includedColumnNames
            )
        } else {
            "missing"
        }
    }
}

private struct SourceComparableRecordDump<Record: Sendable>: Sendable, CustomDumpReflectable {
    var record: Record
    var includedColumnNames: Set<String>

    var customDumpMirror: Mirror {
        let mirror = Mirror(reflecting: record)
        let children = mirror.children.compactMap { child -> Mirror.Child? in
            guard let label = child.label,
                  includedColumnNames.contains(label)
            else { return nil }

            return child
        }

        return Mirror(
            record,
            children: children,
            displayStyle: mirror.displayStyle
        )
    }
}

private struct SourceComparableEvent: Equatable, Sendable {
    var id: OME.Event.ID
    var name: String
    var description: String?
    var startDate: LocalDate?
    var endDate: LocalDate?
    var status: Open<OME.Event.Status>?
    var mode: Open<OME.Event.Mode>?
    var locations: [OME.Event.Location]?
    var uris: [OME.Event.EventURI]?
    var timeZone: TimeZone
    var images: [SourceComparableImageAsset]?
    var contactNumbers: [OME.Event.ContactNumber]?
    var categoryConfigs: OME.Event.CategoryConfigs?

    init(_ event: OME.Event) {
        self.id = event.id
        self.name = event.name
        self.description = event.description
        self.startDate = event.startDate
        self.endDate = event.endDate
        self.status = event.status
        self.mode = event.mode
        self.locations = event.locations
        self.uris = event.uris
        self.timeZone = event.timeZone
        self.images = sourceComparableImages(event.images)
        self.contactNumbers = event.contactNumbers
        self.categoryConfigs = event.categoryConfigs
    }
}

private struct SourceComparableStage: Equatable, Sendable {
    var id: OME.Stage.ID
    var name: String
    var color: OMEColor
    var category: OME.Stage.Category?
    var sortIndex: Int?
    var images: [SourceComparableImageAsset]?
    var systemIconName: String?
    var iconShortCode: String?
    var lineup: [OME.ID<OME.Participant>]?

    init(_ stage: OME.Stage) {
        self.id = stage.id
        self.name = stage.name
        self.color = stage.color
        self.category = stage.category
        self.sortIndex = stage.sortIndex
        self.images = sourceComparableImages(stage.images)
        self.systemIconName = stage.systemIconName
        self.iconShortCode = stage.iconShortCode
        self.lineup = stage.lineup
    }
}

private struct SourceComparableParticipant: Equatable, Sendable {
    var id: OME.Participant.ID
    var name: String
    var bio: String?
    var images: [SourceComparableImageAsset]?
    var kind: OME.Participant.Kind?
    var links: [ExternalPlatform.Link]?

    init(_ participant: OME.Participant) {
        self.id = participant.id
        self.name = participant.name
        self.bio = participant.bio
        self.images = sourceComparableImages(participant.images)
        self.kind = participant.kind
        self.links = participant.links
    }
}

private struct SourceComparablePoster: Equatable, Sendable {
    var id: OME.Poster.ID
    var title: String?
    var image: SourceComparableImageAsset

    init(_ poster: OME.Poster) {
        self.id = poster.id
        self.title = poster.title
        self.image = poster.image.sourceComparable
    }
}

private struct SourceComparableImageAsset: Equatable, Sendable {
    var assetKey: String?
    var source: SourceComparableImageSource
    var role: OME.ImageAsset.Role
    var renderKind: OME.ImageAsset.RenderKind
    var appearance: OME.ImageAsset.Appearance?
    var materializationPolicy: OME.ImageAsset.MaterializationPolicy
    var thumbhash: String?
    var focalPoint: OME.ImageAsset.FocalPoint?

    init(_ image: OME.ImageAsset) {
        self.assetKey = image.assetKey
        self.source = SourceComparableImageSource(
            image.source,
            assetKey: image.assetKey
        )
        self.role = image.role
        self.renderKind = image.renderKind
        self.appearance = image.appearance
        self.materializationPolicy = image.materializationPolicy
        self.thumbhash = image.thumbhash
        self.focalPoint = image.focalPoint
    }
}

private enum SourceComparableImageSource: Equatable, Sendable {
    case fileIdentity(String)
    case source(OME.ImageAsset.Source)

    init(
        _ source: OME.ImageAsset.Source,
        assetKey: String?
    ) {
        switch source {
        case let .url(url) where url.isFileURL:
            self = .fileIdentity(
                assetKey ?? url.sourceEditingFileIdentity
            )
        default:
            self = .source(source)
        }
    }
}

private extension OME.ImageAsset {
    var sourceComparable: SourceComparableImageAsset {
        SourceComparableImageAsset(self)
    }
}

private func sourceComparableImages(
    _ images: [OME.ImageAsset]?
) -> [SourceComparableImageAsset]? {
    images?.map(\.sourceComparable)
}

private extension URL {
    var sourceEditingFileIdentity: String {
        let lastPathComponent = standardizedFileURL.lastPathComponent
        if !lastPathComponent.isEmpty {
            return lastPathComponent
        }
        return standardizedFileURL.path
    }
}
