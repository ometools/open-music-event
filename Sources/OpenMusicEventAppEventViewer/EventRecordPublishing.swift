import ATProto
import ATProtoOAuth
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import SourceEditing
#if os(Android)
import SkipSwiftUI
#else
import SwiftUI
#endif

@Feature
public struct EventRecordPublishing {
    public init() {}

    public struct State {
        public init(
            eventID: Event.ID,
            baseline: SourceBaselineDatabase? = nil,
            selectedSessionID: Shared<Atmosphere.Account.ID?> = OpenMusicEventOAuth.selectedSessionID
        ) {
            self.eventID = eventID
            self._selectedSessionID = selectedSessionID
            self._changes = Fetch(wrappedValue: [], CanonicalChangesRequest(eventID: eventID, baseline: baseline))
        }

        public let eventID: Event.ID
        public var account = Spawn(Account.State())
        @Shared public var selectedSessionID: Atmosphere.Account.ID?
        @FetchAll public var events: [Event]
        @FetchAll public var importedIdentities: [CanonicalSourceEventIdentity]
        @DebugSnapshotIgnored @Fetch public var changes: [CanonicalWorkspaceRecordChange]
        public var review: EventRecordPublication?
        public var reviewChanges: [CanonicalWorkspaceRecordChange] = []
        public var result: EventRecordPublicationResult?
        public var errorMessage: String?
        public var isPublishing = false

        var pendingEvents: [Event] {
            let ids = Set(changes.filter(\.canPublish).map(\.id))
            return workspaceEvents.filter { ids.contains($0.id) }
        }

        var workspaceEvents: [Event] {
            guard let source = importedIdentities.first(where: { $0.id == eventID }) else {
                return events.filter { $0.id == eventID }
            }
            let ids = Set(importedIdentities.filter {
                $0.source == source.source && $0.publisher == source.publisher
            }.map(\.id))
            return events.filter { ids.contains($0.id) }
        }
    }

    public enum Action {
        case closeButtonTapped
        case reviewButtonTapped
        case publishButtonTapped
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.oauthAuthorizationBroker) var authorization
    @Dependency(EventRecordPublisher.self) var publisher

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .closeButtonTapped:
                guard !state.isPublishing else { return }
                store.addTask { try store.dismiss() }

            case .reviewButtonTapped:
                guard !state.isPublishing else { return }
                state.result = nil
                state.errorMessage = nil
                do {
                    guard let account = state.selectedSessionID?.rawValue else {
                        throw EventRecordPublication.PublicationError.wrongAccount
                    }
                    if let error = state.$changes.loadError { throw error }
                    state.review = try Self.prepare(events: state.pendingEvents, account: account)
                    let ids = Set(state.review!.records.map(\.id))
                    state.reviewChanges = state.changes.filter { ids.contains($0.id) }
                } catch {
                    state.review = nil
                    state.reviewChanges = []
                    state.errorMessage = error.localizedDescription
                }

            case .publishButtonTapped:
                guard !state.isPublishing, let review = state.review else { return }
                guard state.selectedSessionID?.rawValue == review.account else {
                    state.review = nil
                    state.reviewChanges = []
                    state.errorMessage = EventRecordPublication.PublicationError.wrongAccount.localizedDescription
                    return
                }
                let selectedSessionID = state.$selectedSessionID
                let database = database
                let authorization = authorization
                let publisher = publisher
                let changes = state.$changes
                state.isPublishing = true
                state.errorMessage = nil
                state.result = nil
                store.addTask {
                    do {
                        try await authorization.authorize(review.authorization)
                        guard selectedSessionID.wrappedValue?.rawValue == review.account else {
                            throw EventRecordPublication.PublicationError.wrongAccount
                        }
                        let current = try await database.read { db in
                            try review.records.map { record in
                                guard let event = try Event.find(record.id).fetchOne(db) else {
                                    throw EventRecordPublication.PublicationError.reviewChanged
                                }
                                return event
                            }
                        }
                        guard try Self.prepare(events: current, account: review.account) == review else {
                            throw EventRecordPublication.PublicationError.reviewChanged
                        }
                        let result = try await publisher.publish(review)
                        // Remote verification remains visible even if saving the local receipt fails.
                        try store.modify { $0.result = result }
                        try await database.write { db in
                            for receipt in result.receipts {
                                try EventRecordPublicationReceipt.upsert { receipt }.execute(db)
                            }
                        }
                        try await changes.load()
                        try store.modify {
                            $0.result = result
                            $0.isPublishing = false
                            $0.review = nil
                            $0.reviewChanges = []
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = error is CancellationError
                                ? "Publication was cancelled. Your local edits are unchanged."
                                : error.localizedDescription
                            $0.isPublishing = false
                        }
                    }
                }
            }
        }
        .spawn(\.account) { Account() }
        .onChange(of: store.selectedSessionID) { state in
            state.review = nil
            state.reviewChanges = []
        }
        .onChange(of: store.events) { state in
            state.review = nil
            state.reviewChanges = []
        }
    }

    static func prepare(events: [Event], account: DID) throws -> EventRecordPublication {
        try EventRecordPublication.prepare(events: events, account: account) { blob in
            guard let url = try stagedLocalImageBlobURL(for: blob) else {
                throw EventRecordPublication.PublicationError.missingImage(blob.ref)
            }
            return try Data(contentsOf: url)
        }
    }
}

