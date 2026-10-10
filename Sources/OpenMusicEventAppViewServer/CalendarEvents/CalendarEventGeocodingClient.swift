import Dependencies
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CalendarEventGeocodingClient: Sendable {
    public struct Coordinates: Codable, Equatable, Sendable {
        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }

        public var latitude: Double
        public var longitude: Double
    }

    public enum Result: Equatable, Sendable {
        case coordinates(latitude: Double, longitude: Double)
        case noResult
        case unavailable
    }

    public init(
        coordinatesForAddress: @escaping @Sendable (String) async throws -> Result
    ) {
        self.coordinatesForAddress = coordinatesForAddress
    }

    public var coordinatesForAddress: @Sendable (String) async throws -> Result
}

private enum CalendarEventGeocodingClientKey: TestDependencyKey {
    static var testValue: CalendarEventGeocodingClient { .unconfigured }
}

extension CalendarEventGeocodingClientKey: DependencyKey {
    static var liveValue: CalendarEventGeocodingClient { .unconfigured }
}

public extension DependencyValues {
    var calendarEventGeocoding: CalendarEventGeocodingClient {
        get { self[CalendarEventGeocodingClientKey.self] }
        set { self[CalendarEventGeocodingClientKey.self] = newValue }
    }
}

public extension CalendarEventGeocodingClient {
    static var unconfigured: Self {
        Self { _ in .unavailable }
    }

    static func overrides(
        _ coordinatesByAddress: [String: Coordinates],
        fallback: Self = .unconfigured
    ) -> Self {
        let normalizedCoordinates = Dictionary(
            uniqueKeysWithValues: coordinatesByAddress.map {
                (CalendarGeocode.normalize($0.key), $0.value)
            }
        )
        return Self { address in
            if let coordinates = normalizedCoordinates[CalendarGeocode.normalize(address)] {
                return .coordinates(
                    latitude: coordinates.latitude,
                    longitude: coordinates.longitude
                )
            }
            return try await fallback.coordinatesForAddress(address)
        }
    }

    static func geoapify(
        apiKey: String,
        dataForRequest: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) -> Self {
        Self { address in
            var components = URLComponents(
                string: "https://api.geoapify.com/v1/geocode/search"
            )!
            components.queryItems = [
                URLQueryItem(name: "text", value: address),
                URLQueryItem(name: "limit", value: "1"),
                URLQueryItem(name: "format", value: "geojson"),
            ]
            var request = URLRequest(url: components.url!)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            let (data, response) = try await dataForRequest(request)
            guard let response = response as? HTTPURLResponse else {
                throw CalendarEventGeocodingError.invalidResponse
            }
            guard (200..<300).contains(response.statusCode) else {
                throw CalendarEventGeocodingError.httpStatus(response.statusCode)
            }
            let payload = try JSONDecoder().decode(GeoapifyResponse.self, from: data)
            guard let properties = payload.features.first?.properties else {
                return .noResult
            }
            guard properties.lat.isFinite,
                  properties.lon.isFinite,
                  (-90...90).contains(properties.lat),
                  (-180...180).contains(properties.lon)
            else { throw CalendarEventGeocodingError.invalidCoordinates }
            return .coordinates(latitude: properties.lat, longitude: properties.lon)
        }
    }
}

public enum CalendarEventGeocodingError: Error, Equatable, Sendable {
    case httpStatus(Int)
    case invalidCoordinates
    case invalidResponse
}

private struct GeoapifyResponse: Decodable {
    struct Feature: Decodable {
        struct Properties: Decodable {
            var lat: Double
            var lon: Double
        }

        var properties: Properties
    }

    var features: [Feature]
}
