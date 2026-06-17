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
        self.role = role
        self.renderKind = renderKind
        self.materializationPolicy = materializationPolicy

        let payload = Payload(
            assetKey: assetKey,
            source: source,
            thumbhash: thumbhash,
            focalPoint: focalPoint
        )
        if let appearance {
            self.variants = .legacyAppearance(payload, appearance)
        } else {
            self.variants = .standard(payload)
        }
    }

    public init(
        role: OMERecord.ImageAsset.Role,
        renderKind: OMERecord.ImageAsset.RenderKind,
        materializationPolicy: OMERecord.ImageAsset.MaterializationPolicy,
        appearances: AppearancePair
    ) {
        self.role = role
        self.renderKind = renderKind
        self.materializationPolicy = materializationPolicy
        self.variants = .appearances(appearances)
    }

    public var role: OMERecord.ImageAsset.Role
    public var renderKind: OMERecord.ImageAsset.RenderKind
    public var materializationPolicy: OMERecord.ImageAsset.MaterializationPolicy
    public var variants: Variants

    public var assetKey: String? {
        get { primaryPayload.assetKey }
        set {
            updatePrimaryPayload {
                $0.assetKey = newValue
            }
        }
    }

    public var source: SourceImageRef {
        get { primaryPayload.source }
        set {
            updatePrimaryPayload {
                $0.source = newValue
            }
        }
    }

    public var appearance: OMERecord.ImageAsset.Appearance? {
        get {
            guard case let .legacyAppearance(_, appearance) = variants else {
                return nil
            }
            return appearance
        }
        set {
            let payload = primaryPayload
            if let newValue {
                variants = .legacyAppearance(payload, newValue)
            } else {
                variants = .standard(payload)
            }
        }
    }

    public var thumbhash: String? {
        get { primaryPayload.thumbhash }
        set {
            updatePrimaryPayload {
                $0.thumbhash = newValue
            }
        }
    }

    public var focalPoint: OMERecord.ImageAsset.FocalPoint? {
        get { primaryPayload.focalPoint }
        set {
            updatePrimaryPayload {
                $0.focalPoint = newValue
            }
        }
    }

    public var appearances: AppearancePair? {
        get {
            guard case let .appearances(pair) = variants else {
                return nil
            }
            return pair
        }
        set {
            if let newValue {
                variants = .appearances(newValue)
            } else {
                variants = .standard(primaryPayload)
            }
        }
    }

    public var payloads: [VariantPayload] {
        switch variants {
        case let .standard(payload):
            return [
                VariantPayload(appearance: nil, payload: payload)
            ]

        case let .legacyAppearance(payload, appearance):
            return [
                VariantPayload(appearance: appearance, payload: payload)
            ]

        case let .appearances(pair):
            return [
                VariantPayload(appearance: .light, payload: pair.light),
                VariantPayload(appearance: .dark, payload: pair.dark),
            ]
        }
    }

    public func payload(
        for appearance: OMERecord.ImageAsset.Appearance?
    ) -> Payload? {
        payloads.first { $0.appearance == appearance }?.payload
    }

    public func mapPayloads(
        _ transform: (Payload, OMERecord.ImageAsset.Appearance?) throws -> Payload
    ) rethrows -> SourceImageAsset {
        var image = self
        switch variants {
        case let .standard(payload):
            image.variants = try .standard(transform(payload, nil))

        case let .legacyAppearance(payload, appearance):
            image.variants = try .legacyAppearance(transform(payload, appearance), appearance)

        case let .appearances(pair):
            image.variants = try .appearances(
                AppearancePair(
                    light: transform(pair.light, .light),
                    dark: transform(pair.dark, .dark)
                )
            )
        }
        return image
    }

    private var primaryPayload: Payload {
        switch variants {
        case let .standard(payload),
             let .legacyAppearance(payload, _):
            return payload

        case let .appearances(pair):
            return pair.light
        }
    }

    private mutating func updatePrimaryPayload(
        _ update: (inout Payload) -> Void
    ) {
        switch variants {
        case var .standard(payload):
            update(&payload)
            variants = .standard(payload)

        case .legacyAppearance(var payload, let appearance):
            update(&payload)
            variants = .legacyAppearance(payload, appearance)

        case var .appearances(pair):
            update(&pair.light)
            variants = .appearances(pair)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case assetKey
        case source
        case role
        case renderKind
        case appearance
        case materializationPolicy
        case thumbhash
        case focalPoint
        case appearances
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        role = try container.decode(OMERecord.ImageAsset.Role.self, forKey: .role)
        renderKind = try container.decode(OMERecord.ImageAsset.RenderKind.self, forKey: .renderKind)
        materializationPolicy = try container.decode(
            OMERecord.ImageAsset.MaterializationPolicy.self,
            forKey: .materializationPolicy
        )

        if let appearances = try container.decodeIfPresent(AppearancePair.self, forKey: .appearances) {
            variants = .appearances(appearances)
        } else {
            let payload = Payload(
                assetKey: try container.decodeIfPresent(String.self, forKey: .assetKey),
                source: try container.decode(SourceImageRef.self, forKey: .source),
                thumbhash: try container.decodeIfPresent(String.self, forKey: .thumbhash),
                focalPoint: try container.decodeIfPresent(
                    OMERecord.ImageAsset.FocalPoint.self,
                    forKey: .focalPoint
                )
            )
            if let appearance = try container.decodeIfPresent(
                OMERecord.ImageAsset.Appearance.self,
                forKey: .appearance
            ) {
                variants = .legacyAppearance(payload, appearance)
            } else {
                variants = .standard(payload)
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(renderKind, forKey: .renderKind)
        try container.encode(materializationPolicy, forKey: .materializationPolicy)

        switch variants {
        case let .standard(payload),
             let .legacyAppearance(payload, _):
            try container.encodeIfPresent(payload.assetKey, forKey: .assetKey)
            try container.encode(payload.source, forKey: .source)
            try container.encodeIfPresent(payload.thumbhash, forKey: .thumbhash)
            try container.encodeIfPresent(payload.focalPoint, forKey: .focalPoint)

        case let .appearances(pair):
            try container.encode(pair, forKey: .appearances)
        }
    }
}

public extension SourceImageAsset {
    struct Payload: Codable, Equatable, Sendable {
        public init(
            assetKey: String? = nil,
            source: SourceImageRef,
            thumbhash: String? = nil,
            focalPoint: OMERecord.ImageAsset.FocalPoint? = nil
        ) {
            self.assetKey = assetKey
            self.source = source
            self.thumbhash = thumbhash
            self.focalPoint = focalPoint
        }

        public var assetKey: String?
        public var source: SourceImageRef
        public var thumbhash: String?
        public var focalPoint: OMERecord.ImageAsset.FocalPoint?
    }

    struct AppearancePair: Codable, Equatable, Sendable {
        public init(light: Payload, dark: Payload) {
            self.light = light
            self.dark = dark
        }

        public var light: Payload
        public var dark: Payload
    }

    enum Variants: Equatable, Sendable {
        case standard(Payload)
        case legacyAppearance(Payload, OMERecord.ImageAsset.Appearance)
        case appearances(AppearancePair)
    }

    struct VariantPayload: Equatable, Sendable {
        public init(
            appearance: OMERecord.ImageAsset.Appearance?,
            payload: Payload
        ) {
            self.appearance = appearance
            self.payload = payload
        }

        public var appearance: OMERecord.ImageAsset.Appearance?
        public var payload: Payload
    }
}

public extension SourceImageAsset {
    init(_ imageAsset: OMERecord.ImageAsset) {
        self.init(
            assetKey: imageAsset.assetKey,
            source: {
                switch imageAsset.source {
                case let .blob(blob):
                    // Source DTOs are collaboration-level and should stay path/URL based.
                    let url = URL(string: "atproto-blob://\(blob.ref.rawValue)")!
                    return .url(url)
                case let .url(url):
                    return .url(url)
                }
            }(),
            role: imageAsset.role,
            renderKind: imageAsset.renderKind,
            appearance: imageAsset.appearance,
            materializationPolicy: imageAsset.materializationPolicy,
            thumbhash: imageAsset.thumbhash,
            focalPoint: imageAsset.focalPoint
        )
    }

    var recordValues: [OMERecord.ImageAsset] {
        recordPayloads.map { variant in
            OMERecord.ImageAsset(
                assetKey: variant.payload.assetKey,
                source: .url(variant.payload.url),
                role: role,
                renderKind: renderKind,
                appearance: variant.appearance,
                materializationPolicy: materializationPolicy,
                thumbhash: variant.payload.thumbhash,
                focalPoint: variant.payload.focalPoint
            )
        }
    }

    var recordValue: OMERecord.ImageAsset {
        recordValues[0]
    }

    var url: URL {
        primaryPayload.url
    }

    private var recordPayloads: [VariantPayload] {
        switch variants {
        case let .legacyAppearance(payload, _):
            return [
                VariantPayload(appearance: nil, payload: payload)
            ]

        default:
            return payloads
        }
    }
}

public extension Collection where Element == SourceImageAsset {
    func recordImageAssets() -> [OMERecord.ImageAsset] {
        bundlingAppearancePairs().flatMap(\.recordValues)
    }

    func bundlingAppearancePairs() -> [SourceImageAsset] {
        var buckets: [SourceImageBundleKey: SourceImageAppearanceBucket] = [:]
        for image in self {
            guard case let .legacyAppearance(payload, appearance) = image.variants else {
                continue
            }
            buckets[SourceImageBundleKey(image), default: SourceImageAppearanceBucket()]
                .insert(payload, appearance: appearance)
        }

        let completeKeys = Set(buckets.compactMap { key, bucket in
            bucket.isComplete ? key : nil
        })
        var emittedKeys = Set<SourceImageBundleKey>()
        var images: [SourceImageAsset] = []

        for image in self {
            guard case .legacyAppearance = image.variants else {
                images.append(image)
                continue
            }

            let key = SourceImageBundleKey(image)
            guard completeKeys.contains(key) else {
                var image = image
                image.appearance = nil
                images.append(image)
                continue
            }

            guard emittedKeys.insert(key).inserted,
                  let pair = buckets[key]?.appearancePair
            else { continue }

            images.append(
                SourceImageAsset(
                    role: image.role,
                    renderKind: image.renderKind,
                    materializationPolicy: image.materializationPolicy,
                    appearances: pair
                )
            )
        }

        return images
    }
}

public extension Collection where Element == OMERecord.ImageAsset {
    func sourceImageAssets() -> [SourceImageAsset] {
        map(SourceImageAsset.init).bundlingAppearancePairs()
    }
}

private struct SourceImageBundleKey: Hashable {
    init(_ image: SourceImageAsset) {
        self.role = image.role.rawValue
        self.renderKind = image.renderKind.rawValue
        self.materializationPolicy = image.materializationPolicy.rawValue
    }

    var role: String
    var renderKind: String
    var materializationPolicy: String
}

private struct SourceImageAppearanceBucket {
    var light: SourceImageAsset.Payload?
    var dark: SourceImageAsset.Payload?

    var isComplete: Bool {
        light != nil && dark != nil
    }

    var appearancePair: SourceImageAsset.AppearancePair? {
        guard let light, let dark else { return nil }
        return SourceImageAsset.AppearancePair(light: light, dark: dark)
    }

    mutating func insert(
        _ payload: SourceImageAsset.Payload,
        appearance: OMERecord.ImageAsset.Appearance
    ) {
        switch appearance {
        case .dark:
            dark = payload
        case .light:
            light = payload
        }
    }
}

private extension SourceImageAsset.Payload {
    var url: URL {
        switch source {
        case let .file(path):
            URL(filePath: path)
        case let .url(url):
            url
        }
    }
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
