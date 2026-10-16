import ATProtoTypes
import CasePaths
import CustomDump
import Foundation
import GRDB
import OpenMusicEventLexicon
import SourceEditing
import SQLiteData

@CasePathable
enum SourcePresentationRecord: OpenUnion {
    case calendar(OME.Calendar)
    case relationship(OME.Relationship)
    case event(OME.Event)
    case stage(OME.Stage)
    case contributor(OME.Contributor)
    case schedule(OME.Schedule)
    case scheduleItem(OME.ScheduleItem)
    case scheduleItemPerformanceDetails(OME.ScheduleItem.PerformanceDetails)
    case scheduleItemContributor(OME.ScheduleItem.Contributor)
    case channel(OME.Channel)
    case communicationPost(CommsPost)
    case poster(OME.Poster)

    static let unionTypes: OpenUnionTypes<Self> = [
        .type(.init(nsid: OME.Calendar.nsid), \.calendar),
        .type(.init(nsid: OME.Relationship.nsid), \.relationship),
        .type(.init(nsid: OME.Event.nsid), \.event),
        .type(.init(nsid: OME.Stage.nsid), \.stage),
        .type(.init(nsid: OME.Contributor.nsid), \.contributor),
        .type(.init(nsid: OME.Schedule.nsid), \.schedule),
        .type("app.openmusicevent.workspace.proposal#scheduleItem", \.scheduleItem),
        .type(
            "app.openmusicevent.workspace.proposal#scheduleItemPerformanceDetails",
            \.scheduleItemPerformanceDetails
        ),
        .type(
            "app.openmusicevent.workspace.proposal#scheduleItemContributor",
            \.scheduleItemContributor
        ),
        .type(.init(nsid: OME.Channel.nsid), \.channel),
        .type(
            "app.openmusicevent.workspace.proposal#communicationPost",
            \.communicationPost
        ),
        .type(.init(nsid: OME.Poster.nsid), \.poster),
    ]
}

public extension OME {
    static var sourceMetadataProjections: [OpenMusicEventSourceProjection] {
        [
            OpenMusicEventSourceProjection(
                tableType: Calendar.self,
                recordType: Calendar.sourceRecordType,
                fileFamily: .calendar,
                title: { $0.name },
                sourceRecord: { .calendar($0) }
            ),
            OpenMusicEventSourceProjection(
                tableType: WorkspaceRelationshipRecord.self,
                recordType: WorkspaceRelationshipRecord.sourceRecordType,
                fileFamily: .collaborator,
                sourceRecord: { .relationship($0.relationship) }
            ),
        ]
    }

