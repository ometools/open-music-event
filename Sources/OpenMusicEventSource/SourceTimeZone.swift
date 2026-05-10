import Foundation

@propertyWrapper
public struct SourceTimeZone: Codable, Equatable, Sendable {
    public var wrappedValue: TimeZone

    public init(wrappedValue: TimeZone) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let identifier = try? container.decode(String.self) {
            self.wrappedValue = try Self.timeZone(identifier, codingPath: decoder.codingPath)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identifier = try container.decode(String.self, forKey: .identifier)
        self.wrappedValue = try Self.timeZone(
            identifier,
            codingPath: decoder.codingPath + [CodingKeys.identifier]
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue.identifier)
    }

    private enum CodingKeys: String, CodingKey {
        case identifier
    }

    private static func timeZone(
        _ identifier: String,
        codingPath: [any CodingKey]
    ) throws -> TimeZone {
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: codingPath,
                    debugDescription: "Not a valid time zone identifier: \(identifier)"
                )
            )
        }
        return timeZone
    }
}
