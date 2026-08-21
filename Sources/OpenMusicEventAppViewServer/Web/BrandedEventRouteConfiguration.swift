import Foundation
import OpenMusicEventLexicon
import OpenMusicEventRouting

extension AppViewConfiguration {
    static func brandedEventRouteClaims(
        environment: [String: String]
    ) throws -> [BrandedEventRouteClaim] {
        guard let path = environment["OME_BRANDED_EVENT_ROUTE_CONFIGURATION_PATH"] else {
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw AppViewConfigurationError.brandedEventRouteConfigurationUnreadable(path)
        }

        let file: BrandedEventRouteConfigurationFile
        do {
            file = try JSONDecoder().decode(BrandedEventRouteConfigurationFile.self, from: data)
        } catch {
            throw AppViewConfigurationError.brandedEventRouteConfigurationInvalid(path)
        }

        var routeKeys: Set<String> = []
        return try file.claims.map { configuredClaim in
            let host = configuredClaim.host.lowercased()
            guard isSafeDomainName(host) else {
                throw AppViewConfigurationError.invalidBrandedEventRouteHost(
                    configuredClaim.host
                )
            }
            guard isSafeRouteComponent(configuredClaim.eventClaim) else {
                throw AppViewConfigurationError.invalidBrandedEventRouteClaim(
                    configuredClaim.eventClaim
                )
            }
            guard let organizerID = OME.Organizer.ID(configuredClaim.organizerID) else {
                throw AppViewConfigurationError.invalidBrandedEventRouteOrganizerID(
                    configuredClaim.organizerID
                )
            }
            guard !configuredClaim.eventRKey.isEmpty else {
                throw AppViewConfigurationError.invalidBrandedEventRouteRKey(
                    configuredClaim.eventRKey
                )
            }
            guard routeKeys.insert("\(host)/\(configuredClaim.eventClaim)").inserted else {
                throw AppViewConfigurationError.duplicateBrandedEventRoute(
                    host: host,
                    eventClaim: configuredClaim.eventClaim
                )
            }

            return BrandedEventRouteClaim(
                host: host,
                eventClaim: configuredClaim.eventClaim,
                eventID: OME.Event.ID(
                    organizerID: organizerID,
                    eventID: OME.ID<OME.Event>(.init(configuredClaim.eventRKey))
                )
            )
        }
    }
}

private struct BrandedEventRouteConfigurationFile: Decodable {
    var claims: [Claim]

    struct Claim: Decodable {
        var host: String
        var eventClaim: String
        var organizerID: String
        var eventRKey: String
    }
}

private func isSafeDomainName(_ value: String) -> Bool {
    !value.isEmpty && value.allSatisfy { character in
        character.isASCII
            && (character.isLetter || character.isNumber || character == "." || character == "-")
    }
}

private func isSafeRouteComponent(_ value: String) -> Bool {
    !value.isEmpty && value.allSatisfy { character in
        character.isASCII
            && (
                character.isLetter
                    || character.isNumber
                    || character == "-"
                    || character == "."
                    || character == "_"
                    || character == "~"
            )
    }
}
