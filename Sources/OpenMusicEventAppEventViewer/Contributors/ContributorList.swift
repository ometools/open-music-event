import OpenMusicEventLexicon
import ATProto
import ATProtoTypes
import Bluesky
import ComposableForms
import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventEditors
import OpenMusicEventImages
import SQLiteData
import SwiftUITabFeatures
import Tagged
import SwiftUI

@Feature
public struct ContributorList {
    public init() {}

    public struct State {
        public init(
            eventID: Event.ID,
            destination: Destination.State? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            AttendeePerformance.mark("contributors-query-contributorRows.begin", event: eventID.description)
            _contributorRows = Fetch(wrappedValue: [], ContributorListRequest(eventID: eventID))
            AttendeePerformance.mark("contributors-query-contributorRows.end", event: eventID.description)
            _actorSubjects = FetchAll(
                Contributor.where { $0.event.eq(eventID) && $0.subject.isNot(nil) }
                    .select { $0.subject }.distinct()
            )
        }

        public let eventID: Event.ID
        public var destination: Destination.State?
        public var errorMessage: String?
        public var searchText = ""

        @DebugSnapshotIgnored
        @Fetch var contributorRows: [ContributorListRow] = []
        @DebugSnapshotIgnored
        @FetchAll var actorSubjects: [DID?]

        var actorProfileLoadRequests: [ContributorProfile.ActorProfileLoadRequest] {
            actorSubjects.compactMap { $0.map { .init(actor: $0) } }
        }
    }

    public enum Action {
        case addButtonTapped
        case deleteContributors([Contributor.ID])
        case destination(Destination.Action)
        case contributorButtonTapped(Contributor.ID)
    }

    @Feature
    public enum Destination {
        case contributorDetail(Spawn<ContributorDetail>)
    }

    @StoreTaskID var searchTask

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
    @Dependency(\.defaultDatabase) var database

    static func contributorProfilesQuery(
        eventID: Event.ID,
        hydration: ContributorProfile.Hydration = .none
    ) -> some Statement<ContributorProfile> {
        ContributorProfile.all(eventID: eventID, hydration: hydration)
    }

    static func contributorRowsQuery(
        eventID: Event.ID,
        hydration: ContributorProfile.Hydration = .none
    ) -> some Statement<ContributorListRow> {
        ContributorListRow.all(eventID: eventID, hydration: hydration)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addButtonTapped:
                let eventID = state.eventID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .createContributor(eventID)
                    )
                    await task?.value
                }

            case let .deleteContributors(contributorIDs):
                let eventID = state.eventID
                store.addTask {
                    do {
                        try database.write { db in
                            for contributorID in contributorIDs {
                                try ContributorRecordEditing.delete(
                                    contributorID,
                                    eventID: eventID,
                                    in: db
                                )
                            }
                        }
                        try store.modify {
                            $0.errorMessage = nil
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to delete contributor."
                        }
                    }
                }

            case .destination:
                break

            case let .contributorButtonTapped(contributorID):
                store.withDependencies {
                    state.destination = .contributorDetail(
                        Spawn(.init(contributorID: contributorID, eventID: state.eventID))
                    )
                }
            }
        }
        .onChange(of: store.searchText) { _, search, state in
            let rows = state.$contributorRows
            let request = ContributorListRequest(eventID: state.eventID, search: search)
            store.addTask(id: searchTask) {
                try await rows.load(request).task
            }
        }
        .onChange(of: store.actorProfileLoadRequests, initial: true) { _, requests, _ in
            guard !requests.isEmpty else { return }

            store.addTask {
                for request in requests {
                    do {
                        _ = try await blueskyActorProfileCache.refreshProfileIfNeeded(
                            request.actor.description,
                            24 * 60 * 60,
                            15 * 60
                        )
                    } catch is CancellationError {
                        return
                    } catch {
                    }
                }
            }
        }
        .ifLet(\.destination) {
            Destination.body
        }
    }
}

