//
//  LocationView.swift
//  event-viewer
//
//  Created by Woodrow Melling on 2/23/25.
//

import  SwiftUI; import SkipFuse
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

                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = address
                    #elseif os(macOS)
                    NSPasteboard.general.setString(address, forType: .string)
                    #endif
                } label: {
                    Image(systemName: "document.on.document")
                }
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
    static let geocoderLogging = Logger(subsystem: "OpenFestival", category: "geocoding")
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


