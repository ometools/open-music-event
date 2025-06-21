//
//  OrganizerListView.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/7/25.
//

import SwiftUI
import SharingGRDB
import SwiftUINavigation
import ImageCaching

struct OrganizerListView: View {
    @MainActor
    @Observable
    class Model {
        public init() {}

        @ObservationIgnored
        @FetchAll(Organizer.all.order(by: \.name))
        var organizers

        @CasePathable
        enum Destination {
            case organizerDetail(OrganizerDetailView.ViewModel)
            case addOrganization(OrganizationFormView.Model)
        }

        var destination: Destination?
        func onAppear() async {
            await withErrorReporting {
                try await $organizers.load()
            }
        }

        func didTapOrganizer(id: Organizer.ID) {
            self.destination = .organizerDetail(.init(url: id))
        }

        func didTapAddOrganizerButton() {
            self.destination = .addOrganization(.init())
        }

        func didDeleteOrganization(organization: Organizer) {
            @Dependency(\.defaultDatabase) var database

            withErrorReporting {
              try database.write { db in
                try Organizer.delete(organization)
                  .execute(db)
              }
            }
        }
    }

    @Bindable var store: Model

    public var body: some View {
        Group {

            if !store.organizers.isEmpty {
                List {
                    ForEach(store.organizers) { org in
                        NavigationLinkButton {
                            store.didTapOrganizer(id: org.id)
                        } label: {
                            Row(org: org)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.didDeleteOrganization(organization: org)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
                .listStyle(.plain)

            } else {
                ContentUnavailableView(
                    "No Organizations Yet",
                    systemImage: "folder.badge.plus",
                    description: Text("Use the + button in the top right, and add a link to any Open Music Event directory")
                )
            }
        }
        .navigationTitle("Organizations")
        .toolbar {
            Button("Add Organization", systemImage: "plus") {
                store.didTapAddOrganizerButton()
            }
            .popoverTip(AddOrganizationTip())
        }
        .navigationDestination(item: $store.destination.organizerDetail) { store in
            OrganizerDetailView(store: store)
        }
        .sheet(item: $store.destination.addOrganization) { store in
            NavigationStack {
                OrganizationFormView(store: store)
                    .navigationTitle("Add Organization")
            }
        }

    }

    struct Row: View {
        var org: Organizer

        var body: some View {
            HStack {
                Organizer.IconView(organizer: org)
                    .frame(width: 60, height: 60)
                    .aspectRatio(contentMode: .fit)

                VStack(alignment: .leading) {
                    Text(org.name)
                    Text(org.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

import TipKit

struct AddOrganizationTip: Tip {
    var title: Text {
        Text("Add an Organization")
    }

    var message: Text? {
        Text("Tap the + button in the top right to add a new organization from a local directory.")
    }

    var image: Image? {
        Image(systemName: "plus.circle.fill")
    }
}
