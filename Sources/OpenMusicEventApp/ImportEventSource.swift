import ATProto
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData
#if os(Android)
import SkipSwiftUI
#else
import SwiftUI
#endif

@Feature
public struct ImportEventSource {
    public struct State {
        var source = ""
        var publisher = OpenMusicEventOAuth.selectedSessionID.wrappedValue?.rawValue.description ?? ""
        var isImporting = false
        var imported: [Event.ID] = []
        var errorMessage: String?
    }

    public enum Action {
        case importButtonTapped
        case sourceSelected(String)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now

    public var body: some Feature {
        Update { state, action in
            if case let .sourceSelected(source) = action {
                state.source = source
                return
            }
            guard !state.isImporting else { return }
            guard let publisher = DID(state.publisher.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                state.errorMessage = "Enter the DID of the repository that will own these Events."
                return
            }
            let request = OpenMusicEventSourceValidationRequest(
                source: state.source.trimmingCharacters(in: .whitespacesAndNewlines),
                organizerID: publisher
            )
            let database = database
            let date = now
            state.isImporting = true
            state.errorMessage = nil
            store.addTask {
                do {
                    let validated = try await OpenMusicEventSourceValidator(request).validate()
                    let ids = try await CanonicalSourceEventImport.insert(validated, at: date, in: database)
                    try store.modify {
                        $0.imported = ids
                        $0.isImporting = false
                    }
                } catch {
                    try store.modify {
                        $0.errorMessage = error.localizedDescription
                        $0.isImporting = false
                    }
                }
            }
        }
    }
}

struct ImportEventSourceView: View {
    @Bindable var store: StoreOf<ImportEventSource>
    @Dependency(\.openMusicEventUIAutomation) var automation

    var body: some View {
        Form {
            Section("Source repository") {
                TextField("Repository or local folder", text: $store.source)
                    .accessibilityIdentifier("source.import.repository")
                TextField("Publisher DID", text: $store.publisher)
                    .accessibilityIdentifier("source.import.publisher")
                Text("Import and edit without signing in. Publishing later requires this account. Existing imported Events keep their local edits.")
                    .font(.footnote)
                #if DEBUG
                if automation == .publication,
                   let source = Bundle.module.url(forResource: "TestivalSource", withExtension: nil) {
                    Button("Use Testival source") { store.send(.sourceSelected(source.path)) }
                        .accessibilityIdentifier("source.import.testival")
                }
                #endif
            }
            Button("Import Events") { store.send(.importButtonTapped) }
                .disabled(store.isImporting || store.source.isEmpty || store.publisher.isEmpty)
                .accessibilityIdentifier("source.import.submit")
            if store.isImporting { ProgressView("Importing Events") }
            if let error = store.errorMessage {
                Text(error).foregroundStyle(.red)
                    .accessibilityIdentifier("source.import.error")
            }
            if !store.imported.isEmpty {
                Text("\(store.imported.count) Events are ready in My Events.")
                    .accessibilityIdentifier("source.import.complete")
            }
        }
        .navigationTitle("Import Events")
    }
}
