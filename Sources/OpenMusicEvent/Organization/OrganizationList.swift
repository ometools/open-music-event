//
//  OrganizerListView.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/7/25.
//

import CoreModels
import SwiftUI
import SkipFuse
import GRDB
import Dependencies
import IssueReporting
import CasePaths
import OpenMusicEventParser

struct OrganizerListView: View {


    @MainActor
    @Observable
    class Model {
        public init() {}

        public typealias Organization = Organizer.Draft


        struct StoredOrganization: Sendable, Equatable, Identifiable {
            var id: Organizer.ID? { organization.id }
            var url: URL
            var organization: Organization
        }

        var organizations: [StoredOrganization] = []

        

        @CasePathable
        enum Destination {
            case organizationRoot(OrganizationRootView.Store)
            case addOrganization(OrganizationFormView.Model)
        }

        var destination: Destination?

        func onAppear() async {
            await withTaskGroup {
                $0.addTask { await self.loadAvailableOrganizations() }

                await $0.waitForAll()
            }
        }

        @ObservationIgnored
        @Dependency(\.userPreferencesDatabase) var userPrefsDB


        @ObservationIgnored
        @Dependency(\.organizationDatabaseManager) var dbManager

        func loadAvailableOrganizations() async {
            
            withErrorReporting {
                // List all organizations from filesystem
                let orgs = try dbManager.listOrganizations()

                // Parse organizer info from YAML files (no database opening needed)
                var organizations: [StoredOrganization] = []
                for url in orgs {
                    // Read and parse organizer-info.yml
                    do {
                        let config = try OrganizerConfiguration.fileTree.read(from: url)

                        organizations.append(
                            .init(
                                url: url,
                                organization: config.info
                            )
                        )
                    } catch {
                        reportIssue("failed to parse organizer-info.yml at \(url)")
                    }

                }
                self.organizations = organizations
            }
        }

        @ObservationIgnored
        @Dependency(\.userPreferencesDatabase) var userPrefsDb

        func didTapOrganization(_ organization: StoredOrganization) {
            withErrorReporting {

            }
        }

        func didTapAddOrganizerButton() {
            let addOrganization = OrganizationFormView.Model()
            addOrganization.didFinishSaving = {
                Task { @MainActor in
                    self.destination = nil
                    await self.loadAvailableOrganizations()
                }
            }
            self.destination = .addOrganization(.init())
        }

        func didDeleteOrganization(_ indices: IndexSet) async {
//            Task {
//                await withErrorReporting {
//                    let orgsToDelete = indices.map { organizations[$0] }
//
//                    for item in orgsToDelete {
//                        // Delete entire organization folder
//                        try FileManager.default.removeItem(at: item.filesPath)
//                    }
//
//                    // Reload list
//                    await loadAvailableOrganizations()
//                }
//            }
        }

        func onPullToRefresh() async {
            await self.loadAvailableOrganizations()
        }
    }

    @Bindable var store: Model

    public var body: some View {
        Group {
            switch store.destination {
            case .organizationRoot(let store):
                OrganizationRootView(store: store)
            case .addOrganization(let store):
                NavigationStack {
                    OrganizationFormView(store: store)
                        .navigationTitle("Add Organization")
                }

            case .none:
                NavigationStack {
                    List {
                        if !store.organizations.isEmpty {
                            ForEach(store.organizations) { item in
                                NavigationLinkButton {
                                    store.didTapOrganization(item)
                                } label: {
                                    Row(org: item.organization)
                                }
                            }
                            .onDelete { indexSet in
                                Task {
                                    await store.didDeleteOrganization(indexSet)
                                }
                            }
                        } else {
                            ContentUnavailableView(
                                "No Organizations Yet",
                                systemImage: "folder.badge.plus",
                                description: Text("Use the + button in the top right, and add a link to any Open Music Event directory")
                            )
                        }

                    }
                    .listStyle(.plain)
                    .refreshable {
                        await self.store.onPullToRefresh()
                    }
                    .onAppear { Task { await store.onAppear() }}
                    .navigationTitle("Organizations")
                    .toolbar {
                        Button("Add Organization", image: Icons.plus) {
                            store.didTapAddOrganizerButton()
                        }
                    }
                }
            }
//            .sheet(item: $store.destination.addOrganization) { store in
//                NavigationStack {
//                    OrganizationFormView(store: store)
//                        .navigationTitle("Add Organization")
//                }
//            }


        }




    }

    struct Row: View {
        var org: Organizer.Draft

        var body: some View {
            HStack {
                OrganizerIconView(organizer: org)
                    .frame(width: 60, height: 60)
                    .aspectRatio(contentMode: .fit)

                VStack(alignment: .leading) {
                    Text(org.name)
                    HStack(spacing: 8) {
                        if let url = org.url {
                            Text(url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.primary)
        }
    }
}

//
//@MainActor
//func observe<Model: AnyObject, Entity: FetchableRecord & TableRecord & Sendable>(
//    query: QueryInterfaceRequest<Entity>,
//    at keyPath: ReferenceWritableKeyPath<Model, [Entity]>,
//    for model: Model,
//    dbWriter: any DatabaseWriter
//) async throws -> AnyDatabaseCancellable {
//    try await withCheckedThrowingContinuation { continuation in
//        let observation = ValueObservation
//            .tracking { db in
//                try query.fetchAll(db)
//            }
//
//        var firstValueRecieved = false
//
//        var token = observation
//            .start(
//                in: dbWriter,
//                onError: { error in
//                    reportIssue(error, "Failed to observe query")
//                    if !firstValueRecieved {
//                        continuation.resume(throwing: error)
//                    }
//                },
//                onChange: { [weak model] entities in
//                    guard let model = model else { return }
//                    model[keyPath: keyPath] = entities
//
//                    continuation.resume()
//                }
//            )
//    }
//}

//// Overload — uses defaultDatabase automatically
//import Dependencies
//
//@MainActor
//func fetchAndObserveQuery<Model: AnyObject, Entity: FetchableRecord & TableRecord & Sendable>(
//    query: QueryInterfaceRequest<Entity>,
//    on model: Model,
//    at keyPath: ReferenceWritableKeyPath<Model, [Entity]>
//) async throws -> AnyDatabaseCancellable {
//    @Dependency(\.defaultDatabase) var dbWriter
//    return try await observe(
//        query: query,
//        at: keyPath,
//        for: model,
//        dbWriter: dbWriter
//    )
//}



enum OrganizationRoute: Hashable, Codable {
    case root
    case event(MusicEvent.ID, EventRoute?)
}

enum EventRoute: Hashable, Codable {
    case artists
    case artist(Artist.ID)
    case stages
    case stage(Stage.ID)
    case schedule
    case communications
    case channel(CommunicationChannel.ID)
}

