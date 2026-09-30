import ATProto
import CasePaths
import Foundation
import ATProtoTypes
import Tagged

public extension OpenMusicEvent {
    enum WorkspaceProposal {}
}

public extension OpenMusicEvent.WorkspaceProposal {
    enum StatusTag {}
    typealias Status = Tagged<StatusTag, String>

    struct ListItem: Codable, Equatable, Identifiable, Sendable {
        public init(
            uri: ATProto.URI,
            canonicalSource: ATProto.URI,
            title: String,
            authorDID: DID,
            status: Status,
            targetBranch: String,
            createdAt: Date,
            updatedAt: Date,
            pullNumber: Int64? = nil,
            pageURL: URL? = nil,
            renderStatus: RenderStatus
        ) {
            self.uri = uri
            self.canonicalSource = canonicalSource
            self.title = title
            self.authorDID = authorDID
            self.status = status
            self.targetBranch = targetBranch
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.pullNumber = pullNumber
            self.pageURL = pageURL
            self.renderStatus = renderStatus
        }

        public var uri: ATProto.URI
        public var canonicalSource: ATProto.URI
        public var title: String
        public var authorDID: DID
        public var status: Status
        public var targetBranch: String
        public var createdAt: Date
        public var updatedAt: Date
        public var pullNumber: Int64?
        public var pageURL: URL?
        public var renderStatus: RenderStatus

        public var id: ATProto.URI { uri }
    }

    struct Detail: Codable, Equatable, Identifiable, Sendable {
        public init(
            uri: ATProto.URI,
            canonicalSource: ATProto.URI? = nil,
            title: String? = nil,
            body: String? = nil,
            authorDID: DID,
            status: Status,
            targetRepositoryDID: DID? = nil,
            targetBranch: String? = nil,
            source: Source? = nil,
            createdAt: Date? = nil,
            updatedAt: Date? = nil,
            pullNumber: Int64? = nil,
            roundNumber: Int? = nil,
            pageURL: URL? = nil,
            patchURL: URL? = nil,
            recordCID: ATProto.CID? = nil,
            recordAvailability: RecordAvailability,
            statusRecordURI: ATProto.URI? = nil,
            renderStatus: RenderStatus,
            presentation: Presentation? = nil
        ) {
            self.uri = uri
            self.canonicalSource = canonicalSource
            self.title = title
            self.body = body
            self.authorDID = authorDID
            self.status = status
            self.targetRepositoryDID = targetRepositoryDID
            self.targetBranch = targetBranch
            self.source = source
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.pullNumber = pullNumber
            self.roundNumber = roundNumber
            self.pageURL = pageURL
            self.patchURL = patchURL
            self.recordCID = recordCID
            self.recordAvailability = recordAvailability
            self.statusRecordURI = statusRecordURI
            self.renderStatus = renderStatus
            self.presentation = presentation
        }

        public var uri: ATProto.URI
        public var canonicalSource: ATProto.URI?
        public var title: String?
        public var body: String?
        public var authorDID: DID
        public var status: Status
        public var targetRepositoryDID: DID?
        public var targetBranch: String?
        public var source: Source?
        public var createdAt: Date?
        public var updatedAt: Date?
        public var pullNumber: Int64?
        public var roundNumber: Int?
        public var pageURL: URL?
        public var patchURL: URL?
        public var recordCID: ATProto.CID?
        public var recordAvailability: RecordAvailability
        public var statusRecordURI: ATProto.URI?
        public var renderStatus: RenderStatus
        public var presentation: Presentation?

        public var id: ATProto.URI { uri }
    }

    struct Page: Codable, Equatable, Sendable {
        public init(
            proposals: [ListItem],
            cursor: String? = nil
        ) {
            self.proposals = proposals
            self.cursor = cursor
        }

        public var proposals: [ListItem]
        public var cursor: String?
    }

    struct Source: Codable, Equatable, Sendable {
        public init(
            repositoryDID: DID? = nil,
            branch: String,
            revision: String? = nil
        ) {
            self.repositoryDID = repositoryDID
            self.branch = branch
            self.revision = revision
        }

        public var repositoryDID: DID?
        public var branch: String
        public var revision: String?
    }

