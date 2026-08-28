import CasePaths
import Foundation
import Lexicon

public extension OpenMusicEvent {
    enum WorkspaceProposal {}
}

public extension OpenMusicEvent.WorkspaceProposal {
    @CasePathable
    enum SourceRecord: OpenUnion {
        case calendar(OpenMusicEvent.Calendar)
        case relationship(OpenMusicEvent.Relationship)
        case event(OpenMusicEvent.Event)
        case stage(OpenMusicEvent.Stage)
        case contributor(OpenMusicEvent.Contributor)
        case schedule(OpenMusicEvent.Schedule)
        case scheduleItem(OpenMusicEvent.ScheduleItem)
        case scheduleItemPerformanceDetails(OpenMusicEvent.ScheduleItem.PerformanceDetails)
        case scheduleItemContributor(OpenMusicEvent.ScheduleItem.Contributor)
        case channel(OpenMusicEvent.Channel)
        case communicationPost(CommsPost)
        case poster(OpenMusicEvent.Poster)

        public static let unionTypes: OpenUnionTypes<Self> = [
            .type(OpenMusicEvent.Calendar.nsid.rawValue, \.calendar),
            .type(OpenMusicEvent.Relationship.nsid.rawValue, \.relationship),
            .type(OpenMusicEvent.Event.nsid.rawValue, \.event),
            .type(OpenMusicEvent.Stage.nsid.rawValue, \.stage),
            .type(OpenMusicEvent.Contributor.nsid.rawValue, \.contributor),
            .type(OpenMusicEvent.Schedule.nsid.rawValue, \.schedule),
            .type("app.openmusicevent.workspace.proposal#scheduleItem", \.scheduleItem),
            .type(
                "app.openmusicevent.workspace.proposal#scheduleItemPerformanceDetails",
                \.scheduleItemPerformanceDetails
            ),
            .type(
                "app.openmusicevent.workspace.proposal#scheduleItemContributor",
                \.scheduleItemContributor
            ),
            .type(OpenMusicEvent.Channel.nsid.rawValue, \.channel),
            .type(
                "app.openmusicevent.workspace.proposal#communicationPost",
                \.communicationPost
            ),
            .type(OpenMusicEvent.Poster.nsid.rawValue, \.poster),
        ]
    }

    struct Presentation: Codable, Equatable, Sendable {
        public static let currentFormatVersion = 1
        public static let empty = Self(groups: [])

        public var formatVersion: Int
        public var groups: [Group]

        public init(
            formatVersion: Int = Self.currentFormatVersion,
            groups: [Group]
        ) {
            self.formatVersion = formatVersion
            self.groups = groups
        }

        public var totalCount: Int {
            groups.reduce(0) { $0 + $1.records.count }
        }

        public struct Group: Codable, Equatable, Identifiable, Sendable {
            public var id: String
            public var displayName: String
            public var records: [Record]

            public init(
                id: String,
                displayName: String,
                records: [Record]
            ) {
                self.id = id
                self.displayName = displayName
                self.records = records
            }
        }

        public struct Record: Codable, Equatable, Identifiable, Sendable {
            public var id: String
            public var title: String?
            public var transition: Transition
            public var changedFields: [String]
            public var sourceFiles: [String]

            public init(
                id: String,
                title: String? = nil,
                transition: Transition,
                changedFields: [String],
                sourceFiles: [String] = []
            ) {
                self.id = id
                self.title = title
                self.transition = transition
                self.changedFields = changedFields
                self.sourceFiles = sourceFiles
            }
        }

        public struct Transition: Codable, Equatable, Sendable {
            public enum Kind: String, Codable, Equatable, Sendable {
                case added
                case modified
                case deleted
            }

            public var kind: Kind
            public var before: Open<SourceRecord>?
            public var after: Open<SourceRecord>?

            public init(
                kind: Kind,
                before: Open<SourceRecord>? = nil,
                after: Open<SourceRecord>? = nil
            ) {
                self.kind = kind
                self.before = before
                self.after = after
            }
        }
    }
}
