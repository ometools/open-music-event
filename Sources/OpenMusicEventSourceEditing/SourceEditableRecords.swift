import CustomDump
import Foundation
import GRDB
import OpenMusicEventLexicon
import SourceEditing
import SQLiteData

public extension OME {
    static var sourceMetadataProjections: [OpenMusicEventSourceProjection] {
        [
            OpenMusicEventSourceProjection(
                tableType: Calendar.self,
                recordType: Calendar.sourceRecordType,
                fileFamily: .calendar
            ),
            OpenMusicEventSourceProjection(
                tableType: WorkspaceRelationshipRecord.self,
                recordType: WorkspaceRelationshipRecord.sourceRecordType,
                fileFamily: .collaborator
            ),
        ]
    }

    static var sourceEventProjections: [OpenMusicEventSourceProjection] {
        [
            OpenMusicEventSourceProjection(
                tableType: Event.self,
                recordType: Event.sourceRecordType,
                fileFamily: .event
            ),
            OpenMusicEventSourceProjection(
                tableType: Stage.self,
                recordType: Stage.sourceRecordType,
                fileFamily: .stage
            ),
            OpenMusicEventSourceProjection(
                tableType: Contributor.self,
                recordType: Contributor.sourceRecordType,
                fileFamily: .contributor
            ),
            OpenMusicEventSourceProjection(
                tableType: Schedule.self,
                recordType: Schedule.sourceRecordType,
                fileFamily: .schedule
            ),
            OpenMusicEventSourceProjection(
                tableType: ScheduleItem.self,
                recordType: ScheduleItem.sourceRecordType,
                fileFamily: .schedule
            ),
            OpenMusicEventSourceProjection(
                tableType: ScheduleItem.PerformanceDetails.self,
                recordType: ScheduleItem.PerformanceDetails.sourceRecordType,
                fileFamily: .schedule
            ),
            OpenMusicEventSourceProjection(
                tableType: ScheduleItem.Contributor.self,
                recordType: ScheduleItem.Contributor.sourceRecordType,
                fileFamily: .schedule
            ),
            OpenMusicEventSourceProjection(
                tableType: Channel.self,
                recordType: Channel.sourceRecordType,
                fileFamily: .channel
            ),
            OpenMusicEventSourceProjection(
                tableType: Poster.self,
                recordType: Poster.sourceRecordType,
                fileFamily: .poster
            ),
        ]
    }

    static var sourceProjections: [OpenMusicEventSourceProjection] {
        sourceMetadataProjections + sourceEventProjections
    }

    static var sourceMetadataRecordTypes: [AnySourceEditableRecordType] {
        sourceMetadataProjections.map(\.recordType)
    }

    static var sourceRecordTableTypes: [any SourceEditableTable.Type] {
        sourceEventProjections.map(\.tableType)
    }

    static var sourceRecordTypes: [AnySourceEditableRecordType] {
        sourceEventProjections.map(\.recordType)
    }

    static var sourceDiffRecordTypes: [AnySourceEditableRecordType] {
        sourceProjections.map(\.recordType)
    }

    static var sourceTableDescriptors: [SourceTableDescriptor] {
        sourceEventProjections.map(\.recordType.descriptor)
    }

    static var sourceProjectionsByTableID: [SourceTableDescriptor.ID: OpenMusicEventSourceProjection] {
        Dictionary(
            uniqueKeysWithValues: sourceProjections.map {
                ($0.recordType.descriptor.id, $0)
            }
        )
    }
}

public struct OpenMusicEventSourceProjection {
    public enum FileFamily: Equatable, Sendable {
        case calendar
        case collaborator
        case event
        case stage
        case contributor
        case schedule
        case channel
        case poster
    }

    public var tableType: any SourceEditableTable.Type
    public var recordType: AnySourceEditableRecordType
    public var fileFamily: FileFamily

    public init(
        tableType: any SourceEditableTable.Type,
        recordType: AnySourceEditableRecordType,
        fileFamily: FileFamily
    ) {
        self.tableType = tableType
        self.recordType = recordType
        self.fileFamily = fileFamily
    }
}

extension OME.Calendar: SourceEditableTable {
    public static var sourceColumnPolicies: SourceColumnPolicies<Self> {
        [
            \.images: .imageArray
        ]
    }
}

extension WorkspaceRelationshipRecord: SourceEditableTable {}

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
extension OME.ScheduleItem: SourceEditableTable {}
extension OME.ScheduleItem.PerformanceDetails: SourceEditableTable {}
extension OME.ScheduleItem.Contributor: SourceEditableTable {}
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

    var customDumpValue: Any {
        (
            assetKey: assetKey,
            source: source.stableDescription,
            role: role.rawValue,
            renderKind: renderKind.rawValue,
            appearance: appearance?.rawValue,
            materializationPolicy: materializationPolicy.rawValue,
            thumbhash: thumbhash,
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