    enum RecordAvailability: String, Codable, Equatable, Sendable {
        case awaitingRecord = "app.openmusicevent.workspace.defs#awaitingRecord"
        case present = "app.openmusicevent.workspace.defs#present"
        case deleted = "app.openmusicevent.workspace.defs#deleted"
    }

    enum RenderStatus: String, Codable, Equatable, Sendable {
        case awaitingInput = "app.openmusicevent.workspace.defs#awaitingInput"
        case pending = "app.openmusicevent.workspace.defs#pending"
        case ready = "app.openmusicevent.workspace.defs#ready"
    }

    struct GetProposal: XRPC.Query, Sendable {
        public static let nsid = ATProto.NSID("app.openmusicevent.workspace.getProposal")

        public typealias Input = Never
        public typealias Output = Detail

        public init(uri: ATProto.URI) {
            self.parameters = Parameters(uri: uri)
        }

        public var parameters: Parameters

        public struct Parameters: Codable, Equatable, Sendable {
            public init(uri: ATProto.URI) {
                self.uri = uri
            }

            public var uri: ATProto.URI
        }
    }

    struct GetProposals: XRPC.Query, Sendable {
        public static let nsid = ATProto.NSID("app.openmusicevent.workspace.getProposals")

        public typealias Input = Never
        public typealias Output = Page

        public init(
            source: ATProto.URI,
            targetBranch: String,
            includeRetained: Bool = false,
            cursor: String? = nil,
            limit: Int = 100
        ) {
            self.parameters = Parameters(
                source: source,
                targetBranch: targetBranch,
                includeRetained: includeRetained,
                cursor: cursor,
                limit: limit
            )
        }

        public var parameters: Parameters

        public struct Parameters: Codable, Equatable, Sendable {
            public init(
                source: ATProto.URI,
                targetBranch: String,
                includeRetained: Bool = false,
                cursor: String? = nil,
                limit: Int = 100
            ) {
                self.source = source
                self.targetBranch = targetBranch
                self.includeRetained = includeRetained
                self.cursor = cursor
                self.limit = limit
            }

            public var source: ATProto.URI
            public var targetBranch: String
            public var includeRetained: Bool
            public var cursor: String?
            public var limit: Int

            enum CodingKeys: String, CodingKey {
                case source
                case targetBranch
                case includeRetained
                case cursor
                case limit
            }

            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.source = try container.decode(ATProto.URI.self, forKey: .source)
                self.targetBranch = try container.decode(String.self, forKey: .targetBranch)
                self.includeRetained = try container.decodeIfPresent(
                    Bool.self,
                    forKey: .includeRetained
                ) ?? false
                self.cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
                self.limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 100

                guard (1...100).contains(limit) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .limit,
                        in: container,
                        debugDescription: "XRPC limit must be between 1 and 100."
                    )
                }
            }
        }
    }

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
            .type(.init(nsid: OpenMusicEvent.Calendar.nsid), \.calendar),
            .type(.init(nsid: OpenMusicEvent.Relationship.nsid), \.relationship),
            .type(.init(nsid: OpenMusicEvent.Event.nsid), \.event),
            .type(.init(nsid: OpenMusicEvent.Stage.nsid), \.stage),
            .type(.init(nsid: OpenMusicEvent.Contributor.nsid), \.contributor),
            .type(.init(nsid: OpenMusicEvent.Schedule.nsid), \.schedule),
            .type("app.openmusicevent.workspace.proposal#scheduleItem", \.scheduleItem),
            .type(
                "app.openmusicevent.workspace.proposal#scheduleItemPerformanceDetails",
                \.scheduleItemPerformanceDetails
            ),
            .type(
                "app.openmusicevent.workspace.proposal#scheduleItemContributor",
                \.scheduleItemContributor
            ),
            .type(.init(nsid: OpenMusicEvent.Channel.nsid), \.channel),
            .type(
                "app.openmusicevent.workspace.proposal#communicationPost",
                \.communicationPost
            ),
            .type(.init(nsid: OpenMusicEvent.Poster.nsid), \.poster),
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

public extension Tagged
where Tag == OME.WorkspaceProposal.StatusTag, RawValue == String {
    static let open = Self(rawValue: "sh.tangled.repo.pull.status.open")
    static let closed = Self(rawValue: "sh.tangled.repo.pull.status.closed")
    static let merged = Self(rawValue: "sh.tangled.repo.pull.status.merged")
}
