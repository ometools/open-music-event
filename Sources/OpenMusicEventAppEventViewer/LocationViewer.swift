import ComposableArchitecture2
import Dependencies
import Foundation
import SQLiteData
import SwiftUI

#if canImport(MapKit)
import MapKit
#endif

@Feature
public struct LocationViewer {
    public init() {}

    public struct State {
        public let eventID: OMERecord.Event.ID
        @FetchOne public var event: OMERecord.Event?
        public var destination: Destination.State?

        public init(
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            _event = FetchOne(
                OMERecord.Event.where { $0.id.eq(eventID) }
            )
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case editButtonTapped
    }

    @Feature
    public enum Destination {
        case editLocation(Spawn<EditLocation>)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case .editButtonTapped:
                store.withDependencies {
                    state.destination = .editLocation(
                        Spawn(EditLocation.State(eventID: state.eventID))
                    )
                }
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct LocationViewerView: View {
    @Bindable var store: StoreOf<LocationViewer>

    public init(store: StoreOf<LocationViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let locations = store.event?.locations?.displayLocations, !locations.isEmpty {
                List {
                    ForEach(locations.indices, id: \.self) { index in
                        let location = locations[index]
                        Section {
                            #if canImport(MapKit)
                            if let coordinates = location.coordinates {
                                LocationMapView(coordinates: coordinates)
                                    .frame(minHeight: 320)
                                    .listRowInsets(EdgeInsets())
                            }
                            #endif

                            if let address = location.displayAddress {
                                LocationInfoRow(
                                    title: "Address",
                                    value: address,
                                    systemImage: "mappin.and.ellipse"
                                )
                            }

                            if let coordinates = location.coordinates, location.displayAddress == nil {
                                LocationInfoRow(
                                    title: "Coordinates",
                                    value: coordinates.displayText,
                                    systemImage: "location"
                                )
                            }

                            if let appleMapsURL = location.appleMapsURL {
                                Link(destination: appleMapsURL) {
                                    Label("Apple Maps", systemImage: "location")
                                }
                            }

                            if let googleMapsURL = location.googleMapsURL {
                                Link(destination: googleMapsURL) {
                                    Label("Google Maps", systemImage: "map")
                                }
                            }

                            if let directions = location.displayDirections {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                                        .font(.headline)
                                    Text(directions)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            if locations.count > 1 {
                                Text("Location \(index + 1)")
                            }
                        }
                    }
                }
                .navigationTitle("Location")
            } else {
                ViewerPlaceholderView(
                    title: "Location",
                    systemImage: "mappin.and.ellipse",
                    description: store.event == nil
                        ? "This event could not be loaded."
                        : "No locations have been added to this event yet."
                )
            }
        }
        .toolbar {
            if store.event != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        store.send(.editButtonTapped)
                    }
                }
            }
        }
        .sheet(item: $store.scope(state: \.destination, action: \.destination).editLocation) { editStore in
            NavigationStack {
                EditLocationView(store: editStore)
            }
        }
    }
}

struct LocationInfoRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(value)
                    .foregroundStyle(.secondary)
                    #if !os(Android)
                    .textSelection(.enabled)
                    #endif
            }
        }
        .padding(.vertical, 4)
    }
}

@Feature
public struct EditLocation {
    public init() {}

    public struct State {
        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
        }

        let eventID: OMERecord.Event.ID
        var draft: OMERecord.Event.Draft = .placeholder
        var locations: [EditableLocation] = []
        var hasLoadedDraft = false
        var isSaving = false
        var errorMessage: String?

        var preparedLocations: [OMERecord.Event.Location] {
            locations.compactMap(\.preparedLocation)
        }

        var validationMessage: String? {
            guard hasLoadedDraft else { return nil }

            for location in locations {
                if let message = location.validationMessage {
                    return message
                }
            }

            return nil
        }

        var canSubmit: Bool {
            hasLoadedDraft && !isSaving && validationMessage == nil
        }

