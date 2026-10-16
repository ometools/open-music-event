import ATProtoTypes
import Foundation
import OpenMusicEventLexicon
import SourceEditing

public enum SourceChangePresentationRenderingError: Error, Equatable, Sendable {
    case unavailable(SourceChangeSummary.UnavailableReason)
    case missingRecordComparison(recordID: String)
    case missingProjection(tableID: String)
    case inconsistentTransition(recordID: String, kind: SourceRecordChangeKind)
}

public struct SourceChangePresentationRenderer: Sendable {
    public init() {}

    public func render(
        _ summary: SourceChangeSummary,
        sourceFiles: [SourceFileAttribution] = []
    ) throws -> OME.WorkspaceProposal.Presentation {
        if case let .unavailable(reason) = summary.availability {
            throw SourceChangePresentationRenderingError.unavailable(reason)
        }

        let records = summary.groups.flatMap(\.records)
        let recordIDsByChangeID = Dictionary(
            uniqueKeysWithValues: records.map { ($0.id, sourceRecordID(for: $0)) }
        )
        let sourceFilesByRecordID = sourceFiles.reduce(
            into: [String: [String]]()
        ) { sourceFilesByRecordID, sourceFile in
            for changeID in sourceFile.recordChangeIDs {
                guard let recordID = recordIDsByChangeID[changeID] else { continue }
                sourceFilesByRecordID[recordID, default: []].append(sourceFile.filePath)
            }
        }

        var groups: [OME.WorkspaceProposal.Presentation.Group] = []
        groups.reserveCapacity(summary.groups.count)
        for group in summary.groups {
            var records: [OME.WorkspaceProposal.Presentation.Record] = []
            records.reserveCapacity(group.records.count)
            for change in group.records {
                let recordID = sourceRecordID(for: change)
                guard let comparison = summary.recordComparisons[change] else {
                    throw SourceChangePresentationRenderingError
                        .missingRecordComparison(recordID: recordID)
                }
                guard let projection = OME.sourceProjectionsByTableID[change.tableID] else {
                    throw SourceChangePresentationRenderingError
                        .missingProjection(tableID: change.tableID)
                }
                guard let presentation = projection.presentation(for: comparison) else {
                    throw SourceChangePresentationRenderingError
                        .missingRecordComparison(recordID: recordID)
                }

                let transition = try transition(
                    for: change,
                    presentation: presentation,
                    recordID: recordID
                )
                let changedFields = change.fieldChanges
                    .map(\.columnName)
                    .sorted()
                let attributedSourceFiles = sourceFilesByRecordID[
                    recordID,
                    default: []
                ]
                .sorted()
                records.append(
                    OME.WorkspaceProposal.Presentation.Record(
                        id: recordID,
                        title: presentation.title,
                        transition: transition,
                        changedFields: changedFields,
                        sourceFiles: attributedSourceFiles
                    )
                )
            }
            guard !records.isEmpty else { continue }
            records.sort { $0.id < $1.id }

            groups.append(
                OME.WorkspaceProposal.Presentation.Group(
                    id: group.id,
                    displayName: group.displayName,
                    records: records
                )
            )
        }
        groups.sort { $0.id < $1.id }

        return OME.WorkspaceProposal.Presentation(groups: groups)
    }
}

private func transition(
    for change: SourceRecordChange,
    presentation: OpenMusicEventSourceProjection.PresentationRecordComparison,
    recordID: String
) throws -> OME.WorkspaceProposal.Presentation.Transition {
    switch (change.kind, presentation.before, presentation.after) {
    case let (.added, nil, .some(after)):
        return .init(kind: .added, after: try wireRecord(after))

    case let (.modified, .some(before), .some(after)):
        return .init(
            kind: .modified,
            before: try wireRecord(before),
            after: try wireRecord(after)
        )

    case let (.deleted, .some(before), nil):
        return .init(kind: .deleted, before: try wireRecord(before))

    default:
        throw SourceChangePresentationRenderingError.inconsistentTransition(
            recordID: recordID,
            kind: change.kind
        )
    }
}

private func wireRecord(_ record: SourcePresentationRecord) throws -> Lexicon.JSONValue {
    try JSONDecoder().decode(
        Lexicon.JSONValue.self,
        from: JSONEncoder().encode(Open<SourcePresentationRecord>.known(record))
    )
}

private func sourceRecordID(
    for change: SourceRecordChange
) -> String {
    let primaryKey = change.primaryKeyValues
        .sorted { $0.columnName < $1.columnName }
        .map { "\($0.columnName)=\($0.value)" }
        .joined(separator: ",")
    return "\(change.tableID):\(primaryKey)"
}
