import ComposableArchitecture2
import Dependencies
import Foundation
import SQLiteData
import Tagged
import SwiftUI

@Feature
public struct PeopleViewer {
    public init() {}

    public struct State {
        public init(
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil,
            database: (any DatabaseReader)? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            _participants = FetchAll(
                PeopleViewer.participantsQuery(eventID: eventID),
                database: database
            )
        }

        public let eventID: OMERecord.Event.ID
        public var destination: Destination.State?
        public var searchText = ""

        @FetchAll public var participants: [OMERecord.Participant]

        public var filteredParticipants: [OMERecord.Participant] {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return participants }

            return participants.filter { participant in
                participant.name.localizedStandardContains(query)
                    || participant.kind?.rawValue.localizedStandardContains(query) == true
            }
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case participantButtonTapped(OMERecord.ID<OMERecord.Participant>)
    }

    @Feature
    public enum Destination {
        case participantDetail(Spawn<ParticipantDetail>)
    }

    static func participantsQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Participant> {
        OMERecord.Participant
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { $0.name.collate(.nocase) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case let .participantButtonTapped(participantID):
                state.destination = .participantDetail(
                    Spawn(.init(participantID: participantID, eventID: state.eventID))
                )
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct PeopleViewerView: View {
    @Bindable var store: StoreOf<PeopleViewer>

    public init(store: StoreOf<PeopleViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.participants.isEmpty {
                ViewerPlaceholderView(
                    title: "People",
                    systemImage: "person.3",
                    description: "No people have been added to this event yet."
                )
            } else if store.filteredParticipants.isEmpty {
                ViewerPlaceholderView(
                    title: "No Results",
                    systemImage: "person.3",
                    description: "No people match your search."
                )
            } else {
                List(store.filteredParticipants) { participant in
                    Button {
                        store.send(.participantButtonTapped(participant.id.participantID))
                    } label: {
                        PeopleRowView(participant: participant)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .navigationTitle("People")
            }
        }
        .searchable(text: $store.searchText, prompt: "Search People")
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .navigationDestination(item: $store.scope(state: \.destination, action: \.destination).participantDetail) { detailStore in
            ParticipantDetailView(store: detailStore)
        }
    }
}

struct PeopleRowView: View {
    let participant: OMERecord.Participant

    var body: some View {
        HStack(spacing: 12) {
            ParticipantArtworkView(
                imageURL: participant.imageURL ?? participant.logoURL,
                size: 60
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(participant.name)
                    .lineLimit(1)

                if let kind = participant.kind?.displayName {
                    Text(kind)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .foregroundStyle(.primary)
    }
}

@Feature
public struct ParticipantDetail {
    public init() {}

    public struct State: Identifiable {
        public let participantID: OMERecord.ID<OMERecord.Participant>
        public let eventID: OMERecord.Event.ID

        @FetchOne public var participant: OMERecord.Participant?

        public init(
            participantID: OMERecord.ID<OMERecord.Participant>,
            eventID: OMERecord.Event.ID? = nil,
            database: (any DatabaseReader)? = nil
        ) {
            @Dependency(\.defaultEventID) var defaultEventID

            self.participantID = participantID
            self.eventID = eventID ?? defaultEventID
            _participant = FetchOne(
                ParticipantDetail.participantQuery(
                    participantID: participantID,
                    eventID: self.eventID
                ),
                database: database
            )
        }

        public var id: OMERecord.ID<OMERecord.Participant> { participantID }
    }

    public enum Action {}

    static func participantQuery(
        participantID: OMERecord.ID<OMERecord.Participant>,
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Participant> {
        OMERecord.Participant
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.id.participantID.eq(participantID) }
    }

    public var body: some Feature {
        Update { _, _ in }
    }
}

public struct ParticipantDetailView: View {
    let store: StoreOf<ParticipantDetail>

    public init(store: StoreOf<ParticipantDetail>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let participant = store.participant {
                List {
                    ParticipantHeaderView(participant: participant)

                    if let bio = participant.displayBio {
                        Section("About") {
                            Text(bio)
                        }
                    }

                    if let links = participant.links, !links.isEmpty {
                        Section("Links") {
                            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                                ParticipantLinkRow(link: link)
                            }
                        }
                    }
                }
                .navigationTitle(participant.name)
            } else {
                ContentUnavailableView(
                    "Person",
                    systemImage: "person.crop.circle",
                    description: Text(verbatim: store.participantID.rawValue.rawValue)
                )
                .navigationTitle("Person")
            }
        }
    }
}

struct ParticipantHeaderView: View {
    let participant: OMERecord.Participant

    var body: some View {
        HStack(spacing: 14) {
            ParticipantArtworkView(
                imageURL: participant.imageURL ?? participant.logoURL,
                size: 72
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(participant.name)
                    .font(.headline)
                    .lineLimit(2)

                if let kind = participant.kind?.displayName {
                    Text(kind)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

struct ParticipantArtworkView: View {
    let imageURL: URL?
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.secondary.opacity(0.12))

            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.square")
            .font(.system(size: size * 0.42))
            .foregroundStyle(.secondary)
    }
}

struct ParticipantLinkRow: View {
    let link: ExternalPlatform.Link

    var body: some View {
        Link(destination: link.destinationURL) {
            HStack(spacing: 12) {
                Text(link.displayName)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }
}

private extension OMERecord.Participant {
    var displayBio: String? {
        let bio = bio?.trimmingCharacters(in: .whitespacesAndNewlines)
        return bio?.isEmpty == false ? bio : nil
    }
}

private extension OMERecord.Participant.Kind {
    var displayName: String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension ExternalPlatform.Link {
    var destinationURL: URL {
        guard url.scheme == nil else { return url }
        return URL(string: "https://\(url.absoluteString)") ?? url
    }

    var displayName: String {
        platform?.name ?? url.host ?? url.absoluteString
    }
}
