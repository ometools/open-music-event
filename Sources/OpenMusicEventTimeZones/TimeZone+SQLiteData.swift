import Foundation
import SQLiteData

extension TimeZone: @retroactive SQLiteType {
    public static var typeAffinity: SQLiteTypeAffinity { .text }
}

extension TimeZone: @retroactive QueryRepresentable {}
extension TimeZone: @retroactive QueryExpression {}
extension TimeZone: @retroactive QueryBindable {
    public var queryBinding: QueryBinding { identifier.queryBinding }
}

extension TimeZone: @retroactive _OptionalPromotable {}
extension TimeZone: @retroactive QueryDecodable {
    public init(decoder: inout some QueryDecoder) throws {
        let identifier = try String(decoder: &decoder)
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw InvalidTimeZoneIdentifierError(identifier: identifier)
        }
        self = timeZone
    }
}

public struct InvalidTimeZoneIdentifierError: Error, Equatable, Sendable {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }
}
