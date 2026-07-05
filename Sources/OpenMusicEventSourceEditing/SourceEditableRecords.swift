import CustomDump
import Foundation
import GRDB
import Lexicon
import OpenMusicEventLexicon
import SourceEditing

public extension OME {
    static var sourceMetadataRecordTypes: [AnySourceEditableRecordType] {
        [
            Calendar.sourceRecordType(
                projection: SourceComparableCalendar.init,
                semanticallyEqualColumn: { columnName, baseline, working in
                    guard columnName == "images",
                          let baselineImages = sourceComparableImages(baseline.images),
                          let workingImages = sourceComparableImages(working.images)
                    else { return false }
                    return baselineImages == workingImages
                },
                semanticallyEqualFieldChange: sourceImageArraysAreEqual(columnName: "images"),
                fieldDiff: sourceImageArrayFieldDiff(columnName: "images")
            ),
        ]
    }

    static var sourceRecordTableTypes: [any SourceEditableTable.Type] {
        [
            Event.self,
            Stage.self,
            Contributor.self,
            Schedule.self,
            Performance.self,
            Channel.self,
            Poster.self,
        ]
    }

    static var sourceRecordTypes: [AnySourceEditableRecordType] {
        [
            Event.sourceRecordType(
                projection: SourceComparableEvent.init,
                semanticallyEqualColumn: { columnName, baseline, working in
                    guard columnName == "images",
                          let baselineImages = sourceComparableImages(baseline.images),
                          let workingImages = sourceComparableImages(working.images)
                    else { return false }
                    return baselineImages == workingImages
                },
                semanticallyEqualFieldChange: sourceImageArraysAreEqual(columnName: "images"),
                fieldDiff: sourceImageArrayFieldDiff(columnName: "images")
            ),
            Stage.sourceRecordType(
                projection: SourceComparableStage.init,
                semanticallyEqualColumn: { columnName, baseline, working in
                    guard columnName == "images",
                          let baselineImages = sourceComparableImages(baseline.images),
                          let workingImages = sourceComparableImages(working.images)
                    else { return false }
                    return baselineImages == workingImages
                },
                semanticallyEqualFieldChange: sourceImageArraysAreEqual(columnName: "images"),
                fieldDiff: sourceImageArrayFieldDiff(columnName: "images")
            ),
            Contributor.sourceRecordType(
                projection: SourceComparableContributor.init,
                semanticallyEqualColumn: { columnName, baseline, working in
                    guard columnName == "images",
                          let baselineImages = sourceComparableImages(baseline.images),
                          let workingImages = sourceComparableImages(working.images)
                    else { return false }
                    return baselineImages == workingImages
                },
                semanticallyEqualFieldChange: sourceImageArraysAreEqual(columnName: "images"),
                fieldDiff: sourceImageArrayFieldDiff(columnName: "images")
            ),
            Schedule.sourceRecordType,
            Performance.sourceRecordType,
            Channel.sourceRecordType,
            Poster.sourceRecordType(
                projection: SourceComparablePoster.init,
                semanticallyEqualColumn: { columnName, baseline, working in
                    guard columnName == "image" else { return false }
                    return baseline.image.sourceComparable == working.image.sourceComparable
                },
                semanticallyEqualFieldChange: sourceImagesAreEqual(columnName: "image"),
                fieldDiff: sourceImageFieldDiff(columnName: "image")
            ),
        ]
    }

    static var sourceTableDescriptors: [SourceTableDescriptor] {
        sourceRecordTypes.map(\.descriptor)
    }
}

extension OME.Calendar: SourceEditableTable {}
extension OME.Event: SourceEditableTable {}
extension OME.Stage: SourceEditableTable {}
extension OME.Contributor: SourceEditableTable {}
extension OME.Schedule: SourceEditableTable {}
extension OME.Performance: SourceEditableTable {}
extension OME.Channel: SourceEditableTable {}
extension OME.Poster: SourceEditableTable {}

private extension SourceEditableTable where QueryOutput: Sendable {
    static func sourceRecordType<Projection: Equatable & Sendable>(
        projection: @escaping (QueryOutput) -> Projection,
        semanticallyEqualColumn: @escaping (String, QueryOutput, QueryOutput) -> Bool,
        semanticallyEqualFieldChange: @escaping (SourceFieldChange) -> Bool = { _ in false },
        fieldDiff: @escaping (SourceRecordChange) -> String? = { _ in nil }
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
                        semanticallyEqualFieldChange(fieldChange)
                            || semanticallyEqualColumn(
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
                if let rawFieldDiff = fieldDiff(resolvedChange) {
                    if resolvedChange.recordDiff?.isEmpty == false {
                        resolvedChange.recordDiff?.append("\n")
                    }
                    resolvedChange.recordDiff?.append(rawFieldDiff)
                }
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
    var policies: OME.Event.Policies?
    var reportingLink: OME.Event.ReportingLink?

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
        self.policies = event.policies
        self.reportingLink = event.reportingLink
    }
}

private struct SourceComparableCalendar: Equatable, Sendable {
    var id: OME.Calendar.ID
    var name: String
    var description: String?
    var images: [SourceComparableImageAsset]?