        var preparedDraft: OMERecord.Event.Draft {
            var draft = draft
            let locations = preparedLocations
            draft.locations = locations.isEmpty ? nil : locations
            return draft
        }
    }

    public enum Action {
        case addLocationButtonTapped
        case cancelButtonTapped
        case removeLocationButtonTapped(UUID)
        case saveButtonTapped
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addLocationButtonTapped:
                state.locations.append(EditableLocation())

            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .removeLocationButtonTapped(let id):
                state.locations.removeAll { $0.id == id }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This event could not be loaded."
                    return
                }

                guard let validationMessage = state.validationMessage else {
                    state.errorMessage = nil
                    state.isSaving = true
                    let draft = state.preparedDraft

                    store.addTask {
                        do {
                            try database.write { db in
                                try OMERecord.Event.upsert {
                                    draft
                                }
                                .execute(db)
                            }
                            try store.modify {
                                $0.errorMessage = nil
                                $0.isSaving = false
                            }
                            try store.dismiss()
                        } catch {
                            try store.modify {
                                $0.errorMessage = "Unable to save location."
                                $0.isSaving = false
                            }
                        }
                    }
                    return
                }

                state.errorMessage = validationMessage
            }
        }
        .onMount { state in
            guard !state.hasLoadedDraft else { return }

            do {
                if let event = try database.read({ db in
                    try OMERecord.Event.where { $0.id.eq(state.eventID) }.fetchOne(db)
                }) {
                    state.draft = .init(event)
                    state.locations = (event.locations ?? []).map(EditableLocation.init)
                    state.hasLoadedDraft = true
                    state.errorMessage = nil
                } else {
                    state.errorMessage = "This event could not be loaded."
                }
            } catch {
                state.errorMessage = "This event could not be loaded."
            }
        }
    }
}

public struct EditLocationView: View {
    @Bindable var store: StoreOf<EditLocation>

    public init(store: StoreOf<EditLocation>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasLoadedDraft {
                Form {
                    ForEach($store.locations) { $location in
                        Section {
                            TextField("Address", text: $location.address, axis: .vertical)
                                .lineLimit(2...4)

                            TextField("Directions", text: $location.directions, axis: .vertical)
                                .lineLimit(2...6)

                            Toggle("Coordinates", isOn: $location.hasCoordinates.animation())

                            if location.hasCoordinates {
                                TextField("Latitude", text: $location.latitude)
                                    #if os(iOS)
                                    .keyboardType(.decimalPad)
                                    #endif
                                TextField("Longitude", text: $location.longitude)
                                    #if os(iOS)
                                    .keyboardType(.decimalPad)
                                    #endif
                            }

                            TextField("Apple Maps Link", text: $location.appleMapsLink)
                                #if os(iOS)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif
                            TextField("Google Maps Link", text: $location.googleMapsLink)
                                #if os(iOS)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif

                            Button("Remove Location", role: .destructive) {
                                store.send(.removeLocationButtonTapped(location.id))
                            }
                        }
                    }

                    Section {
                        Button("Add Location") {
                            store.send(.addLocationButtonTapped)
                        }
                    }

                    if let errorMessage = store.errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            } else {
                ViewerPlaceholderView(
                    title: "Edit Location",
                    systemImage: "mappin.and.ellipse",
                    description: "This event could not be loaded."
                )
            }
        }
        .disabled(store.isSaving)
        .navigationTitle("Edit Location")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    store.send(.cancelButtonTapped)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if store.isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.canSubmit)
                }
            }
        }
    }
}

#if canImport(MapKit)
struct LocationMapView: View {
    let coordinates: OMERecord.Event.Location.Coordinates

    var body: some View {
        let coordinate = CLLocationCoordinate2D(
            latitude: coordinates.latitude,
            longitude: coordinates.longitude
        )
        Map(
            initialPosition: .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                )
            )
        ) {
            Marker("Location", coordinate: coordinate)
        }
    }
}
#endif

public struct EditableLocation: Identifiable, Equatable {
    public var id = UUID()
    var address = ""
    var directions = ""
    var hasCoordinates = false
    var latitude = ""
    var longitude = ""
    var appleMapsLink = ""
    var googleMapsLink = ""

    init() {}

    init(_ location: OMERecord.Event.Location) {
        self.address = location.address ?? ""
        self.directions = location.directions ?? ""
        if let coordinates = location.coordinates {
            self.hasCoordinates = true
            self.latitude = "\(coordinates.latitude)"
            self.longitude = "\(coordinates.longitude)"
        }
        self.appleMapsLink = location.appleMapsLink?.absoluteString ?? ""
        self.googleMapsLink = location.googleMapsLink?.absoluteString ?? ""
    }

