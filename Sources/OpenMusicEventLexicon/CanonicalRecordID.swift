import ATProtoTypes
import Foundation

public enum CanonicalRecordID {
    private static let alphabet = Array("234567abcdefghijklmnopqrstuvwxyz".utf8)

    public static func next(
        collection: Lexicon.ID,
        in repository: ATProto.URI.Authority,
        at date: Date,
        after previous: ATProto.Record.Key? = nil,
        clockID: UInt16 = .random(in: 0..<1024)
    ) throws -> ATProto.URI {
        let microseconds = date.timeIntervalSince1970 * 1_000_000
        guard microseconds >= 0, microseconds < Double(1 << 53), clockID < 1024 else {
            throw Error.invalidTimestamp
        }
        var value = (UInt64(microseconds) << 10) | UInt64(clockID)
        if let previous {
            guard let priorValue = decode(previous.rawValue), priorValue < UInt64.max else {
                throw Error.invalidPreviousKey
            }
            value = max(value, priorValue + 1)
        }
        var encoded = [UInt8](repeating: alphabet[0], count: 13)
        for index in encoded.indices.reversed() {
            encoded[index] = alphabet[Int(value & 31)]
            value >>= 5
        }
        return ATProto.URI(
            authority: repository,
            collection: ATProto.NSID(rawValue: collection.rawValue),
            rkey: ATProto.Record.Key(rawValue: String(decoding: encoded, as: UTF8.self))
        )
    }

    private static func decode(_ key: String) -> UInt64? {
        guard key.utf8.count == 13 else { return nil }
        var value: UInt64 = 0
        for character in key.utf8 {
            guard let digit = alphabet.firstIndex(of: character),
                  value <= (UInt64.max >> 5) else { return nil }
            value = (value << 5) | UInt64(digit)
        }
        return value
    }

    public enum Error: Swift.Error {
        case invalidTimestamp
        case invalidPreviousKey
    }
}
