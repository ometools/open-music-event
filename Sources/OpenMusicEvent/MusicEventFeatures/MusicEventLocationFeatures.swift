////
////  LocationView.swift
////  event-viewer
////
////  Created by Woodrow Melling on 2/23/25.
////
//
//import  SwiftUI; import SkipFuse
//
//#if canImport(MapKit)
//import MapKit
//extension MusicEvent.Location.Coordinates {
//    public init(from coordinates: CLLocationCoordinate2D) {
//        self.init(latitude: coordinates.latitude, longitude: coordinates.longitude)
//    }
//
//    public var clLocationCoordinates: CLLocationCoordinate2D {
//        .init(latitude: latitude, longitude: longitude)
//    }
//}
//#elseif os(Android)
////// skip.yml: implementation("com.google.maps.android:maps-compose:4.3.3")
//import com.google.maps.android.compose.__
//import com.google.android.gms.maps.model.CameraPosition
//import com.google.android.gms.maps.model.LatLng
//import android.location.Address
//import android.location.Geocoder
//#endif
//
//@MainActor
//@Observable
//public class LocationFeature {
//    public var location: MusicEvent.Location
//
//    public var coordinates: MusicEvent.Location.Coordinates?
//
//    public func task() async {
//        if let coordinates = location.coordinates {
//            self.coordinates = coordinates
//        } else if let address = location.address {
//            self.coordinates = await geocodeAddress(address: address)
//        }
//    }
//
//    func geocodeAddress(address: String) async -> MusicEvent.Location.Coordinates? {
//        #if canImport(MapKit)
//
//        guard let placemark = try? await CLGeocoder().geocodeAddressString(address).first,
//              let coordinates = placemark.location?.coordinate
//        else {
//            return nil
//        }
//
//        print("Placemark: \(placemark)")
//
//        return MusicEvent.Location.Coordinates(from: coordinates)
//        #elseif SKIP
//        let geocoder = Geocoder(ProcessInfo.processInfo.androidContext)
//
//        if let locations = try? geocoder.getFromLocationName(address, 1) {
//            guard !locations.isNullOrEmpty()
//            else { return nil }
//
//            return Event.Location.Coordinates(
//                latitude: locations[0].latitude,
//                longitude: locations[0].longitude
//            )
//        } else {
//            return nil
//        }
//        #else
//        #error("Unsupported platform")
//        #endif
//    }
//
//    public init(location: MusicEvent.Location) {
//        self.location = location
//        self.coordinates = location.coordinates
//    }
//}
//
//struct LocationView: View {
//    let store: LocationFeature
//
//    var body: some View {
//        Group {
//            #if os(iOS) || os(macOS)
//            List {
//                Section("") {
//                    if let coordinates = store.coordinates {
//                        MapView(coordinates: coordinates)
//                            .listRowInsets(EdgeInsets())
//                            .frame(minHeight: 350)
//                            .aspectRatio(1, contentMode: .fill)
//                    }
//
//                    if let address = store.location.address {
//                        AddressView(address: address)
//                    }
//                }
//
//                self.directions
//            }
//            #elseif os(Android)
//            VStack(spacing: 0) {
//                if let coordinates {
//                    MapView(coordinates: coordinates)
//                        .frame(minHeight: 350)
//                        .aspectRatio(1, contentMode: .fill)
//                }
//
//                List {
//                    if let address = store.location.address {
//                        AddressView(address: address)
//                    }
//
//                    self.directions
//                }
//            }
//            #else
//            #error("Unsupported Platform")
//            #endif
//        }
//        .navigationTitle("Location")
//        .task { await store.task() }
//    }
//
//    struct AddressView: View {
//        let address: String
//        var body: some View {
//            HStack {
//                Text(address)
//                    .font(.headline)
//                    #if !SKIP
//                    .textSelection(.enabled)
//                    #endif
//
//                Spacer()
//
//                Button {
//                    #if os(iOS)
//                    UIPasteboard.general.string = address
//                    #elseif os(macOS)
//                    NSPasteboard.general.setString(address, forType: .string)
//                    #endif
//                } label: {
//                    Image(systemName: "document.on.document")
//                }
//            }
//        }
//    }
//
//    @ViewBuilder
//    var directions: some View {
//        if let directions = store.location.directions {
//            Section("Directions") {
//                Text(directions)
//            }
//        }
//    }
//
//}
//
//extension Logger {
//    static let geocoderLogging = Logger(subsystem: "OpenFestival", category: "geocoding")
//}
//
//
//extension LocationView {
//    struct MapView: View {
//        var coordinates: MusicEvent.Location.Coordinates
//
//        var body: some View {
//            #if canImport(MapKit)
//            // on Darwin platforms, we use the new SwiftUI Map type
//            Map(
//                initialPosition: .region(
//                    MKCoordinateRegion(
//                        center: coordinates.clLocationCoordinates,
//                        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
//                    )
//                )
//            ) {
//                Marker(coordinate: coordinates.clLocationCoordinates) {
//
//                }
//            }
//            #elseif os(Android)
//            let coordinates = LatLng(
//                coordinates.latitude,
//                coordinates.longitude
//            )
//            //        // on Android platforms, we use com.google.maps.android.compose.GoogleMap within in a ComposeView
//            ComposeView { ctx in
//                GoogleMap(
//                    cameraPositionState: rememberCameraPositionState {
//                        position = CameraPosition.fromLatLngZoom(
//                            coordinates,
//                            Float(12.0)
//                        )
//                    }) {
//                        Marker(state = MarkerState(position = coordinates))
//                    }
//            }
//            #else
//            #error("Unsupported Platform")
//            #endif
//        }
//    }
//}
//
//
