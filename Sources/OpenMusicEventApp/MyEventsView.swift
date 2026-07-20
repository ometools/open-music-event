import ComposableArchitecture2
import Foundation
import OpenMusicEventComponents
import OpenMusicEventImages
import OpenMusicEventLexicon
import SQLiteData
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
                Text("This permanently deletes the selected event data from this device. Shared workspace source trees can be opened again, but created events are not cached off device.")
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
            Section("Shared Workspaces") {
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
                    .contextMenu {
                        Button("Delete Event", role: .destructive) {
                            confirmDeleteCreatedEvent(event.id)
                        }
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
            Button {
                store.send(.didTapImportTeamWorkspace)
            } label: {
                Label("Open Shared Workspace", systemImage: "arrow.down.doc")
                    .labelStyle(.iconOnly)
            }

            Button {
                store.send(.didTapCreateEvent)
            } label: {
                Label("Create Event", systemImage: "plus")
                    .labelStyle(.iconOnly)
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

    func confirmDeleteCreatedEvent(_ eventID: OMERecord.Event.ID) {
        store.send(.deleteCreatedEventsButtonTapped([eventID]))
    }
}

struct FetchLoadErrorSection: View {
    let failures: [FetchLoadFailure]
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Unable to load data.")
                if showsTechnicalDetails {
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
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 60, height: 60)

            Text(showsTechnicalDetails ? organizer.id.description : "Organizer")
                .lineLimit(1)

            Spacer()
        }
        .foregroundStyle(.primary)
    }
}

struct TeamWorkspaceRowView: View {
    var teamWorkspace: TeamWorkspaceRow
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text("Shared workspace")
                    .lineLimit(1)
                Text(
                    teamWorkspace.eventCount == 1
                        ? showsTechnicalDetails
                            ? "1 event · \(teamWorkspace.refTitle)"
                            : "1 event"
                        : showsTechnicalDetails
                            ? "\(teamWorkspace.eventCount) events · \(teamWorkspace.refTitle)"
                            : "\(teamWorkspace.eventCount) events"
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

    nonisolated static func imageAssets(
        icon: OME.ImageAsset?,
        poster: OME.ImageAsset?
    ) -> [OME.ImageAsset] {
        [icon, poster].compactMap { $0 }
    }

    static func posterQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Poster> {
        OMERecord.Poster
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
    }

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
        @FetchOne var poster: OMERecord.Poster?

        init(event: OMERecord.Event) {
            self.event = event
            _poster = FetchOne(EventRowView.posterQuery(eventID: event.id))
        }

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.secondary.opacity(0.12))

                EventImageSourceChain(
                    sources: imageSources[...]
                ) {
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        private var imageSources: [DisplayImageAsset] {
            EventRowView.imageAssets(
                icon: event.images?.imageAsset(role: .icon),
                poster: poster?.image
            ).map { asset in
                DisplayImageAsset(
                    asset: asset,
                    cacheContext: asset.role == .poster
                        ? poster.map { .init(posterID: $0.id) }
                        : .init(eventID: event.id)
                )
            }
        }
    }
}

struct EventImageSourceChain<Placeholder: View>: View {
    let sources: ArraySlice<DisplayImageAsset>
    @ViewBuilder var placeholder: () -> Placeholder

    @ViewBuilder
    var body: some View {
        if let source = sources.first {
            ImageAssetAsyncImage(
                image: source,
                contentMode: .fit
            ) { reason in
                switch reason {
                case .loading:
                    Color.clear
                case .failure, .unavailable:
                    if sources.dropFirst().isEmpty {
                        placeholder()
                    } else {
                        EventImageSourceChain(
                            sources: sources.dropFirst(),
                            placeholder: placeholder
                        )
                    }
                }
            }
        } else {
            placeholder()
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