    static var sourceEventProjections: [OpenMusicEventSourceProjection] {
        [
            OpenMusicEventSourceProjection(
                tableType: Event.self,
                recordType: Event.sourceRecordType,
                fileFamily: .event,
                title: { $0.name },
                sourceRecord: { .event($0) }
            ),
            OpenMusicEventSourceProjection(
                tableType: Stage.self,
                recordType: Stage.sourceRecordType,
                fileFamily: .stage,
                title: { $0.name },
                sourceRecord: { .stage($0) }
            ),
            OpenMusicEventSourceProjection(
                tableType: Contributor.self,
                recordType: Contributor.sourceRecordType,
                fileFamily: .contributor,
                title: { $0.name },
                sourceRecord: { .contributor($0) }
            ),
            OpenMusicEventSourceProjection(
                tableType: Schedule.self,
                recordType: Schedule.sourceRecordType,
                fileFamily: .schedule,
                title: { $0.customTitle },
                sourceRecord: { .schedule($0) }
            ),
            OpenMusicEventSourceProjection(
                tableType: ScheduleItem.self,
                recordType: ScheduleItem.sourceRecordType,
                fileFamily: .schedule,
                title: { $0.title },
                sourceRecord: { .scheduleItem($0) }
            ),
            OpenMusicEventSourceProjection(
                tableType: ScheduleItem.PerformanceDetails.self,
                recordType: ScheduleItem.PerformanceDetails.sourceRecordType,
                fileFamily: .schedule,
                sourceRecord: { .scheduleItemPerformanceDetails($0) }
            ),
            OpenMusicEventSourceProjection(
                tableType: ScheduleItem.Contributor.self,
                recordType: ScheduleItem.Contributor.sourceRecordType,
                fileFamily: .schedule,
                title: { $0.anonymousName },
                sourceRecord: { .scheduleItemContributor($0) }
            ),
            OpenMusicEventSourceProjection(
                tableType: Channel.self,
                recordType: Channel.sourceRecordType,
                fileFamily: .channel,
                title: { $0.name },
                sourceRecord: { .channel($0) }
            ),
            OpenMusicEventSourceProjection(
                tableType: CommsPost.self,
                recordType: CommsPost.sourceRecordType,
                fileFamily: .communicationPost,
                title: { $0.title },
                sourceRecord: { .communicationPost($0) }
            ),
            OpenMusicEventSourceProjection(
                tableType: Poster.self,
                recordType: Poster.sourceRecordType,
                fileFamily: .poster,
                title: { $0.title },
                sourceRecord: { .poster($0) }
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
    struct PresentationRecordComparison: Sendable {
        var title: String?
        var before: SourcePresentationRecord?
        var after: SourcePresentationRecord?
    }

    public enum FileFamily: Equatable, Sendable {
        case calendar
        case collaborator
        case event
        case stage
        case contributor
        case schedule
        case channel
        case communicationPost
        case poster
    }

    public var tableType: any SourceEditableTable.Type
    public var recordType: AnySourceEditableRecordType
    public var fileFamily: FileFamily
    private var presentationRecordComparison: @Sendable (
        AnySourceRecordComparison
    ) -> PresentationRecordComparison?

    init<Table: SourceEditableTable>(
        tableType: Table.Type,
        recordType: AnySourceEditableRecordType,
        fileFamily: FileFamily,
        title: @escaping @Sendable (Table.QueryOutput) -> String? = { _ in nil },
        sourceRecord: @escaping @Sendable (
            Table.QueryOutput
        ) -> SourcePresentationRecord
    ) where Table.QueryOutput: Sendable {
        self.tableType = tableType
        self.recordType = recordType
        self.fileFamily = fileFamily
        self.presentationRecordComparison = { comparison in
            guard let comparison = comparison.as(Table.QueryOutput.self) else {
                return nil
            }
            return PresentationRecordComparison(
                title: comparison.right.flatMap(title)
                    ?? comparison.left.flatMap(title),
                before: comparison.left.map(sourceRecord),
                after: comparison.right.map(sourceRecord)
            )
        }
    }

    func presentation(
        for comparison: AnySourceRecordComparison
    ) -> PresentationRecordComparison? {
        presentationRecordComparison(comparison)
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
            \.locations: .json([OME.Event.Location].self),
            \.images: .imageArray,
            \.contactNumbers: .json([OME.Event.ContactNumber].self)
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
            \.images: .imageArray,
            \.links: .json([ExternalPlatform.Link].self)
        ]
    }
}

extension OME.Schedule: SourceEditableTable {}
extension OME.ScheduleItem: SourceEditableTable {}
extension OME.ScheduleItem.PerformanceDetails: SourceEditableTable {}
extension OME.ScheduleItem.Contributor: SourceEditableTable {}
extension OME.Channel: SourceEditableTable {}

extension CommsPost: SourceEditableTable {
    public static var sourceColumnPolicies: SourceColumnPolicies<Self> {
        [
            \.sortIndex: .ignore
        ]
    }
}

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
    static func json<Value>(_ type: Value.Type) -> Self
    where Value: Decodable & Equatable & Sendable {
        .comparing { value in
            decodeJSONValue(type, from: value)
        }
    }

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
