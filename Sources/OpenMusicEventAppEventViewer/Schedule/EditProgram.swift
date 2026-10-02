import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct EditProgram {
    public init() {}

    public struct State: Identifiable {
        public init(eventID: Event.ID, program: Program? = nil, places: [EventPlace]) {
            self.eventID = eventID
            self.programID = program?.id
            self.title = program?.title ?? ""
            self.description = program?.description ?? ""
            self.iconName = program?.icon?.rawValue ?? ""
            self.places = places
            self.selectedPlaceIDs = program?.eventPlaces ?? places.map(\.id)
        }

        public let eventID: Event.ID
        public let programID: Program.ID?
        public let places: [EventPlace]
        public var title: String
        public var description: String
        public var iconName: String
        public var selectedPlaceIDs: [EventPlace.ID]
        public var errorMessage: String?
        public var isSaving = false

        public var id: Program.ID { programID ?? eventID }
        public var canSave: Bool {
            !isSaving && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        public var availablePlaces: [EventPlace] {
            places.filter { !selectedPlaceIDs.contains($0.id) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        public func place(_ id: EventPlace.ID) -> EventPlace? {
            places.first { $0.id == id }
        }
    }

    public enum Action {
        case addPlaceButtonTapped(EventPlace.ID)
        case movePlaceButtonTapped(EventPlace.ID, Int)
        case removePlaceButtonTapped(EventPlace.ID)
        case saveButtonTapped
        case deleteButtonTapped
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now

    public var body: some Feature {
        Update { state, action in
            switch action {
            case let .addPlaceButtonTapped(id):
                guard state.place(id) != nil, !state.selectedPlaceIDs.contains(id) else { return }
                state.selectedPlaceIDs.append(id)

            case let .movePlaceButtonTapped(id, offset):
                guard let index = state.selectedPlaceIDs.firstIndex(of: id),
                      state.selectedPlaceIDs.indices.contains(index + offset) else { return }
                state.selectedPlaceIDs.swapAt(index, index + offset)

            case let .removePlaceButtonTapped(id):
                state.selectedPlaceIDs.removeAll { $0 == id }

            case .saveButtonTapped:
                guard state.canSave else { return }
                let eventID = state.eventID
                let programID = state.programID
                let title = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let description = state.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let iconName = state.iconName.trimmingCharacters(in: .whitespacesAndNewlines)
                let selectedPlaceIDs = state.selectedPlaceIDs
                let createdAt = now
                state.errorMessage = nil
                state.isSaving = true
                store.addTask {
                    do {
                        try await database.write { db in
                            let icon = iconName.isEmpty ? nil : OME.SemanticIcon(rawValue: iconName)
                            if let programID {
                                try ProgramRecordEditing.update(
                                    programID,
                                    eventID: eventID,
                                    title: title,
                                    description: description.isEmpty ? nil : description,
                                    icon: icon,
                                    eventPlaces: selectedPlaceIDs,
                                    in: db
                                )
                            } else {
                                _ = try ProgramRecordEditing.create(
                                    eventID: eventID,
                                    title: title,
                                    description: description.isEmpty ? nil : description,
                                    icon: icon,
                                    eventPlaces: selectedPlaceIDs,
                                    createdAt: createdAt,
                                    in: db
                                )
                            }
                        }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = (error as? ProgramRecordEditing.Error) == .placeInUse
                                ? "Move or delete items at this place before removing it from the program."
                                : "Unable to save program."
                            $0.isSaving = false
                        }
                    }
                }

            case .deleteButtonTapped:
                guard !state.isSaving, let programID = state.programID else { return }
                let eventID = state.eventID
                state.errorMessage = nil
                state.isSaving = true
                store.addTask {
                    do {
                        try await database.write { db in
                            try ProgramRecordEditing.delete(programID, eventID: eventID, in: db)
                        }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = (error as? ProgramRecordEditing.Error) == .programInUse
                                ? "Move or delete this program's items before deleting it."
                                : "Unable to delete program."
                            $0.isSaving = false
                        }
                    }
                }
            }
        }
    }
}

public struct EditProgramView: View {
    @Environment(\.dismiss) var dismiss
    @State var isDeleteConfirmationPresented = false
    @Bindable var store: StoreOf<EditProgram>

    public init(store: StoreOf<EditProgram>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Program") {
                TextField("Title", text: $store.title)
                PortableTextField("Description", text: $store.description, axis: .vertical)
                TextField("Icon name", text: $store.iconName)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            }

            Section("Places in display order") {
                ForEach(store.selectedPlaceIDs, id: \.self) { id in
                    if let place = store.state.place(id) {
                        HStack {
                            Text(place.name)
                            Spacer()
                            Menu {
                                Button("Move Up") { store.send(.movePlaceButtonTapped(id, -1)) }
                                Button("Move Down") { store.send(.movePlaceButtonTapped(id, 1)) }
                                Button("Remove", role: .destructive) {
                                    store.send(.removePlaceButtonTapped(id))
                                }
                            } label: {
                                Label("Place actions", systemImage: "ellipsis.circle")
                                    .labelStyle(.iconOnly)
                            }
                        }
                    }
                }
                if !store.state.availablePlaces.isEmpty {
                    Menu {
                        ForEach(store.state.availablePlaces) { place in
                            Button(place.name) { store.send(.addPlaceButtonTapped(place.id)) }
                        }
                    } label: {
                        Label("Add Place", systemImage: "plus")
                    }
                }
            }

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .disabled(store.isSaving)
        .navigationTitle(store.programID == nil ? "New Program" : "Edit Program")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                SubmitButton(isInProgress: store.isSaving, isDisabled: !store.canSave) {
                    store.send(.saveButtonTapped)
                }
            }
            if store.programID != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Delete Program", role: .destructive) {
                            isDeleteConfirmationPresented = true
                        }
                    } label: {
                        Label("Program actions", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .confirmationDialog("Delete Program?", isPresented: $isDeleteConfirmationPresented) {
            Button("Delete Program", role: .destructive) { store.send(.deleteButtonTapped) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Move or delete this program's items first.")
        }
    }
}
