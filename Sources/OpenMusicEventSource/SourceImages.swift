import Foundation
import OpenMusicEventLexicon

public enum SourceImageRef: Codable, Equatable, Sendable {
    case file(String)
    case url(URL)

    private enum CodingKeys: String, CodingKey {
        case file
        case url
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let file = try container.decodeIfPresent(String.self, forKey: .file) {
            self = .file(file)
        } else {
            self = .url(try container.decode(URL.self, forKey: .url))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .file(file):
            try container.encode(file, forKey: .file)
        case let .url(url):
            try container.encode(url, forKey: .url)
        }
    }
}

public struct SourceImageAsset: Codable, Equatable, Sendable {
    public init(
        assetKey: String? = nil,
        source: SourceImageRef,
        role: OMERecord.ImageAsset.Role,
        renderKind: OMERecord.ImageAsset.RenderKind,
        appearance: OMERecord.ImageAsset.Appearance? = nil,
        materializationPolicy: OMERecord.ImageAsset.MaterializationPolicy,
        thumbhash: String? = nil,
        focalPoint: OMERecord.ImageAsset.FocalPoint? = nil
    ) {
        self.assetKey = assetKey
        self.source = source
        self.role = role
        self.renderKind = renderKind
        self.appearance = appearance
        self.materializationPolicy = materializationPolicy
        self.thumbhash = thumbhash
        self.focalPoint = focalPoint
    }

    public var assetKey: String?
    public var source: SourceImageRef
    public var role: OMERecord.ImageAsset.Role
    public var renderKind: OMERecord.ImageAsset.RenderKind
    public var appearance: OMERecord.ImageAsset.Appearance?
    public var materializationPolicy: OMERecord.ImageAsset.MaterializationPolicy
    public var thumbhash: String?
    public var focalPoint: OMERecord.ImageAsset.FocalPoint?
}

public extension Collection where Element == SourceImageAsset {
    func normalizingIncompleteAppearancePairs() -> [SourceImageAsset] {
        var appearancesByKey: [String: SourceImageAppearancePairCompleteness] = [:]

        for image in self {
            guard let appearance = image.appearance else { continue }
            appearancesByKey[image.appearancePairKey, default: SourceImageAppearancePairCompleteness()]
                .insert(appearance)
        }

        return map { image in
            guard image.appearance != nil,
                  appearancesByKey[image.appearancePairKey]?.isComplete != true
            else {
                return image
            }

            var image = image
            image.appearance = nil
            return image
        }
    }
}

private struct SourceImageAppearancePairCompleteness {
    var hasDark = false
    var hasLight = false

    var isComplete: Bool {
        hasDark && hasLight
    }

    mutating func insert(_ appearance: OMERecord.ImageAsset.Appearance) {
        switch appearance {
        case .dark:
            hasDark = true
        case .light:
            hasLight = true
        }
    }
}

private extension SourceImageAsset {
    var appearancePairKey: String {
        "\(role.rawValue)|\(renderKind.rawValue)"
    }
}
