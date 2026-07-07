import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData

public struct SourceEditModePreparationClient: Sendable {
    public var prepare: @Sendable (SourceBaselineRecord.ID) async throws -> Void

    public init(
        prepare: @escaping @Sendable (SourceBaselineRecord.ID) async throws -> Void
    ) {
        self.prepare = prepare
    }
}

public enum SourceEditModePreparationError: Equatable, Error, Sendable {
    case sourceBaselineNotFound(SourceBaselineRecord.ID)
}

public extension SourceEditModePreparationClient {
    static var live: Self {
        Self { sourceBaselineID in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage

            let sourceBaseline = try await database.read { db in
                try SourceBaselineRecord
                    .where { $0.id.eq(sourceBaselineID) }
                    .fetchOne(db)
            }
            guard let sourceBaseline else {
                throw SourceEditModePreparationError.sourceBaselineNotFound(sourceBaselineID)
            }

            let sourceProvenance = sourceBaseline.sourceProvenance
            let storedRepositoryURL = try sourceRepositoryStorage
                .repositoryURL(sourceProvenance)

            try SourceReferenceDatabaseClient
                .ensureReferenceDatabaseIgnored(in: storedRepositoryURL)
        }
    }

    static var noop: Self {
        Self { _ in }
    }
}

public extension DependencyValues {
    var sourceEditModePreparation: SourceEditModePreparationClient {
        get { self[SourceEditModePreparationClientKey.self] }
        set { self[SourceEditModePreparationClientKey.self] = newValue }
    }
}

private enum SourceEditModePreparationClientKey: DependencyKey {
    static var liveValue: SourceEditModePreparationClient {
        .live
    }

    static var testValue: SourceEditModePreparationClient {
        .noop
    }
}
