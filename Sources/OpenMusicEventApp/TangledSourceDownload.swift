import ATProtoOAuth
import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import SwiftUI
import UniformTypeIdentifiers

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

private extension OpenMusicEventSourceValidationResult {
    func sourceBaselineID(
        fallbackRequest: OpenMusicEventSourceValidationRequest
    ) -> SourceBaselineRecord.ID? {
        if let sourceProvenance = insertion.eventSourceProvenances.first?.source {
            return SourceBaselineRecord.ID(source: sourceProvenance)
        }
        return (try? fallbackRequest.tangledSourceProvenance())
            .map(SourceBaselineRecord.ID.init(source:))
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
                let storedRepositoryURL = try sourceRepositoryStorage.repositoryURL(sourceProvenance)
                if Self.isGitRepository(storedRepositoryURL) {
                    request.outputURL = storedRepositoryURL
                    var result = try await OpenMusicEventSourceValidator(request)
                        .validate()
                    result.repositoryURL = storedRepositoryURL
                    try await result.insertion.migrateAndInsert(into: database)
                    return result
                }

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

private extension TangledSourceImportClient {
    static func isGitRepository(_ repositoryURL: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: repositoryURL
                .standardizedFileURL
                .appending(path: ".git")
                .path(percentEncoded: false)
        )
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

    @Dependency(\.getOptionalDefaultSession) var getOptionalDefaultSession
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
        case sourceFolderSelected(String)
        case sourceFolderSelectionFailed
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .importButtonTapped:
                guard !state.isImporting else { return }
                guard !state.trimmedRepository.isEmpty else {
                    state.errorMessage = "Enter a local folder or shared workspace address."
                    return
                }

                var request = OpenMusicEventSourceValidationRequest(
                    source: state.trimmedRepository,
                    ref: state.resolvedRef
                )
                if case .local = try? SourceRepositoryLocation(parsing: state.trimmedRepository) {
                    guard let session = getOptionalDefaultSession(),
                          let organizerID = OMERecord.Organizer.ID(
                            session.accountID.rawValue.description
                          )
                    else {
                        state.errorMessage = "Sign in before opening a local source."
                        return
                    }
                    request.organizerID = organizerID
                }
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
                            sourceBaselineID: result.sourceBaselineID(fallbackRequest: request)
                        )
                    )
                    _ = try? store.dismiss()
                }

            case .sourceFolderSelected(let path):
                state.repository = path
                state.errorMessage = nil

            case .sourceFolderSelectionFailed:
                state.errorMessage = "Unable to open local folder."
            }
        }
    }
}

struct TangledSourceDownloadView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var store: StoreOf<TangledSourceDownload>
    @State var isSourceFolderImporterPresented = false

    var body: some View {
        Form {
            Section {
                Button("Open Local Folder") {
                    isSourceFolderImporterPresented = true
                }

                TextField(
                    "Workspace address",
                    text: $store.repository,
                    prompt: Text("https://tangled.org/owner/repo")
                )
                .autocorrectionDisabled()
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                .textContentType(.URL)
                #endif

                TextField("Version", text: $store.ref, prompt: Text("main or HEAD"))
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Text("Workspace")
            }

            Section("Canonical Sources") {
                canonicalSourceButton(
                    "Wicked Woods",
                    source: "wickedwoods.ca/ome-workspace"
                )
                canonicalSourceButton(
                    "Shambhala",
                    source: "woody.fm/shambhala-ome"
                )
                canonicalSourceButton(
                    "Pine Creek Lodge",
                    source: "woody.fm/pine-creek-lodge-ome"
                )
                canonicalSourceButton(
                    "Folk Fest",
                    source: "woody.fm/montana-folk-festival-ome"
                )
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
        .fileImporter(
            isPresented: $isSourceFolderImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    store.send(.sourceFolderSelected(url.path(percentEncoded: false)))
                }

            case .failure:
                store.send(.sourceFolderSelectionFailed)
            }
        }
        .navigationTitle("Open Shared Workspace")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Label("Cancel", systemImage: "close")
                        .labelStyle(.iconOnly)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                SubmitButton(
                    isInProgress: store.isImporting,
                    isDisabled: !store.canImport
                ) {
                    store.send(.importButtonTapped)
                }
            }
        }
    }

    private func canonicalSourceButton(
        _ title: LocalizedStringKey,
        source: String
    ) -> some View {
        Button(title) {
            store.send(.sourceFolderSelected(source))
            store.send(.importButtonTapped)
        }
    }
}
