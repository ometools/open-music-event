//
//  LocationView.swift
//  event-viewer
//
//  Created by Woodrow Melling on 2/23/25.
//

import SwiftUI; import SkipFuse
import CoreModels

#if canImport(MapKit)
import MapKit
extension MusicEvent.Location.Coordinates {
    public init(from coordinates: CLLocationCoordinate2D) {
        self.init(latitude: coordinates.latitude, longitude: coordinates.longitude)
    }

    public var clLocationCoordinates: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }
}
#endif

#if SKIP
//// skip.yml: implementation("com.google.maps.android:maps-compose:4.3.3")
import com.google.maps.android.compose.__
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import android.location.Address
import android.location.Geocoder
import android.content.Intent
import android.net.Uri
#endif

// SKIP @bridge
struct LocationCoordinates {
    // SKIP @bridge
    let latitude: Double
    // SKIP @bridge
    let longitude: Double

    // SKIP @bridge
    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(from coordinates: MusicEvent.Location.Coordinates) {
        self.latitude = coordinates.latitude
        self.longitude = coordinates.longitude
    }
}

#if canImport(MapKit)
extension LocationCoordinates {
    init(from coordinates: CLLocationCoordinate2D) {
        self.latitude = coordinates.latitude
        self.longitude = coordinates.longitude
    }
    
    var clLocationCoordinates: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
#endif

@MainActor
@Observable
public class LocationFeature {
    public var location: MusicEvent.Location

    var coordinates: LocationCoordinates?

    public func task() async {
        if let coordinates = location.coordinates {
            self.coordinates = LocationCoordinates(from: coordinates)
        } else if let address = location.address {
            self.coordinates = await geocodeAddress(address: address)
        }
    }

    public func didTapOpenInAppleMaps() {
        // Use direct Apple Maps link if available
        if let appleMapsLink = location.appleMapsLink {
            openURL(appleMapsLink)
            return
        }
        
        // Fallback to constructed URL if coordinates are available
        guard let coordinates = coordinates else { return }
        
        #if canImport(MapKit)
        let placemark = MKPlacemark(coordinate: coordinates.clLocationCoordinates)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = location.address
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        #endif
    }

    public func didTapOpenInGoogleMaps() {
        // Use direct Google Maps link if available
        if let googleMapsLink = location.googleMapsLink {
            openURL(googleMapsLink)
            return
        }
        
        // Fallback to constructed URL if coordinates are available
        guard let coordinates = coordinates else { return }
        
        let urlString = "https://www.google.com/maps/dir/?api=1&destination=\(coordinates.latitude),\(coordinates.longitude)"
        
        if let url = URL(string: urlString) {
            openURL(url)
        }
    }
    
    private func openURL(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #elseif SKIP
        let intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url.absoluteString))
        ProcessInfo.processInfo.androidContext.startActivity(intent)
        #endif
    }

    public init(location: MusicEvent.Location) {
        self.location = location
        self.coordinates = location.coordinates.map { LocationCoordinates(from: $0) }
    }
}

#if canImport(MapKit)
func geocodeAddress(address: String) async -> LocationCoordinates? {
    guard let placemark = try? await CLGeocoder().geocodeAddressString(address).first,
          let coordinates = placemark.location?.coordinate
    else {
        return nil
    }

    print("Placemark: \(placemark)")

    return LocationCoordinates(from: coordinates)
}
#endif

#if SKIP
func geocodeAddress(address: String) async -> LocationCoordinates? {
    let geocoder = Geocoder(ProcessInfo.processInfo.androidContext)

    if let locations = try? geocoder.getFromLocationName(address, 1) {
        guard !locations.isNullOrEmpty()
        else { return nil }

        return LocationCoordinates(
            latitude: locations[0].latitude,
            longitude: locations[0].longitude
        )
    } else {
        return nil
    }
}
#endif

struct LocationView: View {
    let store: LocationFeature

    var body: some View {
        Group {
            #if os(iOS) || os(macOS)
            List {
                Section("") {
                    if let coordinates = store.coordinates {
                        MapView(latitude: coordinates.latitude, longitude: coordinates.longitude)
                            .listRowInsets(EdgeInsets())
                            .frame(minHeight: 350)
                            .aspectRatio(1, contentMode: .fill)
                    }

                    if let address = store.location.address {
                        AddressView(address: address)
                    }

                    Menu {
                        #if os(iOS)
                        Button("Apple Maps", systemImage: "location") {
                            store.didTapOpenInAppleMaps()
                        }
                        #endif
                        Button("Google Maps", systemImage: "map") {
                            store.didTapOpenInGoogleMaps()
                        }
                    } label: {
                        Label("Open in Maps", systemImage: "arrow.up.right.square")
                    }
                }

                self.directions
            }
            #elseif os(Android)
            VStack(spacing: 0) {
                if let coordinates = store.coordinates {
                    MapView(latitude: coordinates.latitude, longitude: coordinates.longitude)
                        .frame(minHeight: 350)
                        .aspectRatio(1, contentMode: .fill)
                }

                List {
                    if let address = store.location.address {
                        AddressView(address: address)
                    }

                    Menu {
                        Button("Google Maps", systemImage: "map") {
                            store.didTapOpenInGoogleMaps()
                        }
                    } label: {
                        Label("Open in Maps", systemImage: "arrow.up.right.square")
                    }

                    self.directions
                }
            }
            #else
            #error("Unsupported Platform")
            #endif
        }
        .navigationTitle("Location")
        .task { await store.task() }
    }

    struct AddressView: View {
        let address: String
        var body: some View {
            HStack {
                Text(address)
                    .font(.headline)
                    #if !os(Android)
                    .textSelection(.enabled)
                    #endif

                Spacer()
            }
        }
    }

    @ViewBuilder
    var directions: some View {
        if let directions = store.location.directions {
            Section("Directions") {
                Text(directions)
            }
        }
    }

}

extension Logger {
    static let geocoderLogging = Logger(subsystem: "bundle.ome.OpenMusicEvent", category: "geocoding")
}


struct MapView: View {
    let latitude: Double
    let longitude: Double

    var body: some View {
        #if os(Android)
        // on Android platforms, we use com.google.maps.android.compose.GoogleMap within in a ComposeView
        ComposeView { MapComposer(latitude: latitude, longitude: longitude) }
        #else
        // on Darwin platforms, we use the SwiftUI Map type
        Map(
            initialPosition: .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                )
            )
        ) {
            Marker(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {

            }
        }
        #endif
    }
}

#if SKIP
struct MapComposer : ContentComposer {
    let latitude: Double
    let longitude: Double

    @Composable func Compose(context: ComposeContext) {
        GoogleMap(cameraPositionState: rememberCameraPositionState {
            position = CameraPosition.fromLatLngZoom(LatLng(latitude, longitude), Float(12.0))
        }) {
            Marker(state = MarkerState(position = LatLng(latitude, longitude)))
        }
    }
}
#endif


