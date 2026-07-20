import CustomDump
import Foundation
import GRDB
import OpenMusicEventLexicon
import SourceEditing

public extension OME {
    static var sourceMetadataRecordTypes: [AnySourceEditableRecordType] {
        [
            Calendar.sourceRecordType(
                semanticFields: [
                    .imageArray(columnName: "images")
                ]
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
                semanticFields: [
                    .imageArray(columnName: "images")
                ]
            ),
            Stage.sourceRecordType(
                semanticFields: [
                    .imageArray(columnName: "images")
                ]
            ),
            Contributor.sourceRecordType(
                semanticFields: [
                    .imageArray(columnName: "images")
                ]
            ),
            Schedule.sourceRecordType,
            Performance.sourceRecordType,
            Channel.sourceRecordType,
            Poster.sourceRecordType(
                semanticFields: [
                    .image(columnName: "image")
                ]
            ),
        ]
    }

    static var sourceDiffRecordTypes: [AnySourceEditableRecordType] {
        sourceMetadataRecordTypes + sourceRecordTypes
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
    static func sourceRecordType(
        semanticFields: [SourceSemanticFieldNormalizer]
    ) -> AnySourceEditableRecordType {
        let genericRecordType = Self.sourceRecordType
        let semanticFieldsByColumnName = Dictionary(
            uniqueKeysWithValues: semanticFields.map { ($0.columnName, $0) }
        )

        return AnySourceEditableRecordType(
            descriptor: sourceDescriptor,
            resolveRecordChange: { change, db, baselineSchemaName in
                var retainedFieldChanges: [SourceFieldChange] = []
                var genericFieldChanges: [SourceFieldChange] = []
                var semanticFieldDiffs: [String] = []

                for fieldChange in change.fieldChanges {
                    if let semanticField = semanticFieldsByColumnName[fieldChange.columnName] {
                        guard !semanticField.valuesAreEqual(fieldChange) else { continue }
                        retainedFieldChanges.append(fieldChange)
                        if let fieldDiff = semanticField.diff(fieldChange), !fieldDiff.isEmpty {
                            semanticFieldDiffs.append(fieldDiff)
                        }
                    } else {
                        retainedFieldChanges.append(fieldChange)
                        genericFieldChanges.append(fieldChange)
                    }
                }

                guard !retainedFieldChanges.isEmpty else {
                    return nil
                }

                var genericRecordDiff: String?
                if !genericFieldChanges.isEmpty {
                    var genericChange = change
                    genericChange.fieldChanges = genericFieldChanges
                    let resolvedGenericChange = try genericRecordType
                        .resolveRecordChange(genericChange, db, baselineSchemaName)
                    genericRecordDiff = resolvedGenericChange?.recordDiff
                }

                var resolvedChange = change
                resolvedChange.fieldChanges = retainedFieldChanges

                let recordDiffs = ([genericRecordDiff].compactMap(\.self) + semanticFieldDiffs)
                    .filter { !$0.isEmpty }
                if !recordDiffs.isEmpty {
                    resolvedChange.recordDiff = recordDiffs.joined(separator: "\n")
                } else if !genericFieldChanges.isEmpty {
                    resolvedChange.recordDiff = genericRecordDiff
                } else {
                    resolvedChange.recordDiff = nil
                }
                return resolvedChange
            },
            recordComparison: { change, db, baselineSchemaName in
                try genericRecordType.recordComparison(change, db, baselineSchemaName)
            }
        )
    }
}

private struct SourceSemanticFieldNormalizer {
    var columnName: String
    var valuesAreEqual: (SourceFieldChange) -> Bool
    var diff: (SourceFieldChange) -> String?

    static func imageArray(columnName: String) -> Self {
        Self(
            columnName: columnName,
            valuesAreEqual: sourceImageArraysAreEqual(columnName: columnName),
            diff: sourceImageArrayFieldDiff(columnName: columnName)
        )
    }

    static func image(columnName: String) -> Self {
        Self(
            columnName: columnName,
            valuesAreEqual: sourceImagesAreEqual(columnName: columnName),
            diff: sourceImageFieldDiff(columnName: columnName)
        )
    }
}

private struct SourceComparableImageAsset: CustomDumpRepresentable, Equatable, Sendable {
    var assetKey: String?
    var source: SourceComparableImageSource
    var role: OME.ImageAsset.Role
    var renderKind: OME.ImageAsset.RenderKind
    var appearance: OME.ImageAsset.Appearance?
    var materializationPolicy: OME.ImageAsset.MaterializationPolicy
    var thumbhash: String?
    var dimensions: OME.ImageAsset.Dimensions?
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
        self.dimensions = image.dimensions
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
            && lhs.dimensions == rhs.dimensions
            && lhs.focalPoint == rhs.focalPoint
    }

    var customDumpValue: Any {
        (
            assetKey: assetKey,
            source: source.stableDescription,
            role: role.rawValue,
            renderKind: renderKind.rawValue,
            appearance: appearance?.rawValue,
            materializationPolicy: materializationPolicy.rawValue,
            thumbhash: thumbhash,
            dimensions: dimensions.map { (width: $0.width, height: $0.height) },
            focalPoint: focalPoint.map { (x: $0.x, y: $0.y) }
        )
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

    var stableDescription: String {
        switch self {
        case let .fileIdentity(identity):
            return "fileIdentity(\(identity))"

        case let .source(.blob(blob)):
            return "blob(\(blob))"

        case let .source(.url(url)):
            return "url(\(url.absoluteString))"
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

private struct SourceComparableImageColumn<Value: Sendable>: CustomDumpRepresentable, Sendable {
    var columnName: String
    var value: Value

    var customDumpValue: Any {
        (
            columnName: columnName,
            value: value
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
) -> (SourceFieldChange) -> String? {
    { fieldChange in
        guard fieldChange.columnName == columnName else { return nil }
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
) -> (SourceFieldChange) -> String? {
    { fieldChange in
        guard fieldChange.columnName == columnName else { return nil }
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