    var validationMessage: String? {
        if hasCoordinates {
            guard parsedLatitude != nil, parsedLongitude != nil else {
                return "Enter valid latitude and longitude values."
            }
        }

        if !trimmedAppleMapsLink.isEmpty, URL(string: trimmedAppleMapsLink) == nil {
            return "Enter a valid Apple Maps link."
        }

        if !trimmedGoogleMapsLink.isEmpty, URL(string: trimmedGoogleMapsLink) == nil {
            return "Enter a valid Google Maps link."
        }

        return nil
    }

    var preparedLocation: OMERecord.Event.Location? {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let directions = directions.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let coordinates = preparedCoordinates
        let appleMapsLink = trimmedAppleMapsLink.nilIfEmpty.flatMap { URL(string: $0) }
        let googleMapsLink = trimmedGoogleMapsLink.nilIfEmpty.flatMap { URL(string: $0) }

        guard address != nil
            || directions != nil
            || coordinates != nil
            || appleMapsLink != nil
            || googleMapsLink != nil
        else { return nil }

        return OMERecord.Event.Location(
            address: address,
            directions: directions,
            coordinates: coordinates,
            appleMapsLink: appleMapsLink,
            googleMapsLink: googleMapsLink
        )
    }

    private var preparedCoordinates: OMERecord.Event.Location.Coordinates? {
        guard hasCoordinates, let latitude = parsedLatitude, let longitude = parsedLongitude else {
            return nil
        }

        return OMERecord.Event.Location.Coordinates(latitude: latitude, longitude: longitude)
    }

    private var parsedLatitude: Double? {
        guard let latitude = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              (-90...90).contains(latitude)
        else { return nil }
        return latitude
    }

    private var parsedLongitude: Double? {
        guard let longitude = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              (-180...180).contains(longitude)
        else { return nil }
        return longitude
    }

    private var trimmedAppleMapsLink: String {
        appleMapsLink.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedGoogleMapsLink: String {
        googleMapsLink.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Array where Element == OMERecord.Event.Location {
    var displayLocations: Self {
        filter(\.hasDisplayContent)
    }
}

private extension OMERecord.Event.Location {
    var hasDisplayContent: Bool {
        displayAddress != nil
            || displayDirections != nil
            || coordinates != nil
            || appleMapsLink != nil
            || googleMapsLink != nil
    }

    var displayAddress: String? {
        let address = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        return address?.isEmpty == false ? address : nil
    }

    var displayDirections: String? {
        let directions = directions?.trimmingCharacters(in: .whitespacesAndNewlines)
        return directions?.isEmpty == false ? directions : nil
    }

    var appleMapsURL: URL? {
        if let appleMapsLink {
            return appleMapsLink
        }

        if let coordinates {
            return URL(string: "http://maps.apple.com/?daddr=\(coordinates.latitude),\(coordinates.longitude)")
        }

        return displayAddress.flatMap { address in
            var components = URLComponents(string: "http://maps.apple.com/")
            components?.queryItems = [
                URLQueryItem(name: "daddr", value: address)
            ]
            return components?.url
        }
    }

    var googleMapsURL: URL? {
        if let googleMapsLink {
            return googleMapsLink
        }

        if let coordinates {
            return URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(coordinates.latitude),\(coordinates.longitude)")
        }

        return displayAddress.flatMap { address in
            var components = URLComponents(string: "https://www.google.com/maps/dir/")
            components?.queryItems = [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "destination", value: address),
            ]
            return components?.url
        }
    }
}

private extension OMERecord.Event.Draft {
    static var placeholder: Self {
        .init(
            id: .init(
                organizerID: OMERecord.Organizer.ID("did:web:example.com")!,
                eventID: .init("-1")
            ),
            name: "",
            description: nil,
            startDate: nil,
            endDate: nil,
            status: nil,
            mode: nil,
            locations: nil,
            uris: nil,
            timeZone: TimeZone.current,
            imageURL: nil,
            iconImageURL: nil,
            siteMapImageURL: nil,
            contactNumbers: nil,
            categoryConfigs: nil
        )
    }
}

private extension OMERecord.Event.Location.Coordinates {
    var displayText: String {
        "\(latitude), \(longitude)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
