import OpenMusicEventLexicon
import ATProtoTypes
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventEditors
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

#if !os(Android) && canImport(MapKit)
import MapKit
#endif

@Feature
public struct LocationViewer {
    public init() {}

    public struct State {
        public let eventID: Event.ID
        @FetchOne public var event: Event?

        public init(eventID: Event.ID) {
            self.eventID = eventID
            _event = FetchOne(Event.where { $0.id.eq(eventID) })
        }
    }

    public enum Action {
        case editButtonTapped
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .editButtonTapped:
                let eventID = state.eventID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .editLocation(eventID)
                    )
                    await task?.value
                }
            }
        }
    }
}

public struct LocationViewerView: View {
    @Bindable var store: StoreOf<LocationViewer>
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<LocationViewer>,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        Group {
            if let locations = store.event?.locations, !locations.isEmpty {
                List {
                    ForEach(locations.indices, id: \.self) { index in
                        let location = locations[index]
                        Section {
                            #if !os(Android) && canImport(MapKit)
                            if let coordinates = location.displayCoordinates {
                                LocationMapView(coordinates: coordinates)
                                    .frame(minHeight: 320)
                                    .listRowInsets(EdgeInsets())
                            }
                            #endif

                            let locators = location.locators ?? []
                            ForEach(locators.indices, id: \.self) { locatorIndex in
                                switch locators[locatorIndex] {
                                case let .known(.address(address)):
                                    LocationInfoRow(
                                        title: "Address",
                                        value: address.displayText,
                                        systemImage: "mappin.and.ellipse"
                                    )
                                case let .known(.geo(geo)):
                                    LocationInfoRow(
                                        title: "Coordinates",
                                        value: "\(geo.latitude), \(geo.longitude)",
                                        systemImage: "location"
                                    )
                                case let .known(.foursquare(place)):
                                    LocationInfoRow(
                                        title: "Foursquare Place",
                                        value: place.fsqPlaceID,
                                        systemImage: "mappin.and.ellipse"
                                    )
                                case let .known(.hthree(cell)):
                                    LocationInfoRow(
                                        title: "H3 Cell",
                                        value: cell.value,
                                        systemImage: "location"
                                    )
                                case .unknown:
                                    EmptyView()
                                }
                            }

                            let links = location.links ?? []
                            ForEach(links.indices, id: \.self) { linkIndex in
                                let link = links[linkIndex]
                                Link(destination: link.url) {
                                    Label(link.title ?? "Open Map", mappedSystemImage: "map")
                                }
                            }

                            if let mapURL = location.mapURL {
                                Link(destination: mapURL) {
                                    #if os(Android)
                                    Label("Open in Google Maps", mappedSystemImage: "map")
                                    #else
                                    Label("Open in Apple Maps", mappedSystemImage: "map")
                                    #endif
                                }
                            }

                            if let details = location.displayDescription {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(
                                        "Details",
                                        mappedSystemImage: "arrow.triangle.turn.up.right.diamond"
                                    )
                                        .font(.headline)
                                    Text(details)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            Text(location.name)
                        }
                    }
                }
                .navigationTitle("Location")
            } else {
                ContentUnavailableView {
                    Label("Location", mappedSystemImage: "mappin.and.ellipse")
                } description: {
                    if store.event == nil {
                        Text("This event could not be loaded.")
                    } else if showsAuthoringControls {
                        Text("Add a location so attendees know where to go.")
                    } else {
                        Text("No locations have been added to this event yet.")
                    }
                } actions: {
                    if showsAuthoringControls, store.event != nil {
                        Button("Add Location") { store.send(.editButtonTapped) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .navigationTitle("Location")
            }
        }
        .toolbar {
            if showsAuthoringControls, store.event != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.editButtonTapped)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .labelStyle(.iconOnly)
                    }
                }
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
            MappedSystemImage(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)


            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(value)
                    .foregroundStyle(.secondary)
                    #if !os(Android)
                    .selectableText()
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
        public init(eventID: Event.ID) {
            self.eventID = eventID
        }

        let eventID: Event.ID
        var event: Event?
        var locations: [EditableLocation] = []
        var editingLocationID: EditableLocation.ID?
        var editingLocatorID: EditableLocator.ID?
        var editingLinkID: EditableLink.ID?
        var hasLoadedDraft = false
        var isSaving = false
        var errorMessage: String?

        var preparedLocations: [Event.Location] {
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

    }

    public enum Action {
        case addLocationButtonTapped
        case addLocatorButtonTapped(UUID, EditableLocator.Kind)
        case addLinkButtonTapped(UUID)
        case cancelButtonTapped
        case editLocationButtonTapped(UUID)
        case editLocatorButtonTapped(UUID, UUID)
        case editLinkButtonTapped(UUID, UUID)
        case moveLocationButtonTapped(UUID, Int)
        case moveLocatorButtonTapped(UUID, UUID, Int)
        case moveLinkButtonTapped(UUID, UUID, Int)
        case removeLocationButtonTapped(UUID)
        case removeLocatorButtonTapped(UUID, UUID)
        case removeLinkButtonTapped(UUID, UUID)
        case saveButtonTapped
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addLocationButtonTapped:
                let location = EditableLocation()
                state.locations.append(location)
                state.editingLocationID = location.id
                state.editingLocatorID = nil
                state.editingLinkID = nil

            case let .addLocatorButtonTapped(locationID, kind):
                guard let index = state.locations.firstIndex(where: { $0.id == locationID }) else { return }
                let locator = EditableLocator(kind: kind)
                state.locations[index].locators.append(locator)
                state.editingLocationID = locationID
                state.editingLocatorID = locator.id
                state.editingLinkID = nil

            case let .addLinkButtonTapped(locationID):
                guard let index = state.locations.firstIndex(where: { $0.id == locationID }) else { return }
                let link = EditableLink()
                state.locations[index].links.append(link)
                state.editingLocationID = locationID
                state.editingLocatorID = nil
                state.editingLinkID = link.id

            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case let .editLocationButtonTapped(id):
                guard state.locations.contains(where: { $0.id == id }) else { return }
                state.editingLocationID = id
                state.editingLocatorID = nil
                state.editingLinkID = nil

            case let .editLocatorButtonTapped(locationID, locatorID):
                guard let location = state.locations.first(where: { $0.id == locationID }),
                      location.locators.contains(where: { $0.id == locatorID }) else { return }
                state.editingLocationID = locationID
                state.editingLocatorID = locatorID
                state.editingLinkID = nil

            case let .editLinkButtonTapped(locationID, linkID):
                guard let location = state.locations.first(where: { $0.id == locationID }),
                      location.links.contains(where: { $0.id == linkID }) else { return }
                state.editingLocationID = locationID
                state.editingLocatorID = nil
                state.editingLinkID = linkID

            case let .moveLocationButtonTapped(id, offset):
                guard let index = state.locations.firstIndex(where: { $0.id == id }),
                      state.locations.indices.contains(index + offset) else { return }
                state.locations.swapAt(index, index + offset)

            case let .moveLocatorButtonTapped(locationID, locatorID, offset):
                guard let locationIndex = state.locations.firstIndex(where: { $0.id == locationID }),
                      let index = state.locations[locationIndex].locators.firstIndex(where: { $0.id == locatorID }),
                      state.locations[locationIndex].locators.indices.contains(index + offset) else { return }
                state.locations[locationIndex].locators.swapAt(index, index + offset)

            case let .moveLinkButtonTapped(locationID, linkID, offset):
                guard let locationIndex = state.locations.firstIndex(where: { $0.id == locationID }),
                      let index = state.locations[locationIndex].links.firstIndex(where: { $0.id == linkID }),
                      state.locations[locationIndex].links.indices.contains(index + offset) else { return }
                state.locations[locationIndex].links.swapAt(index, index + offset)

            case .removeLocationButtonTapped(let id):
                state.locations.removeAll { $0.id == id }
                if state.editingLocationID == id {
                    state.editingLocationID = nil
                    state.editingLocatorID = nil
                    state.editingLinkID = nil
                }

            case let .removeLocatorButtonTapped(locationID, locatorID):
                guard let index = state.locations.firstIndex(where: { $0.id == locationID }) else { return }
                state.locations[index].locators.removeAll { $0.id == locatorID }
                if state.editingLocatorID == locatorID { state.editingLocatorID = nil }

            case let .removeLinkButtonTapped(locationID, linkID):
                guard let index = state.locations.firstIndex(where: { $0.id == locationID }) else { return }
                state.locations[index].links.removeAll { $0.id == linkID }
                if state.editingLinkID == linkID { state.editingLinkID = nil }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This event could not be loaded."
                    return
                }

                guard let validationMessage = state.validationMessage else {
                    guard let original = state.event else {
                        state.errorMessage = "This event could not be loaded."
                        return
                    }
                    let locations = state.preparedLocations
                    state.errorMessage = nil
                    state.isSaving = true

                    store.addTask {
                        do {
                            try database.write { db in
                                guard var current = try Event.find(original.id).fetchOne(db),
                                      current.locations == original.locations else {
                                    throw LocationChangedError()
                                }
                                current.locations = locations.isEmpty ? nil : locations
                                try current.validateReferences()
                                try Event.upsert { current }.execute(db)
                            }
                            try store.modify {
                                $0.errorMessage = nil
                                $0.isSaving = false
                            }
                            try store.dismiss()
                        } catch is LocationChangedError {
                            try store.modify {
                                $0.errorMessage = "Locations changed. Reopen the editor to see the latest values."
                                $0.isSaving = false
                            }
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
                    try Event.where { $0.id.eq(state.eventID) }.fetchOne(db)
                }) {
                    state.event = event
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

private struct LocationChangedError: Error {}

public struct EditLocationView: View {
    @Bindable var store: StoreOf<EditLocation>

    public init(store: StoreOf<EditLocation>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasLoadedDraft {
                Form {
                    EditLocationListSection(store: store)
                    if let index = store.locations.firstIndex(where: { $0.id == store.editingLocationID }) {
                        EditLocationDetailSections(store: store, locationIndex: index)
                    }

                    if let errorMessage = store.errorMessage ?? store.validationMessage {
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
                Button {
                    store.send(.cancelButtonTapped)
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                SubmitButton(
                    isInProgress: store.isSaving,
                    isDisabled: !store.canSubmit
                ) {
                    store.send(.saveButtonTapped)
                }
            }
        }
    }
}

struct EditLocationListSection: View {
    @Bindable var store: StoreOf<EditLocation>

    var body: some View {
        Section("Locations") {
            ForEach(store.locations) { location in
                HStack {
                    Text(location.name.isEmpty ? "New Location" : location.name)
                    Spacer()
                    Menu {
                        Button("Edit") { store.send(.editLocationButtonTapped(location.id)) }
                        Button("Move Up") { store.send(.moveLocationButtonTapped(location.id, -1)) }
                            .disabled(store.locations.first?.id == location.id)
                        Button("Move Down") { store.send(.moveLocationButtonTapped(location.id, 1)) }
                            .disabled(store.locations.last?.id == location.id)
                        Button("Delete", role: .destructive) {
                            store.send(.removeLocationButtonTapped(location.id))
                        }
                    } label: {
                        Label("Location Actions", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            Button("Add Location") { store.send(.addLocationButtonTapped) }
        }
    }
}

struct EditLocationDetailSections: View {
    @Bindable var store: StoreOf<EditLocation>
    let locationIndex: Int

    var body: some View {
        Section("Edit Location") {
            TextField("Name", text: $store.locations[locationIndex].name)
            PortableTextField(
                "Details and directions",
                text: $store.locations[locationIndex].description,
                axis: .vertical
            )
            .portableLineLimit(2...6)
        }
        EditLocationLocatorSections(store: store, locationIndex: locationIndex)
        EditLocationLinkSections(store: store, locationIndex: locationIndex)
    }
}

struct EditLocationLocatorSections: View {
    @Bindable var store: StoreOf<EditLocation>
    let locationIndex: Int

    var body: some View {
        let location = store.locations[locationIndex]
        Section("Locators") {
            ForEach(location.locators) { locator in
                HStack {
                    Text(locator.kind.title)
                    Spacer()
                    Menu {
                        Button("Edit") { store.send(.editLocatorButtonTapped(location.id, locator.id)) }
                        Button("Move Up") { store.send(.moveLocatorButtonTapped(location.id, locator.id, -1)) }
                            .disabled(location.locators.first?.id == locator.id)
                        Button("Move Down") { store.send(.moveLocatorButtonTapped(location.id, locator.id, 1)) }
                            .disabled(location.locators.last?.id == locator.id)
                        Button("Delete", role: .destructive) {
                            store.send(.removeLocatorButtonTapped(location.id, locator.id))
                        }
                    } label: {
                        Label("Locator Actions", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            Menu("Add Locator") {
                Button("Address") { store.send(.addLocatorButtonTapped(location.id, .address)) }
                Button("Coordinates") { store.send(.addLocatorButtonTapped(location.id, .geo)) }
                Button("Foursquare Place") { store.send(.addLocatorButtonTapped(location.id, .foursquare)) }
                Button("H3 Cell") { store.send(.addLocatorButtonTapped(location.id, .hthree)) }
            }
        }
        if let index = location.locators.firstIndex(where: { $0.id == store.editingLocatorID }) {
            Section("Edit Locator") {
                EditableLocatorFields(locator: $store.locations[locationIndex].locators[index])
            }
        }
    }
}

struct EditLocationLinkSections: View {
    @Bindable var store: StoreOf<EditLocation>
    let locationIndex: Int

    var body: some View {
        let location = store.locations[locationIndex]
        Section("Links") {
            ForEach(location.links) { link in
                HStack {
                    Text(link.title.isEmpty ? (link.url.isEmpty ? "New Link" : link.url) : link.title)
                        .lineLimit(1)
                    Spacer()
                    Menu {
                        Button("Edit") { store.send(.editLinkButtonTapped(location.id, link.id)) }
                        Button("Move Up") { store.send(.moveLinkButtonTapped(location.id, link.id, -1)) }
                            .disabled(location.links.first?.id == link.id)
                        Button("Move Down") { store.send(.moveLinkButtonTapped(location.id, link.id, 1)) }
                            .disabled(location.links.last?.id == link.id)
                        Button("Delete", role: .destructive) {
                            store.send(.removeLinkButtonTapped(location.id, link.id))
                        }
                    } label: {
                        Label("Link Actions", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            Button("Add Link") { store.send(.addLinkButtonTapped(location.id)) }
        }
        if let index = location.links.firstIndex(where: { $0.id == store.editingLinkID }) {
            Section("Edit Link") {
                EditLinkFields(link: $store.locations[locationIndex].links[index])
            }
        }
    }
}

#if !os(Android) && canImport(MapKit)
struct LocationMapView: View {
    let coordinates: LocationCoordinates

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

struct LocationCoordinates: Equatable {
    let latitude: Double
    let longitude: Double
}

public struct EditableLocation: Identifiable, Equatable {
    public var id = UUID()
    var original: Event.Location?
    var name = ""
    var description = ""
    var locators: [EditableLocator] = []
    var links: [EditableLink] = []

    init() {}

    init(_ location: Event.Location) {
        original = location
        name = location.name
        description = location.description ?? ""
        locators = (location.locators ?? []).map(EditableLocator.init)
        links = (location.links ?? []).map(EditableLink.init)
    }

    var validationMessage: String? {
        if name.trimmed.isEmpty { return "Enter a location name." }
        return locators.compactMap(\.validationMessage).first
            ?? links.compactMap(\.validationMessage).first
    }

    var preparedLocation: Event.Location? {
        guard validationMessage == nil else { return nil }
        var value = original ?? Event.Location(name: name.trimmed)
        value.name = name.trimmed
        value.description = description.trimmed.nilIfEmpty
        value.locators = locators.isEmpty ? nil : locators.compactMap(\.preparedLocator)
        value.links = links.isEmpty ? nil : links.compactMap(\.preparedLink)
        return value
    }
}

public struct EditableLocator: Identifiable, Equatable {
    public enum Kind: Equatable {
        case address, geo, foursquare, hthree, unknown

        var title: String {
            switch self {
            case .address: "Address"
            case .geo: "Coordinates"
            case .foursquare: "Foursquare Place"
            case .hthree: "H3 Cell"
            case .unknown: "Other Locator"
            }
        }
    }

    public var id = UUID()
    var original: Open<Event.Locator>?
    var kind: Kind
    var name = ""
    var country = ""
    var postalCode = ""
    var region = ""
    var locality = ""
    var street = ""
    var latitude = ""
    var longitude = ""
    var altitude = ""
    var fsqPlaceID = ""
    var hthreeValue = ""

    init(kind: Kind) { self.kind = kind }

    init(_ locator: Open<Event.Locator>) {
        original = locator
        switch locator {
        case let .known(.address(value)):
            kind = .address
            name = value.name ?? ""
            country = value.country
            postalCode = value.postalCode ?? ""
            region = value.region ?? ""
            locality = value.locality ?? ""
            street = value.street ?? ""
        case let .known(.geo(value)):
            kind = .geo
            name = value.name ?? ""
            latitude = value.latitude
            longitude = value.longitude
            altitude = value.altitude ?? ""
        case let .known(.foursquare(value)):
            kind = .foursquare
            name = value.name ?? ""
            fsqPlaceID = value.fsqPlaceID
            latitude = value.latitude ?? ""
            longitude = value.longitude ?? ""
        case let .known(.hthree(value)):
            kind = .hthree
            name = value.name ?? ""
            hthreeValue = value.value
        case .unknown:
            kind = .unknown
        }
    }

    var validationMessage: String? {
        switch kind {
        case .address:
            return country.trimmed.count >= 2 ? nil : "Enter the address country code."
        case .geo:
            return coordinatesValid(required: true) ? nil : "Enter valid latitude and longitude values."
        case .foursquare:
            if fsqPlaceID.trimmed.isEmpty { return "Enter the Foursquare place ID." }
            return coordinatesValid(required: false) ? nil : "Enter valid Foursquare coordinates."
        case .hthree:
            return hthreeValue.trimmed.isEmpty ? "Enter the H3 cell value." : nil
        case .unknown:
            return nil
        }
    }

    var preparedLocator: Open<Event.Locator>? {
        guard validationMessage == nil else { return nil }
        switch kind {
        case .address:
            var value = Event.Address(country: country.trimmed)
            value.name = name.trimmed.nilIfEmpty
            value.postalCode = postalCode.trimmed.nilIfEmpty
            value.region = region.trimmed.nilIfEmpty
            value.locality = locality.trimmed.nilIfEmpty
            value.street = street.trimmed.nilIfEmpty
            return .known(.address(value))
        case .geo:
            var value = Event.Geo(latitude: latitude.trimmed, longitude: longitude.trimmed)
            value.name = name.trimmed.nilIfEmpty
            value.altitude = altitude.trimmed.nilIfEmpty
            return .known(.geo(value))
        case .foursquare:
            var value = Event.Foursquare(fsqPlaceID: fsqPlaceID.trimmed)
            value.name = name.trimmed.nilIfEmpty
            value.latitude = latitude.trimmed.nilIfEmpty
            value.longitude = longitude.trimmed.nilIfEmpty
            return .known(.foursquare(value))
        case .hthree:
            var value = Event.HThree(value: hthreeValue.trimmed)
            value.name = name.trimmed.nilIfEmpty
            return .known(.hthree(value))
        case .unknown:
            return original
        }
    }

    func coordinatesValid(required: Bool) -> Bool {
        let lat = latitude.trimmed
        let lon = longitude.trimmed
        if !required && lat.isEmpty && lon.isEmpty { return true }
        guard let latitude = Double(lat), let longitude = Double(lon) else { return false }
        return (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

struct EditableLocatorFields: View {
    @Binding var locator: EditableLocator

    var body: some View {
        switch locator.kind {
        case .address:
            TextField("Name", text: $locator.name)
            TextField("Street", text: $locator.street)
            TextField("City or locality", text: $locator.locality)
            TextField("Region", text: $locator.region)
            TextField("Postal code", text: $locator.postalCode)
            TextField("Country code", text: $locator.country)
        case .geo:
            TextField("Name", text: $locator.name)
            TextField("Latitude", text: $locator.latitude)
            TextField("Longitude", text: $locator.longitude)
            TextField("Altitude", text: $locator.altitude)
        case .foursquare:
            TextField("Name", text: $locator.name)
            TextField("Foursquare place ID", text: $locator.fsqPlaceID)
            TextField("Latitude", text: $locator.latitude)
            TextField("Longitude", text: $locator.longitude)
        case .hthree:
            TextField("Name", text: $locator.name)
            TextField("H3 cell", text: $locator.hthreeValue)
        case .unknown:
            Text("This locator is preserved without changes.")
                .foregroundStyle(.secondary)
        }
    }
}

private extension Event.Address {
    var displayText: String {
        [name, street, locality, region, postalCode, country]
            .compactMap { $0?.trimmed.nilIfEmpty }
            .joined(separator: ", ")
    }
}

private extension Event.Location {
    var displayDescription: String? { description?.trimmed.nilIfEmpty }

    var mapURL: URL? {
        let destination = displayCoordinates.map { "\($0.latitude),\($0.longitude)" }
            ?? (locators ?? []).compactMap { locator -> String? in
                if case let .known(.address(address)) = locator { return address.displayText }
                return nil
            }.first
        guard let destination else { return nil }
        #if os(Android)
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: destination),
        ]
        #else
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "daddr", value: destination)]
        #endif
        return components?.url
    }

    var displayCoordinates: LocationCoordinates? {
        for locator in locators ?? [] {
            switch locator {
            case let .known(.geo(geo)):
                if let latitude = Double(geo.latitude), let longitude = Double(geo.longitude) {
                    return LocationCoordinates(latitude: latitude, longitude: longitude)
                }
            case let .known(.foursquare(place)):
                if let latitude = place.latitude.flatMap(Double.init),
                   let longitude = place.longitude.flatMap(Double.init) {
                    return LocationCoordinates(latitude: latitude, longitude: longitude)
                }
            default:
                break
            }
        }
        return nil
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
