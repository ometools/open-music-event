//
//  SemanticVersion.swift
//  open-music-event
//
//  Created by Woodrow Melling on 6/11/25.
//

import Tagged

/**
 A struct representing a semantic version number.

 https://semver.org/

 #Usage
 ```swift
 let version1 = SemanticVersion(major: 1, minor: 2, patch: 3)
 let version2 = SemanticVersion(1, 2, 3)
 let version3 = SemanticVersion("4.5.6")
 let version4 = SemanticVersion(tolerant: "7.8")
 ```

 Semantic version numbers follow the format `major.minor.patch` and are used to indicate compatibility between software versions.
 */
public struct SemanticVersion: Hashable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /**
     Initializes a new `SemanticVersion` instance from a string representation of the version.

     The string should follow the format `major.minor.patch`.

     - Parameter string: A string representation of the version.
     - Returns: A new `SemanticVersion` instance, or `nil` if the string is not in the correct format.
     */
    public init?(_ string: String) {
        let components = string.split(separator: ".")
        guard components.count == 3
        else { return nil }

        guard let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2])
        else { return nil }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /**
     Initializes a new `SemanticVersion` instance from a string representation of the version, allowing for a more lenient format.

     The string should follow the format `major.minor.patch` or `major.minor`. If the patch version is omitted, it is assumed to be 0.

     - Parameter tolerantString: A string representation of the version, in a more lenient format.
     - Returns: A new `SemanticVersion` instance, or `nil` if the string is not in the correct format.
     */
    public init?(tolerant string: String) {
        let components = string.split(separator: ".")
        guard components.count == 3 || components.count == 2 else { return nil }

        guard let major = Int(components[0]),
              let minor = Int(components[1])
        else { return nil }

        let patch = components.count == 3 ? Int(components[2]) : 0
        guard let patch else { return nil }

        self.major = major
        self.minor = minor
        self.patch = patch
    }
}

extension SemanticVersion: CustomStringConvertible {
    public var description: String {
        "\(major).\(minor).\(patch)"
    }
}

extension SemanticVersion: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        } else if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}

extension SemanticVersion: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let versionString = try container.decode(String.self)
        guard let version = SemanticVersion(tolerant: versionString) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid semantic version string: \(versionString)")
        }
        self = version
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.description)
    }
}

public enum iOSVersionTag {}
public typealias iOSVersion = Tagged<iOSVersionTag, SemanticVersion>

public extension Tagged where RawValue == SemanticVersion {
    init(major: Int, minor: Int, patch: Int) {
        self.init(rawValue: .init(major: major, minor: minor, patch: patch))
    }

    init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.init(rawValue: .init(major: major, minor: minor, patch: patch))
    }

    init?(_ string: String) {
        if let version = SemanticVersion(string) {
            self.init(version)
        } else {
            return nil
        }
    }

    init?(tolerant string: String) {
        if let version = SemanticVersion(tolerant: string) {
            self.init(version)
        } else {
            return nil
        }
    }
}
