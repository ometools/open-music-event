import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SwiftUI

public struct TangledSourceImportClient: Sendable {
    public var importSource: @Sendable (OpenMusicEventSourceValidationRequest) async throws -> OpenMusicEventSourceValidationResult

    public init(
        importSource: @escaping @Sendable (OpenMusicEventSourceValidationRequest) async throws -> OpenMusicEventSourceValidationResult
    ) {
        self.importSource = importSource
    }
}

public struct SourceImportCompleted: FeatureEventKey {
    public init() {}
    public typealias Value = ImportedSource
}

public struct ImportedSource: Equatable, Sendable {
    public var organizerID: OMERecord.Organizer.ID
    public var sourceBaselineID: SourceBaselineRecord.ID?

    public init(
        organizerID: OMERecord.Organizer.ID,
        sourceBaselineID: SourceBaselineRecord.ID?
    ) {
        self.organizerID = organizerID
        self.sourceBaselineID = sourceBaselineID
    }
}

public extension TangledSourceImportClient {
    static var live: Self {
        Self { request in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage
            var request = request
            if request.outputURL == nil,
               let sourceProvenance = try request.tangledSourceProvenance() {
                @Dependency(\.uuid) var uuid
                let temporaryOutputURL = SourceRepositoryStorageClient
                    .temporaryDownloadURL(uuid: uuid())
                request.outputURL = temporaryOutputURL
                do {
                    var result = try await OpenMusicEventSourceValidator(request)
                        .validate()
                    result.repositoryURL = try sourceRepositoryStorage.store(
                        temporaryOutputURL,
                        sourceProvenance
                    )
                    try await result.insertion.migrateAndInsert(into: database)
                    return result
                } catch {
                    try? FileManager.default.removeItem(at: temporaryOutputURL)
                    throw error
                }
            }

            return try await OpenMusicEventSourceValidator(request)
                .validateAndInsertIntoDefaultDatabase()
        }
    }
}

private enum TangledSourceImportClientKey: DependencyKey {
    static var liveValue: TangledSourceImportClient {
        .live
    }

    static var testValue: TangledSourceImportClient {
        TangledSourceImportClient { _ in
            throw OpenMusicEventSourceValidationError.missingOrganizerIDForLocalSource
        }
    }
}

public extension DependencyValues {
    var tangledSourceImport: TangledSourceImportClient {
        get { self[TangledSourceImportClientKey.self] }
        set { self[TangledSourceImportClientKey.self] = newValue }
    }
}

@Feature
public struct TangledSourceDownload {
    public init() {}

    @Dependency(\.tangledSourceImport) var tangledSourceImport

    public struct State {
        public init() {}

        var repository = ""
        var ref = "HEAD"
        var importedSummary: SourceValidationSummary?
        var isImporting = false
        var errorMessage: String?

        var trimmedRepository: String {
            repository.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var resolvedRef: String {
            let trimmedRef = ref.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedRef.isEmpty ? "HEAD" : trimmedRef
        }

        var canImport: Bool {
            !isImporting && !trimmedRepository.isEmpty
        }
    }

    public enum Action {
        case importButtonTapped
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .importButtonTapped:
                guard !state.isImporting else { return }
                guard !state.trimmedRepository.isEmpty else {
                    state.errorMessage = "Enter a Tangled repository."
                    return
                }

                let request = OpenMusicEventSourceValidationRequest(
                    source: state.trimmedRepository,
                    ref: state.resolvedRef
                )
                state.isImporting = true
                state.importedSummary = nil
                state.errorMessage = nil

                store.addTask {
                    await Task.yield()
                    let result = await store.withErrorHandling(
                        fallbackMessage: .sourceImportFailed,
                        operation: .sourceImport
                    ) {
                        try await tangledSourceImport.importSource(request)
                    } cleanup: {
                        $0.isImporting = false
                    } parseError: {
                        SourceImportError.parser
                    }
                    guard let result else { return }

                    await Task.yield()
                    try store.modify {
                        $0.isImporting = false
                        $0.importedSummary = result.summary
                        $0.errorMessage = nil
                    }
                    try store.post(
                        key: SourceImportCompleted.self,
                        value: ImportedSource(
                            organizerID: result.organizerID,
                            sourceBaselineID: (try? request.tangledSourceProvenance())
                                .map(SourceBaselineRecord.ID.init(source:))
                        )
                    )
                    _ = try? store.dismiss()
                }
            }
        }
    }
}

struct TangledSourceDownloadView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var store: StoreOf<TangledSourceDownload>

    var body: some View {
        Form {
            Section {
                TextField(
                    "Repository",
                    text: $store.repository,
                    prompt: Text("https://tangled.org/owner/repo")
                )
                .autocorrectionDisabled()
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                .textContentType(.URL)
                #endif

                TextField("Ref", text: $store.ref, prompt: Text("HEAD"))
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Text("Source")
            }

            if let importedSummary = store.importedSummary {
                Section("Imported") {
                    Text("\(importedSummary.events.count) events")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .disabled(store.isImporting)
        .navigationTitle("Import Team Workspace")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if store.isImporting {
                    ProgressView()
                } else {
                    Button("Import") {
                        store.send(.importButtonTapped)
                    }
                    .disabled(!store.canImport)
                }
            }
        }
    }
}
