import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventSource
import SwiftUI

struct TangledSourceImportClient: Sendable {
    var importSource: @Sendable (OpenMusicEventSourceValidationRequest) async throws -> OpenMusicEventSourceValidationResult
}

extension TangledSourceImportClient {
    static var live: Self {
        Self { request in
            try await OpenMusicEventSourceValidator(request)
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

extension DependencyValues {
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
                    do {
                        let result = try await tangledSourceImport.importSource(request)
                        try store.modify {
                            $0.isImporting = false
                            $0.importedSummary = result.summary
                            $0.errorMessage = nil
                        }
                        if let eventID = result.insertedEventIDs.first {
                            try store.post(
                                key: NavigationRequested.self,
                                value: .event(eventID, nil)
                            )
                            try store.dismiss()
                        }
                    } catch {
                        try store.modify {
                            $0.isImporting = false
                            $0.importedSummary = nil
                            $0.errorMessage = error.localizedDescription
                        }
                        reportIssue(error)
                    }
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
        .navigationTitle("Import Source")
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
