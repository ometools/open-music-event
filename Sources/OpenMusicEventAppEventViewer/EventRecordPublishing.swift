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
            selectedSessionID: Shared<Atmosphere.Account.ID?> = OpenMusicEventOAuth.selectedSessionID
        ) {
            self.eventID = eventID
            self._selectedSessionID = selectedSessionID
        }

        public let eventID: Event.ID
        public var account = Spawn(Account.State())
        @Shared public var selectedSessionID: Atmosphere.Account.ID?
        @FetchAll public var events: [Event]
        @FetchAll public var importedIdentities: [CanonicalSourceEventIdentity]
        public var review: EventRecordPublication?
        public var result: EventRecordPublicationResult?
        public var errorMessage: String?
        public var isPublishing = false

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
        case reviewButtonTapped
        case publishButtonTapped
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.oauthAuthorizationBroker) var authorization
    @Dependency(EventRecordPublisher.self) var publisher

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .reviewButtonTapped:
                guard !state.isPublishing else { return }
                state.result = nil
                state.errorMessage = nil
                do {
                    guard let account = state.selectedSessionID?.rawValue else {
                        throw EventRecordPublication.PublicationError.wrongAccount
                    }
                    state.review = try Self.prepare(events: state.workspaceEvents, account: account)
                } catch {
                    state.review = nil
                    state.errorMessage = error.localizedDescription
                }

            case .publishButtonTapped:
                guard !state.isPublishing, let review = state.review else { return }
                guard state.selectedSessionID?.rawValue == review.account else {
                    state.review = nil
                    state.errorMessage = EventRecordPublication.PublicationError.wrongAccount.localizedDescription
                    return
                }
                let selectedSessionID = state.$selectedSessionID
                let database = database
                let authorization = authorization
                let publisher = publisher
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
                        try store.modify {
                            $0.result = result
                            $0.isPublishing = false
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
        }
        .onChange(of: store.events) { state in
            state.review = nil
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

    public init(store: StoreOf<EventRecordPublishing>) { self.store = store }

    public var body: some View {
        Form {
            AccountView(store: store.spawn(\.account))
                .disabled(store.isPublishing)
            Section {
                Text("Publish this workspace’s Event records and images to the selected account. This does not publish source changes to Tangled.")
                Button("Review records") { store.send(.reviewButtonTapped) }
                    .disabled(store.isPublishing)
                    .accessibilityIdentifier("publication.review")
            }
            if let review = store.review {
                ForEach(review.records) { record in
                    Section(record.event.name) {
                        if let description = record.event.description { Text(description) }
                        ForEach(Array((record.event.media ?? []).enumerated()), id: \.offset) { _, media in
                            if case let .known(.image(image)) = media {
                                ImageAssetAsyncImage(image: .record(image, record.id)) {
                                    ProgressView()
                                }
                                .frame(height: 150)
                                if let alt = image.alt { Text(alt.rawValue) }
                            }
                        }
                    }
                }
                Section {
                    Button("Publish records") { store.send(.publishButtonTapped) }
                        .disabled(store.isPublishing)
                        .accessibilityIdentifier("publication.publish")
                }
            }
            if store.isPublishing { ProgressView("Publishing records and images") }
            if let error = store.errorMessage {
                Text(error).accessibilityIdentifier("publication.error")
            }
            if let result = store.result {
                Section("Publication result") {
                    Text("Verified \(result.receipts.count) event records")
                        .accessibilityIdentifier("publication.verified")
                    ForEach(result.failures.keys.sorted(by: { $0.description < $1.description }), id: \.self) { id in
                        Text(result.failures[id] ?? "Publication failed")
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
        .navigationTitle("Publish records")
    }
}
