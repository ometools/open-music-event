import CustomDump
import Foundation
import GRDB
import OpenMusicEventLexicon
import SourceEditing
import SQLiteData

public extension OME {
    static var sourceMetadataRecordTypes: [AnySourceEditableRecordType] {
        [
            Calendar.sourceRecordType,
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
            Event.sourceRecordType,
            Stage.sourceRecordType,
            Contributor.sourceRecordType,
            Schedule.sourceRecordType,
            Performance.sourceRecordType,
            Channel.sourceRecordType,
            Poster.sourceRecordType,
        ]
    }

    static var sourceDiffRecordTypes: [AnySourceEditableRecordType] {
        sourceMetadataRecordTypes + sourceRecordTypes
    }

    static var sourceTableDescriptors: [SourceTableDescriptor] {
        sourceRecordTypes.map(\.descriptor)
    }
}

extension OME.Calendar: SourceEditableTable {
    public static var sourceColumnPolicies: SourceColumnPolicies<Self> {
        [
            \.images: .imageArray
        ]
    }
}

extension OME.Event: SourceEditableTable {
    public static var sourceColumnPolicies: SourceColumnPolicies<Self> {
        [
            \.images: .imageArray
        ]
    }
}

extension OME.Stage: SourceEditableTable {
    public static var sourceColumnPolicies: SourceColumnPolicies<Self> {
        [
            \.images: .imageArray
        ]
    }
}

extension OME.Contributor: SourceEditableTable {
    public static var sourceColumnPolicies: SourceColumnPolicies<Self> {
        [
            \.images: .imageArray
        ]
    }
}

extension OME.Schedule: SourceEditableTable {}
extension OME.Performance: SourceEditableTable {}
extension OME.Channel: SourceEditableTable {}

extension OME.Poster: SourceEditableTable {
    public static var sourceColumnPolicies: SourceColumnPolicies<Self> {
        [
            \.image: .image
        ]
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

private extension SourceColumnPolicy {
    static var imageArray: Self {
        .comparing(
            decode: sourceComparableImages
        )
    }

    static var image: Self {
        .comparing(
            decode: sourceComparableImage
        )
    }
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