    init(_ calendar: OME.Calendar) {
        self.id = calendar.id
        self.name = calendar.name
        self.description = calendar.description
        self.images = sourceComparableImages(calendar.images)
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
    var lineup: [OME.ID<OME.Contributor>]?

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

private struct SourceComparableContributor: Equatable, Sendable {
    var id: OME.Contributor.ID
    var name: String
    var bio: String?
    var images: [SourceComparableImageAsset]?
    var links: [ExternalPlatform.Link]?

    init(_ contributor: OME.Contributor) {
        self.id = contributor.id
        self.name = contributor.name
        self.bio = contributor.bio
        self.images = sourceComparableImages(contributor.images)
        self.links = contributor.links
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.assetKey == rhs.assetKey
            && SourceComparableImageSource.semanticallyEqual(
                lhs.source,
                rhs.source,
                assetKey: lhs.assetKey
            )
            && lhs.role == rhs.role
            && lhs.renderKind == rhs.renderKind
            && lhs.appearance == rhs.appearance
            && lhs.materializationPolicy == rhs.materializationPolicy
            && lhs.thumbhash == rhs.thumbhash
            && lhs.focalPoint == rhs.focalPoint
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

    static func semanticallyEqual(
        _ lhs: Self,
        _ rhs: Self,
        assetKey: String?
    ) -> Bool {
        if lhs == rhs {
            return true
        }

        guard let assetKey else { return false }
        switch (lhs, rhs) {
        case let (.fileIdentity(identity), .source(.url(url))),
             let (.source(.url(url)), .fileIdentity(identity)):
            return !url.isFileURL && identity == assetKey

        default:
            return false
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

private struct SourceComparableImageColumn<Value: Sendable>: Sendable, CustomDumpReflectable {
    var columnName: String
    var value: Value

    var customDumpMirror: Mirror {
        Mirror(
            self,
            children: [
                Mirror.Child(label: columnName, value: value)
            ]
        )
    }
}

private func sourceImageArraysAreEqual(
    columnName: String
) -> (SourceFieldChange) -> Bool {
    { fieldChange in
        guard fieldChange.columnName == columnName else { return false }
        let baselineImages = sourceComparableImages(fieldChange.baselineValue)
        let workingImages = sourceComparableImages(fieldChange.workingValue)
        if baselineImages == nil, workingImages == nil {
            return fieldChange.baselineValue == fieldChange.workingValue
        }
        return baselineImages == workingImages
    }
}

private func sourceImagesAreEqual(
    columnName: String
) -> (SourceFieldChange) -> Bool {
    { fieldChange in
        guard fieldChange.columnName == columnName else { return false }
        let baselineImage = sourceComparableImage(fieldChange.baselineValue)
        let workingImage = sourceComparableImage(fieldChange.workingValue)
        if baselineImage == nil, workingImage == nil {
            return fieldChange.baselineValue == fieldChange.workingValue
        }
        return baselineImage == workingImage
    }
}

private func sourceImageArrayFieldDiff(
    columnName: String
) -> (SourceRecordChange) -> String? {
    { change in
        guard let fieldChange = change.fieldChanges.first(where: { $0.columnName == columnName }) else {
            return nil
        }
        return diff(
            SourceComparableImageColumn(
                columnName: columnName,
                value: sourceComparableImages(fieldChange.baselineValue)
            ),
            SourceComparableImageColumn(
                columnName: columnName,
                value: sourceComparableImages(fieldChange.workingValue)
            )
        )
    }
}

private func sourceImageFieldDiff(
    columnName: String
) -> (SourceRecordChange) -> String? {
    { change in
        guard let fieldChange = change.fieldChanges.first(where: { $0.columnName == columnName }) else {
            return nil
        }
        return diff(
            SourceComparableImageColumn(
                columnName: columnName,
                value: sourceComparableImage(fieldChange.baselineValue)
            ),
            SourceComparableImageColumn(
                columnName: columnName,
                value: sourceComparableImage(fieldChange.workingValue)
            )
        )
    }
}

private func sourceComparableImages(
    _ value: DatabaseValue?
) -> [SourceComparableImageAsset]? {
    guard let images = decodeJSONValue([OME.ImageAsset].self, from: value) else {
        return nil
    }
    return sourceComparableImages(images)
}

private func sourceComparableImage(
    _ value: DatabaseValue?
) -> SourceComparableImageAsset? {
    decodeJSONValue(OME.ImageAsset.self, from: value)?
        .sourceComparable
}

private func decodeJSONValue<Value: Decodable>(
    _ type: Value.Type,
    from value: DatabaseValue?
) -> Value? {
    guard let value else { return nil }
    switch value.storage {
    case .null:
        return nil
    case let .string(json):
        return try? JSONDecoder().decode(Value.self, from: Data(json.utf8))
    default:
        return nil
    }
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
