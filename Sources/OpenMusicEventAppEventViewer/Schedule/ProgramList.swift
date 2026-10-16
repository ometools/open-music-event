import ComposableArchitecture2
import Dependencies
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import Sharing
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct ProgramList {
    public init() {}

    public struct State: Identifiable {
        public init(eventID: Event.ID) {
            self.eventID = eventID
            _event = FetchOne(Event.where { $0.id.eq(eventID) })
            _programs = FetchAll(Program.where { $0.event.eq(eventID) })
            _places = FetchAll(EventPlace.where { $0.event.eq(eventID) })
        }

        public let eventID: Event.ID
        public var id: Event.ID { eventID }
        @FetchOne public var event: Event?
        @FetchAll public var programs: [Program]
        @FetchAll public var places: [EventPlace]
        public var destination: Destination.State?
        public var errorMessage: String?

        public var orderedPrograms: [Program] {
            let byID = Dictionary(uniqueKeysWithValues: programs.map { ($0.id, $0) })
            return (event?.programs ?? []).compactMap { byID[$0] }
        }
    }

    public enum Action {
        case addButtonTapped
        case editButtonTapped(Program.ID)
        case deleteButtonTapped(Program.ID)
        case moveButtonTapped(Program.ID, Int)
        case destination(Destination.Action)
    }

    @Feature
    public enum Destination {
        case editor(Spawn<ProgramForm>)
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addButtonTapped:
                guard state.event != nil else { return }
                state.destination = .editor(Spawn(ProgramForm.State(
                    eventID: state.eventID,
                    places: state.places
                )))

            case let .editButtonTapped(id):
                guard let program = state.orderedPrograms.first(where: { $0.id == id }) else { return }
                state.destination = .editor(Spawn(ProgramForm.State(
                    eventID: state.eventID,
                    program: program,
                    places: state.places
                )))

            case let .deleteButtonTapped(id):
                guard state.orderedPrograms.contains(where: { $0.id == id }) else { return }
                let eventID = state.eventID
                state.errorMessage = nil
                store.addTask {
                    do {
                        try await database.write { db in
                            try ProgramRecordEditing.delete(id, eventID: eventID, in: db)
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = (error as? ProgramRecordEditing.Error) == .programInUse
                                ? "Move or delete this program's items before deleting it."
                                : "Unable to delete program."
                        }
                    }
                }

            case let .moveButtonTapped(id, offset):
                guard let index = state.orderedPrograms.firstIndex(where: { $0.id == id }),
                      state.orderedPrograms.indices.contains(index + offset) else { return }
                let eventID = state.eventID
                store.addTask {
                    do {
                        try await database.write { db in
                            guard var event = try Event.find(eventID).fetchOne(db),
                                  var programs = event.programs,
                                  let index = programs.firstIndex(of: id),
                                  programs.indices.contains(index + offset) else { return }
                            programs.swapAt(index, index + offset)
                            event.programs = programs
                            try event.validateReferences()
                            try Event.upsert { event }.execute(db)
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to reorder programs."
                        }
                    }
                }

            case .destination:
                break
            }
        }
        .ifLet(\.destination) { Destination.body }
    }
}

public struct ProgramListView: View {
    @State var programPendingDeletion: Program.ID?
    @Bindable var store: StoreOf<ProgramList>

    public init(store: StoreOf<ProgramList>) {
        self.store = store
    }

    public var body: some View {
        List {
            if let errorMessage = store.errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            if store.state.orderedPrograms.isEmpty {
                ContentUnavailableView {
                    Label("No Programs", mappedSystemImage: "calendar")
                } description: {
                    Text("Add a program to organize performances and places.")
                } actions: {
                    Button("Add Program") { store.send(.addButtonTapped) }
                        .buttonStyle(.borderedProminent)
                }
            }
            ForEach(store.state.orderedPrograms) { program in
                HStack {
                    Button {
                        store.send(.editButtonTapped(program.id))
                    } label: {
                        VStack(alignment: .leading) {
                            Text(program.title)
                            if let description = program.description, !description.isEmpty {
                                Text(description).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Menu {
                        Button("Edit") { store.send(.editButtonTapped(program.id)) }
                        Button("Move Up") { store.send(.moveButtonTapped(program.id, -1)) }
                        Button("Move Down") { store.send(.moveButtonTapped(program.id, 1)) }
                        Button("Delete", role: .destructive) {
                            programPendingDeletion = program.id
                        }
                    } label: {
                        Label("Program actions", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityIdentifier("button.program-actions.\(program.id)")
                }
            }
        }
        .navigationTitle("Programs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.send(.addButtonTapped)
                } label: {
                    Label("Add Program", systemImage: "plus")
                }
            }
        }
        .navigationDestination(item: $store.scope(\.destination).editor) { editorStore in
            ProgramFormView(store: editorStore)
        }
        .confirmationDialog(
            "Delete Program?",
            isPresented: Binding(
                get: { programPendingDeletion != nil },
                set: { if !$0 { programPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let programID = programPendingDeletion {
                Button("Delete Program", role: .destructive) {
                    store.send(.deleteButtonTapped(programID))
                    programPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { programPendingDeletion = nil }
        } message: {
            Text("Move or delete this program's items first.")
        }
    }
}
