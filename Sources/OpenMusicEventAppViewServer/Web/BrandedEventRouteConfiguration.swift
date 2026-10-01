import Foundation
import ATProtoTypes
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
            guard let eventID = Event.ID(configuredClaim.eventURI) else {
                throw AppViewConfigurationError.invalidBrandedEventRouteEventURI(
                    configuredClaim.eventURI
                )
            }
            do {
                try LexiconCoding.validateRecordURI(eventID, type: Event.self)
            } catch {
                throw AppViewConfigurationError.invalidBrandedEventRouteEventURI(
                    configuredClaim.eventURI
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
                eventID: eventID
            )
        }
    }
}

private struct BrandedEventRouteConfigurationFile: Decodable {
    var claims: [Claim]

    struct Claim: Decodable {
        var host: String
        var eventClaim: String
        var eventURI: String
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