public struct EventRecordPublishingView: View {
    @Bindable var store: StoreOf<EventRecordPublishing>
    @Bindable var accountStore: StoreOf<Account>

    public init(store: StoreOf<EventRecordPublishing>) {
        self.store = store
        self.accountStore = store.spawn(\.account)
    }

    public var body: some View {
        Form {
            Section("Publish as") {
                HStack {
                    Text(accountStore.accountRows.first(where: \.isSelected)?.title ?? "Select an account")
                    Spacer()
                    AccountPicker(store: accountStore)
                }
                .disabled(store.isPublishing)
            }
            Section {
                Text("Review your event changes and images before making them public. Other workspace changes are not included.")
                Button(store.result == nil ? "Review Changes" : "Review Remaining Changes") { store.send(.reviewButtonTapped) }
                    .disabled(store.isPublishing || store.pendingEvents.isEmpty)
                    .accessibilityIdentifier("publication.review")
            }
            WorkspaceChangeSummarySection(
                changes: store.review == nil ? store.changes.filter(\.canPublish) : store.reviewChanges
            )
            if store.isPublishing { ProgressView("Publishing changes and images…") }
            if let error = store.errorMessage {
                Section("Changes not published") {
                    Text(error).accessibilityIdentifier("publication.error")
                    Text("Your local edits are still here. You can try again.")
                }
            }
            if let error = store.$changes.loadError {
                Section("Changes could not be loaded") { Text(error.localizedDescription) }
            }
            if let result = store.result {
                Section("Publication result") {
                    Text("Published \(result.receipts.count) events")
                        .accessibilityIdentifier("publication.verified")
                    ForEach(result.failures.keys.sorted(by: { $0.description < $1.description }), id: \.self) { id in
                        VStack(alignment: .leading) {
                            Text(store.events.first { $0.id == id }?.name ?? "Event").font(.headline)
                            Text(result.failures[id] ?? "Publication failed")
                            Text("Your edits are preserved. Review remaining changes to try again.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    DisclosureGroup("Technical details") {
                        ForEach(result.receipts) { receipt in
                            Text(receipt.id.description).textSelection(.enabled)
                            Text(receipt.cid.rawValue).textSelection(.enabled)
                            ForEach(receipt.images, id: \.ref) { blob in
                                Text(blob.ref.rawValue).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Publish Changes")
        .interactiveDismissDisabled(store.isPublishing)
        .sheet(
            item: $accountStore.presentation,
            onDismiss: { accountStore.send(.accountPresentationDismissed) }
        ) { _ in
            AccountPresentationView(store: accountStore)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(store.result == nil ? "Cancel" : "Done") { store.send(.closeButtonTapped) }
                    .disabled(store.isPublishing)
                    .accessibilityIdentifier("publication.close")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Publish") { store.send(.publishButtonTapped) }
                    .disabled(store.isPublishing || store.review == nil)
                    .accessibilityIdentifier("publication.publish")
            }
        }
    }
}
