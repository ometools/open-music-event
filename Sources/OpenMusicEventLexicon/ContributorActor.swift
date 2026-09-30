import ATProto
import Foundation
import ATProtoTypes
import SQLiteData

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
