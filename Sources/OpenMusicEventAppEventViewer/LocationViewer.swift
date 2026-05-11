import ComposableArchitecture2
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
        @FetchOne(OMERecord.Event.defaultEvent) public var event: OMERecord.Event?

        public init() {}
    }

    public enum Action {}

    public var body: some Feature {
        Update { _, _ in }
    }
}

public struct LocationViewerView: View {
    let store: StoreOf<LocationViewer>

    public init(store: StoreOf<LocationViewer>) {
        self.store = store
    }

    public var body: some View {
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
                description: "No locations have been added to this event yet."
            )
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

private extension OMERecord.Event.Location.Coordinates {
    var displayText: String {
        "\(latitude), \(longitude)"
    }
}
