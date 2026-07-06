import ComposableArchitecture2
import Foundation
import OpenMusicEventImages
import OpenMusicEventLexicon
import SwiftUI

struct MyEventsView: View {
    @Bindable var store: StoreOf<MyEvents>

    var body: some View {
        content
            .navigationTitle("My Events")
            .listStyle(.plain)
            .confirmationDialog(
                "Delete Created Events?",
                isPresented: deleteCreatedEventsConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete Created Events", role: .destructive) {
                    store.send(.deleteCreatedEventsConfirmationDeleteButtonTapped)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the selected event data from this device. Team workspace source trees can be re-imported from the Tangled workspace, but created events are not cached off device.")
            }
            .toolbar {
                toolbarContent
            }
            .sheet(item: $store.scope(\.destination, action: \.destination).createEvent) { createEventStore in
                NavigationStack {
                    CreateEventView(store: createEventStore)
                }
            }
            .sheet(item: $store.scope(\.destination, action: \.destination).sourceImport) { downloadStore in
                NavigationStack {
                    TangledSourceDownloadView(store: downloadStore)
                }
            }
            .navigationDestination(item: $store.scope(\.organizerDetail, action: \.organizerDetail)) { detailStore in
                OrganizerDetailView(store: detailStore)
            }
            .navigationDestination(item: $store.scope(\.teamWorkspaceDetail, action: \.teamWorkspaceDetail)) { detailStore in
                TeamWorkspaceDetailView(store: detailStore)
            }
    }

    private var deleteCreatedEventsConfirmationPresented: Binding<Bool> {
        Binding(
            get: { store.isDeleteCreatedEventsConfirmationPresented },
            set: { store.send(.deleteCreatedEventsConfirmationPresentedChanged($0)) }
        )
    }

    private var content: some View {
        List {
            errorSection
            teamWorkspacesSection
            eventsSection
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = store.errorMessage {
            Section {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        if !store.fetchLoadFailures.isEmpty {
            FetchLoadErrorSection(failures: store.fetchLoadFailures)
        }
    }

    @ViewBuilder
    private var teamWorkspacesSection: some View {
        if !store.teamWorkspaces.isEmpty {
            Section("Team Workspaces") {
                ForEach(store.teamWorkspaces) { teamWorkspace in
                    Button {
                        store.send(.didTapTeamWorkspace(teamWorkspace.id))
                    } label: {
                        TeamWorkspaceRowView(teamWorkspace: teamWorkspace)
                    }
                }
                .onDelete { offsets in
                    deleteTeamWorkspaces(at: offsets)
                }
            }
        }
    }

    @ViewBuilder
    private var eventsSection: some View {
        if !store.events.isEmpty {
            Section("Events") {
                ForEach(store.events) { event in
                    Button {
                        store.send(.didTapEvent(event))
                    } label: {
                        EventRowView(event: event)
                    }
                }
                .onDelete { offsets in
                    confirmDeleteCreatedEvents(at: offsets)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button("Import Team Workspace", systemImage: "arrow.down.doc") {
                store.send(.didTapImportTeamWorkspace)
            }

            Button("Create Event", systemImage: "plus") {
                store.send(.didTapCreateEvent)
            }
        }
    }

    func deleteTeamWorkspaces(at offsets: IndexSet) {
        let sourceBaselineIDs = offsets.compactMap { offset in
            store.teamWorkspaces.indices.contains(offset)
                ? store.teamWorkspaces[offset].id
                : nil
        }
        store.send(.deleteTeamWorkspaces(sourceBaselineIDs))
    }

    func confirmDeleteCreatedEvents(at offsets: IndexSet) {
        let eventIDs = offsets.compactMap { offset in
            store.events.indices.contains(offset)
                ? store.events[offset].id
                : nil
        }
        store.send(.deleteCreatedEventsButtonTapped(eventIDs))
    }
}

struct FetchLoadErrorSection: View {
    let failures: [FetchLoadFailure]

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Unable to load data.")
                ForEach(failures) { failure in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(describing: failure.error))
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.red)
        }
    }
}

#Preview {
    NavigationStack {
        MyEventsView(store: Store(initialState: .init(), feature: {
            MyEvents()
        }))
    }
}

struct OrganizerRowView: View {
    var organizer: OMERecord.Organizer

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 60, height: 60)

            Text(organizer.id.description)
                .lineLimit(1)

            Spacer()
        }
        .foregroundStyle(.primary)
    }
}

struct TeamWorkspaceRowView: View {
    var teamWorkspace: TeamWorkspaceRow

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(teamWorkspace.sourceBaseline.sourceReference)
                    .lineLimit(1)
                Text(
                    "\(teamWorkspace.refTitle) - \(teamWorkspace.organizer.id.description)"
                )
                    .lineLimit(1)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .foregroundStyle(.primary)
    }
}

struct EventRowView: View {
    var event: OMERecord.Event

    var eventDateString: String? {
        event.eventDateText(dateStyle: .long)
    }

    var body: some View {
        HStack(spacing: 10) {
            EventIconImageView(event: event)
                .frame(width: 60, height: 60)
            //                    .foregroundColor(.label)
            //                .invertForLightMode()

            HStack {
                VStack(alignment: .leading) {
                    Text(event.name)
                    if let eventDateString {
                        Text(eventDateString)
                            .lineLimit(1)
                            .font(.caption2)
                    }
                }
            }

            Spacer()
        }
        .foregroundStyle(.primary)
    }

    struct EventIconImageView: View {
        let event: OMERecord.Event

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.secondary.opacity(0.12))

                ImageAssetAsyncImage(
                    asset: event.images?.imageAsset(role: .icon),
                    cacheContext: .init(eventID: event.id),
                    contentMode: .fit
                ) {
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private extension OMERecord.Event {
    func eventDateText(dateStyle: DateFormatter.Style) -> String? {
        switch (startDate, endDate) {
        case let (.some(startDate), .some(endDate)):
            let formatter = DateIntervalFormatter()
            formatter.timeZone = timeZone
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            return formatter.string(
                from: startDate.atStartOfDay(in: timeZone),
                to: endDate.atStartOfDay(in: timeZone)
            )

        case let (.some(startDate), .none):
            return startDate.formatted(dateStyle: dateStyle, in: timeZone)

        case let (.none, .some(endDate)):
            return endDate.formatted(dateStyle: dateStyle, in: timeZone)

        case (.none, .none):
            return nil
        }
    }
}

private extension LocalDate {
    func formatted(dateStyle: DateFormatter.Style, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = .none
        return formatter.string(from: atStartOfDay(in: timeZone))
    }
}
