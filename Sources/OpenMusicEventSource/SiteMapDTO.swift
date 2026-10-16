import Foundation
import OpenMusicEventLexicon
import Tagged

public struct SiteMapDTO: Codable, Equatable, Sendable {
    public struct Style: Codable, Equatable, Identifiable, Sendable {
        public typealias ID = OME.ID<OME.Event.SiteMap.Style>

        public struct Image: Codable, Equatable, Sendable {
            public init(
                assetKey: String? = nil,
                source: SourceImageRef,
                materializationPolicy: OME.ImageAsset.MaterializationPolicy = .lazy,
                thumbhash: String? = nil,
                focalPoint: OME.ImageAsset.FocalPoint? = nil
            ) {
                self.assetKey = assetKey
                self.source = source
                self.materializationPolicy = materializationPolicy
                self.thumbhash = thumbhash
                self.focalPoint = focalPoint
            }

            public var assetKey: String?
            public var source: SourceImageRef
            public var materializationPolicy: OME.ImageAsset.MaterializationPolicy
            public var thumbhash: String?
            public var focalPoint: OME.ImageAsset.FocalPoint?

            public var sourceImageAsset: SourceImageAsset {
                SourceImageAsset(
                    assetKey: assetKey,
                    source: source,
                    role: .siteMap,
                    renderKind: .fullImage,
                    materializationPolicy: materializationPolicy,
                    thumbhash: thumbhash,
                    focalPoint: focalPoint
                )
            }

            private enum CodingKeys: String, CodingKey {
                case assetKey
                case source
                case materializationPolicy
                case thumbhash
                case focalPoint
            }

            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.init(
                    assetKey: try container.decodeIfPresent(String.self, forKey: .assetKey),
                    source: try container.decode(SourceImageRef.self, forKey: .source),
                    materializationPolicy: try container.decodeIfPresent(
                        OME.ImageAsset.MaterializationPolicy.self,
                        forKey: .materializationPolicy
                    ) ?? .lazy,
                    thumbhash: try container.decodeIfPresent(String.self, forKey: .thumbhash),
                    focalPoint: try container.decodeIfPresent(
                        OME.ImageAsset.FocalPoint.self,
                        forKey: .focalPoint
                    )
                )
            }

            public func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(assetKey, forKey: .assetKey)
                try container.encode(source, forKey: .source)
                if materializationPolicy != .lazy {
                    try container.encode(materializationPolicy, forKey: .materializationPolicy)
                }
                try container.encodeIfPresent(thumbhash, forKey: .thumbhash)
                try container.encodeIfPresent(focalPoint, forKey: .focalPoint)
            }
        }

        public init(id: ID, title: String, image: Image) {
            self.id = id
            self.title = title
            self.image = image
        }

        public var id: ID
        public var title: String
        public var image: Image
    }

    public init(
        title: String,
        defaultStyleID: Style.ID? = nil,
        styles: [Style]
    ) {
        self.title = title
        self.defaultStyleID = defaultStyleID
        self.styles = styles
    }

    public var title: String
    public var defaultStyleID: Style.ID?
    public var styles: [Style]
}
