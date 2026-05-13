import ComposableArchitecture2
import Dependencies
import Foundation
import SQLiteData
import SwiftUI
import Tagged

@Feature
public struct StagesViewer {
    public init() {}

    public struct State {
        public init(
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil,
            database: (any DatabaseReader)? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            _stages = FetchAll(
                StagesViewer.stagesQuery(eventID: eventID),
                database: database
            )
        }

        public let eventID: OMERecord.Event.ID
        public var destination: Destination.State?
        public var searchText = ""

        @FetchAll public var stages: [OMERecord.Stage]

        public var filteredStages: [OMERecord.Stage] {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return stages }

            return stages.filter { stage in
                stage.name.localizedStandardContains(query)
                    || stage.category?.rawValue.localizedStandardContains(query) == true
            }
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case stageButtonTapped(OMERecord.ID<OMERecord.Stage>)
    }

    @Feature
    public enum Destination {
        case stageDetail(Spawn<StageDetail>)
    }

    static func stagesQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Stage> {
        OMERecord.Stage
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { ($0.sortIndex.asc(nulls: .last), $0.name.collate(.nocase)) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case let .stageButtonTapped(stageID):
                state.destination = .stageDetail(
                    Spawn(.init(stageID: stageID, eventID: state.eventID))
                )
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct StagesViewerView: View {
    @Bindable var store: StoreOf<StagesViewer>

    public init(store: StoreOf<StagesViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.stages.isEmpty {
                ViewerPlaceholderView(
                    title: "Stages",
                    systemImage: "square.grid.2x2",
                    description: "No stages have been added to this event yet."
                )
            } else if store.filteredStages.isEmpty {
                ViewerPlaceholderView(
                    title: "No Results",
                    systemImage: "square.grid.2x2",
                    description: "No stages match your search."
                )
            } else {
                List(store.filteredStages) { stage in
                    Button {
                        store.send(.stageButtonTapped(stage.id.stageID))
                    } label: {
                        StageRowView(stage: stage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $store.searchText, prompt: "Search Stages")
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .navigationTitle("Stages")
        .navigationDestination(item: $store.scope(state: \.destination, action: \.destination).stageDetail) { detailStore in
            StageDetailView(store: detailStore)
        }
    }
}

@Feature
public struct StageDetail {
    public init() {}

    public struct State: Identifiable {
        public let stageID: OMERecord.ID<OMERecord.Stage>
        public let eventID: OMERecord.Event.ID

        @FetchOne public var stage: OMERecord.Stage?
        @FetchAll public var participants: [OMERecord.Participant]

        public init(
            stageID: OMERecord.ID<OMERecord.Stage>,
            eventID: OMERecord.Event.ID? = nil,
            database: (any DatabaseReader)? = nil
        ) {
            @Dependency(\.defaultEventID) var defaultEventID

            self.stageID = stageID
            self.eventID = eventID ?? defaultEventID
            _stage = FetchOne(
                StageDetail.stageQuery(
                    stageID: stageID,
                    eventID: self.eventID
                ),
                database: database
            )
            _participants = FetchAll(
                PeopleViewer.participantsQuery(eventID: self.eventID),
                database: database
            )
        }

        public var id: OMERecord.ID<OMERecord.Stage> { stageID }

        public var lineupParticipants: [OMERecord.Participant] {
            guard let lineup = stage?.lineup, !lineup.isEmpty else { return [] }
            let participantsByID = Dictionary(
                uniqueKeysWithValues: participants.map { ($0.id.participantID, $0) }
            )
            return lineup.compactMap { participantsByID[$0] }
        }
    }

    public enum Action {}

    static func stageQuery(
        stageID: OMERecord.ID<OMERecord.Stage>,
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Stage> {
        OMERecord.Stage
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.id.stageID.eq(stageID) }
    }

    public var body: some Feature {
        Update { _, _ in }
    }
}

public struct StageDetailView: View {
    @Bindable var store: StoreOf<StageDetail>

    public init(store: StoreOf<StageDetail>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let stage = store.stage {
                List {
                    StageHeaderView(stage: stage)

                    if stage.hasDisplayDetails {
                        Section("Details") {
                            if let category = stage.category?.displayName {
                                LabeledContent("Category", value: category)
                            }

                            if let sortIndex = stage.sortIndex {
                                LabeledContent("Sort Index", value: sortIndex.formatted())
                            }
                        }
                    }

                    if !store.lineupParticipants.isEmpty {
                        Section("Lineup") {
                            ForEach(store.lineupParticipants) { participant in
                                PeopleRowView(participant: participant)
                            }
                        }
                    }
                }
                .navigationTitle(stage.name)
            } else {
                ContentUnavailableView(
                    "Stage",
                    systemImage: "square.grid.2x2",
                    description: Text(verbatim: store.stageID.rawValue.rawValue)
                )
                .navigationTitle("Stage")
            }
        }
    }
}

struct StageRowView: View {
    let stage: OMERecord.Stage

    var body: some View {
        HStack(spacing: 12) {
            StageArtworkView(stage: stage, size: 60)

            VStack(alignment: .leading, spacing: 3) {
                Text(stage.name)
                    .lineLimit(1)

                if let category = stage.category?.displayName {
                    Text(category)
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

struct StageHeaderView: View {
    let stage: OMERecord.Stage

    var body: some View {
        HStack(spacing: 14) {
            StageArtworkView(stage: stage, size: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(stage.name)
                    .font(.headline)
                    .lineLimit(2)

                if let category = stage.category?.displayName {
                    Text(category)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

struct StageArtworkView: View {
    let stage: OMERecord.Stage
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(stage.color.swiftUIColor.opacity(0.18))

            ImageAssetAsyncImage(
                asset: stage.images?.imageAsset(role: .logo),
                contentMode: .fit
            ) {
                StageIconFallback(stage: stage, size: size)
            }
            .foregroundStyle(stage.color.swiftUIColor)
            .padding(10)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct StageIconFallback: View {
    let stage: OMERecord.Stage
    let size: CGFloat

    var body: some View {
        if let systemIconName = stage.systemIconName {
            Image(systemName: systemIconName)
                .font(.system(size: size * 0.42, weight: .semibold))
        } else if let iconShortCode = stage.iconShortCode {
            Text(iconShortCode)
                .font(.system(size: size * 0.36, weight: .heavy))
                .lineLimit(1)
                #if os(iOS)
                .minimumScaleFactor(0.2)
                #endif
        } else {
            Text(stage.initials)
                .font(.system(size: size * 0.36, weight: .heavy))
                .lineLimit(1)
                #if os(iOS)
                .minimumScaleFactor(0.2)
                #endif
        }
    }
}

private extension OMERecord.Stage {
    var hasDisplayDetails: Bool {
        category?.displayName != nil || sortIndex != nil
    }

    var initials: String {
        let initials = name
            .split(separator: " ")
            .filter { !$0.localizedCaseInsensitiveContains("the") }
            .compactMap(\.first)
            .prefix(2)
            .map(String.init)
            .joined()
        return initials.isEmpty ? "?" : initials
    }
}

private extension OMERecord.Stage.Category {
    var displayName: String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value.scheduleDivisionTitle
    }
}

private extension String {
    var scheduleDivisionTitle: String {
        split { $0 == "-" || $0 == "_" || $0 == " " }
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
