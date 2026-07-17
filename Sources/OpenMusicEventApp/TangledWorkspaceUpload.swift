import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventSourceEditing
import SwiftUI

public struct TangledWorkspaceBootstrapCompleted: FeatureEventKey {
    public init() {}
    public typealias Value = TangledWorkspaceBootstrapResult
}

@Feature
public struct TangledWorkspaceUpload {
    public init() {}

    @Dependency(\.tangledWorkspaceBootstrap) var tangledWorkspaceBootstrap

    public struct State {
        public init(
            sourceBaselineID: SourceBaselineRecord.ID,
            repositoryName: String,
            description: String = "",
            knotHost: String = "tangled.org",
            defaultBranch: String = "main"
        ) {
            self.sourceBaselineID = sourceBaselineID
            self.repositoryName = repositoryName
            self.description = description
            self.knotHost = knotHost
            self.defaultBranch = defaultBranch
        }

        public let sourceBaselineID: SourceBaselineRecord.ID
        var defaultBranch: String
        var description: String
        var errorMessage: String?
        var isUploading = false
        var knotHost: String
        var repositoryName: String

        var canUpload: Bool {
            !isUploading
            && !repositoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !knotHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !defaultBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public enum Action {
        case uploadButtonTapped
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .uploadButtonTapped:
                guard !state.isUploading else { return }
                guard state.canUpload else {
                    state.errorMessage = "Enter a workspace name, provider, and version."
                    return
                }

                let request = TangledWorkspaceBootstrapRequest(
                    sourceBaselineID: state.sourceBaselineID,
                    repositoryName: state.repositoryName,
                    description: state.description,
                    knotHost: state.knotHost,
                    defaultBranch: state.defaultBranch
                )
                state.errorMessage = nil
                state.isUploading = true

                store.addTask {
                    let result = await store.withErrorHandling(
                        fallbackMessage: .sourceWorkspaceUploadFailed,
                        operation: .sourceWorkspaceUpload
                    ) {
                        try await tangledWorkspaceBootstrap.bootstrap(request)
                    } cleanup: {
                        $0.isUploading = false
                    } parseError: {
                        SourceImportError.parser
                    }
                    guard let result else { return }

                    try store.modify {
                        $0.isUploading = false
                        $0.errorMessage = nil
                    }
                    try store.post(
                        key: TangledWorkspaceBootstrapCompleted.self,
                        value: result
                    )
                    _ = try? store.dismiss()
                }
            }
        }
    }
}

public struct TangledWorkspaceUploadView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var store: StoreOf<TangledWorkspaceUpload>

    public init(store: StoreOf<TangledWorkspaceUpload>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section {
                TextField("Workspace name", text: $store.repositoryName, prompt: Text("festival-source"))
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif

                TextField("Description", text: $store.description)
                    .autocorrectionDisabled()
            } header: {
                Text("Shared workspace")
            }

            Section {
                TextField("Provider address", text: $store.knotHost, prompt: Text("tangled.org"))
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .textContentType(.URL)
                    #endif

                TextField("Default version", text: $store.defaultBranch, prompt: Text("main"))
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Text("Connection details")
            }

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .disabled(store.isUploading)
        .navigationTitle("Create Shared Workspace")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                SubmitButton(
                    isInProgress: store.isUploading,
                    isDisabled: !store.canUpload
                ) {
                    store.send(.uploadButtonTapped)
                }
            }
        }
    }
}