public struct ContributorListView: View {
    @Bindable var store: StoreOf<ContributorList>
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<ContributorList>,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        Group {
            if store.contributorRows.isEmpty && store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView {
                    Label("Contributors", mappedSystemImage: "person.3")
                } description: {
                    Text(showsAuthoringControls
                        ? "Add the artists, speakers, and other contributors taking part in this event."
                        : "No contributors have been added to this event yet.")
                } actions: {
                    if showsAuthoringControls {
                        Button("Add Contributor") { store.send(.addButtonTapped) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else if store.contributorRows.isEmpty {
                ViewerPlaceholderView(
                    title: "No Results",
                    systemImage: "person.3",
                    description: "No contributors match your search."
                )
            } else {
                List {
                    if let errorMessage = store.errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    ForEach(store.contributorRows) { row in
                        ContributorListButton(
                            row: row
                        ) { contributorID in
                            store.send(.contributorButtonTapped(contributorID))
                        }
                    }
                    .onDelete { offsets in
                        deleteContributors(at: offsets)
                    }
                    .deleteDisabled(!showsAuthoringControls)
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $store.searchText, prompt: "Search Contributors")
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .navigationTitle("Contributors")
        .toolbar {
            if showsAuthoringControls {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.addButtonTapped)
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add Contributor")
                    }
                }
            }
        }
        .navigationDestination(item: $store.scope(\.destination).contributorDetail) { detailStore in
            ContributorDetailView(
                store: detailStore,
                showsAuthoringControls: showsAuthoringControls
            )
        }
        .accessibilityIdentifier(
            "view.contributors.\(store.eventID.description)"
        )
    }

    func deleteContributors(at offsets: IndexSet) {
        let contributorIDs = offsets.compactMap { offset in
            store.contributorRows.indices.contains(offset)
                ? store.contributorRows[offset].contributorID
                : nil
        }
        store.send(.deleteContributors(contributorIDs))
    }
}

struct ContributorListButton: View {
    let row: ContributorListRow
    let contributorButtonTapped: (Contributor.ID) -> Void

    var body: some View {
        Button {
            contributorButtonTapped(row.contributorID)
        } label: {
            ContributorsRowView(
                name: row.name,
                image: row.artworkDisplayImage,
                stageColors: row.stages.map { stage in
                    stage.color.map { Color(red: Double(($0 >> 16) & 255) / 255,
                                      green: Double(($0 >> 8) & 255) / 255,
                                      blue: Double($0 & 255) / 255) } ?? .secondary
                },
                subtitle: row.subtitle
            )
        }
        .navigationLinkListRowStyle()
        .accessibilityIdentifier(
            "button.contributor.\(row.contributorID.description)"
        )
    }
}

struct ContributorsRowView: View {
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    let name: String
    let image: DisplayImageAsset?
    let stageColors: [Color]
    let subtitle: String?

    init(name: String, image: DisplayImageAsset?, stageColors: [Color], subtitle: String?) {
        self.name = name
        self.image = image
        self.stageColors = stageColors
        self.subtitle = subtitle
    }

    init(
        profile: ContributorProfile,
        stageContext: ContributorStageContext? = nil,
        subtitle: String? = nil
    ) {
        self.init(name: profile.name, image: profile.artworkDisplayImage,
                  stageColors: stageContext?.stages.map(\.stageUIColor) ?? [],
                  subtitle: subtitle ?? profile.subtitle)
    }

    init(
        contributor: Contributor,
        stageContext: ContributorStageContext? = nil,
        subtitle: String? = nil
    ) {
        self.init(profile: ContributorProfile(contributor: contributor),
                  stageContext: stageContext, subtitle: subtitle)
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack {
                ContributorArtworkView(
                    image: image,
                    size: 60
                )

                if needsStageDisambiguation {
                    Group {
                        if !stageColors.isEmpty {
                            ContributorStageIndicatorView(
                                colors: stageColors
                            )
                        } else {
                            Rectangle()
                                .fill(Color.clear)
                        }
                    }
                    .frame(width: 5, height: 60)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
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

