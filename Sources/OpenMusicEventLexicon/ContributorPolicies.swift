import ATProto
import Foundation
import Lexicon
import SQLiteData

extension OpenMusicEvent.Event {
    public struct Policies: Codable, Equatable, Sendable {
        public init(contributors: ContributorPolicies? = nil) {
            self.contributors = contributors
        }

        public var contributors: ContributorPolicies?
    }

    public struct ContributorPolicies: Codable, Equatable, Sendable {
        public init(
            listing: Open<ContributorListingPolicy>? = nil,
            profile: Open<ContributorProfilePolicy>? = nil
        ) {
            self.listing = listing
            self.profile = profile
        }

        public var listing: Open<ContributorListingPolicy>?
        public var profile: Open<ContributorProfilePolicy>?
    }

    public enum ContributorListingPolicy: Equatable, Sendable {
        case scheduleContributors
    }

    public enum ContributorProfilePolicy: Equatable, Sendable {
        case actorProfiles(ActorProfiles)
        case claimedArtistsOnly(ClaimedArtistsOnly)

        public struct ActorProfiles: Codable, Equatable, Sendable {
            public init(providers: [Open<ContributorProfileProvider>]) {
                self.providers = providers
            }

            public var providers: [Open<ContributorProfileProvider>]
        }

        public struct ClaimedArtistsOnly: Codable, Equatable, Sendable {
            public init(providers: [Open<ContributorProfileProvider>]) {
                self.providers = providers
            }

            public var providers: [Open<ContributorProfileProvider>]
        }
    }

    public enum ContributorProfileProvider: String, Codable, Equatable, Hashable, Sendable, OpenValue, SQLiteType {
        case bskyActorProfile = "app.bsky.actor.profile"
    }
}

extension OpenMusicEvent.Event.ContributorListingPolicy: OpenValue {
    public static func decodeOpen(from decoder: any Decoder) throws -> Open<Self> {
        let partialValue = try Open<Self>.PartialValue(from: decoder)
        guard case let .object(object) = partialValue,
              case let .string(type)? = object["type"]
        else {
            return .unknown(partialValue)
        }

        switch type {
        case "scheduleContributors":
            return .known(.scheduleContributors)

        default:
            return .unknown(partialValue)
        }
    }

    public static func encodeOpen(_ value: Open<Self>, to encoder: any Encoder) throws {
        switch value {
        case let .known(policy):
            try encodedPartialValue(for: policy).encode(to: encoder)

        case let .unknown(partialValue):
            try partialValue.encode(to: encoder)
        }
    }

    private static func encodedPartialValue(for policy: Self) -> Open<Self>.PartialValue {
        let type: String

        switch policy {
        case .scheduleContributors:
            type = "scheduleContributors"
        }

        return .object([
            "type": .string(type)
        ])
    }
}

extension OpenMusicEvent.Event.ContributorProfilePolicy: OpenValue {
    public static func decodeOpen(from decoder: any Decoder) throws -> Open<Self> {
        let partialValue = try Open<Self>.PartialValue(from: decoder)
        guard case let .object(object) = partialValue,
              case let .string(type)? = object["type"]
        else {
            return .unknown(partialValue)
        }

        switch type {
        case "actorProfiles":
            return .known(.actorProfiles(try partialValue.decoded(as: ActorProfiles.self)))

        case "claimedArtistsOnly":
            return .known(.claimedArtistsOnly(try partialValue.decoded(as: ClaimedArtistsOnly.self)))

        default:
            return .unknown(partialValue)
        }
    }

    public static func encodeOpen(_ value: Open<Self>, to encoder: any Encoder) throws {
        switch value {
        case let .known(policy):
            try encodedPartialValue(for: policy).encode(to: encoder)

        case let .unknown(partialValue):
            try partialValue.encode(to: encoder)
        }
    }

    private static func encodedPartialValue(for policy: Self) throws -> Open<Self>.PartialValue {
        let type: String
        let payload: Open<Self>.PartialValue

        switch policy {
        case let .actorProfiles(actorProfiles):
            type = "actorProfiles"
            payload = try Open<Self>.PartialValue(encoding: actorProfiles)

        case let .claimedArtistsOnly(claimedArtistsOnly):
            type = "claimedArtistsOnly"
            payload = try Open<Self>.PartialValue(encoding: claimedArtistsOnly)
        }

        guard case var .object(object) = payload else {
            throw EncodingError.invalidValue(
                policy,
                .init(
                    codingPath: [],
                    debugDescription: "Contributor profile policy payload must encode as an object."
                )
            )
        }

        object["type"] = .string(type)
        return .object(object)
    }
}

extension OpenMusicEvent.Contributor {
    public struct Actor: Codable, Equatable, Hashable, Sendable, LosslessStringConvertible, SQLiteType {
        public init(_ identifier: Atmosphere.Account.Identifier) {
            switch identifier {
            case let .did(did):
                self.identifier = .did(did)
            case let .handle(handle):
                self.identifier = .handle(.init(rawValue: handle.rawValue.lowercased()))
            }
        }

        public init?(_ description: String) {
            let value = description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }

            if let did = DID(value) {
                self.identifier = .did(did)
                return
            }

            let handle = value.lowercased()
            guard Self.isValidHandle(handle) else { return nil }
            self.identifier = .handle(.init(rawValue: handle))
        }

        public var identifier: Atmosphere.Account.Identifier

        public var description: String {
            identifier.description
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let actor = Self(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ATProto actor identifier: \(string)"
                )
            }
            self = actor
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(description)
        }

        public static var typeAffinity: SQLiteTypeAffinity { .text }

        private static func isValidHandle(_ handle: String) -> Bool {
            guard handle.count <= 253,
                  handle.contains("."),
                  !handle.hasPrefix("."),
                  !handle.hasSuffix("."),
                  !handle.contains("@")
            else { return false }

            return handle
                .split(separator: ".", omittingEmptySubsequences: false)
                .allSatisfy { label in
                    guard (1...63).contains(label.count),
                          let first = label.first,
                          let last = label.last,
                          first.isLetter || first.isNumber,
                          last.isLetter || last.isNumber
                    else { return false }

                    return label.allSatisfy { character in
                        character.isLetter || character.isNumber || character == "-"
                    }
                }
        }
    }
}

extension OpenMusicEvent.Contributor.Actor: QueryRepresentable {}
extension OpenMusicEvent.Contributor.Actor: QueryExpression {}
extension OpenMusicEvent.Contributor.Actor: QueryBindable {
    public var queryBinding: QueryBinding { description.queryBinding }
}
extension OpenMusicEvent.Contributor.Actor: _OptionalPromotable {}
extension OpenMusicEvent.Contributor.Actor: QueryDecodable {
    public init(decoder: inout some QueryDecoder) throws {
        let rawValue = try String(decoder: &decoder)
        guard let actor = Self(rawValue) else {
            throw InvalidContributorActorIdentifier(rawValue: rawValue)
        }
        self = actor
    }
}

public struct InvalidContributorActorIdentifier: Error, Equatable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
