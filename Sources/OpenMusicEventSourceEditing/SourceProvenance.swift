import ATProto
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData

public struct SourceWorkspace: Codable, Equatable, Hashable, Identifiable, Sendable {
    public struct ID: Codable, Hashable, RawRepresentable, Sendable, SQLiteType {
        public static var typeAffinity: SQLiteTypeAffinity { .text }

        public var rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidID(ID)
    }

    public var defaultBranch: String
    public var organizerID: OME.Organizer.ID
    public var repository: String

    public init(
        organizerID: OME.Organizer.ID,
        repository: String,
        branch: String
    ) {
        self.organizerID = organizerID
        self.repository = repository
        self.defaultBranch = Self.normalizedBranch(branch)
    }

    public init(
        organizerID: OME.Organizer.ID,
        sourceRecord: OME.SourceRecord
    ) {
        self.init(
            organizerID: organizerID,
            repository: sourceRecord.reference,
            branch: "main"
        )
    }

    public init(id: ID) throws {
        let components = id.rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4,
              components[0] == "v1",
              let organizer = Self.decode(String(components[1])),
              let organizerID = OME.Organizer.ID(organizer),
              let repository = Self.decode(String(components[2])),
              let branch = Self.decode(String(components[3]))
        else {
            throw Error.invalidID(id)
        }
        self.init(
            organizerID: organizerID,
            repository: repository,
            branch: branch
        )
    }

    public var id: ID {
        ID(
            rawValue: [
                "v1",
                Self.encode(organizerID.description),
                Self.encode(repository),
                Self.encode(defaultBranch),
            ]
            .joined(separator: ".")
        )
    }

    public var sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance {
        OME.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: repository,
            ref: defaultBranch
        )
    }

    /// Whether two workspaces belong to the same organizer-owned repository.
    ///
    /// Published attendee content may advance independently of the editable branch, but it must
    /// never cross either the organizer or repository boundary.
    public func referencesSameRepository(as other: Self) -> Bool {
        organizerID == other.organizerID && repository == other.repository
    }

    public static func normalizedBranch(_ branch: String?) -> String {
        let branch = branch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if branch.isEmpty || branch == "HEAD" {
            return "main"
        }
        if branch.hasPrefix("refs/heads/") {
            return String(branch.dropFirst("refs/heads/".count))
        }
        return branch
    }

    static func encode(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ value: String) -> String? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        return Data(base64Encoded: base64).flatMap { String(data: $0, encoding: .utf8) }
    }
}

@Table("eventSourceProvenances")
public struct EventSourceProvenanceRecord: Equatable, Sendable, Identifiable {
    public var id: OME.Event.ID
    public var sourceKind: OME.SourceDatabaseInsertion.SourceKind
    public var sourceReference: String
    public var ref: String?
    public var eventIDOrigin: OME.SourceDatabaseInsertion.EventIDOrigin
    public var sourceEventDirectory: String

    public init(
        id: OME.Event.ID,
        sourceKind: OME.SourceDatabaseInsertion.SourceKind,
        sourceReference: String,
        ref: String?,
        eventIDOrigin: OME.SourceDatabaseInsertion.EventIDOrigin,
        sourceEventDirectory: String
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.sourceReference = sourceReference
        self.ref = ref
        self.eventIDOrigin = eventIDOrigin
        self.sourceEventDirectory = sourceEventDirectory
    }

    public init(_ provenance: OME.SourceDatabaseInsertion.EventSourceProvenance) {
        self.init(
            id: provenance.eventID,
            sourceKind: provenance.source.kind,
            sourceReference: provenance.source.reference,
            ref: provenance.source.ref,
            eventIDOrigin: provenance.eventIDOrigin,
            sourceEventDirectory: provenance.sourceEventDirectory
        )
    }

    public var sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance {
        OME.SourceDatabaseInsertion.SourceProvenance(
            kind: sourceKind,
            reference: sourceReference,
            ref: ref
        )
    }

    public var workspace: SourceWorkspace? {
        guard sourceKind == .tangled else { return nil }
        return SourceWorkspace(
            organizerID: id.organizerID,
            repository: sourceReference,
            branch: "main"
        )
    }
}

@Table("sourceWorkspaceRelationships")
public struct WorkspaceRelationshipRecord: Codable, Equatable, Sendable, Identifiable {
    @Selection public struct ID: Codable, Hashable, Sendable {
        public init(
            workspaceID: SourceWorkspace.ID,
            actorID: DID
        ) {
            self.workspaceID = workspaceID
            self.actorID = actorID
        }

        public var workspaceID: SourceWorkspace.ID
        public var actorID: DID
    }

    public init(
        id: ID,
        recordKey: String,
        relationship: OME.Relationship
    ) {
        self.id = id
        self.recordKey = recordKey
        self.relationship = relationship
    }

    public var id: ID
    public var recordKey: String
    @Column(as: OME.Relationship.JSONRepresentation.self)
    public var relationship: OME.Relationship

    public static func recordKey(for actorID: DID) -> String {
        Data(actorID.description.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// The exact Git commit represented by a workspace-owned reference database.
@Table("sourceWorkspaceReferences")
public struct SourceWorkspaceReferenceRecord: Equatable, Sendable, Identifiable {
    public var id: SourceWorkspace.ID
    public var revision: String

    public init(id: SourceWorkspace.ID, revision: String) {
        self.id = id
        self.revision = revision
    }
}

/// The Git commit currently installed as the writable database's base for this source.
@Table("sourceWorkspaceInstallations")
public struct SourceWorkspaceInstallationRecord: Equatable, Sendable, Identifiable {
    public var id: SourceWorkspace.ID
    public var revision: String

    public init(id: SourceWorkspace.ID, revision: String) {
        self.id = id
        self.revision = revision
    }
}

/// The branch and exact Git commit the user last selected for authoring.
@Table("sourceWorkspaceSelections")
public struct SourceWorkspaceSelectionRecord: Equatable, Sendable, Identifiable {
    public var id: SourceWorkspace.ID
    public var branch: String
    public var revision: String

    public init(id: SourceWorkspace.ID, branch: String, revision: String) {
        self.id = id
        self.branch = SourceWorkspace.normalizedBranch(branch)
        self.revision = revision
    }
}

extension OME.SourceDatabaseInsertion.EventIDOrigin: SQLiteType {
    public static var typeAffinity: SQLiteTypeAffinity { .text }
}

extension OME.SourceDatabaseInsertion.SourceKind: SQLiteType {
    public static var typeAffinity: SQLiteTypeAffinity { .text }
}
