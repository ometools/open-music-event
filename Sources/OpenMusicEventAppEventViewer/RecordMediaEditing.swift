import ATProto
import ATProtoTypes
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon

public enum RecordMediaEditing {
    static func preparedMedia(_ entries: [MediaEntry]) throws -> [Open<OME.Media>]? {
        let prepared = try entries.map(preparedValue)
        return prepared.isEmpty ? nil : prepared
    }

    static func preparedValue(_ entry: MediaEntry) throws -> Open<OME.Media> {
        guard let importedImage = entry.importedImage,
              case let .known(.image(image)) = entry.value else { return entry.value }
        var preparedImage = image
        preparedImage.source = .known(.blob(try stageLocalImageBlob(
            importedImage.data,
            mimeType: ATProto.MIMEType(rawValue: importedImage.mimeType)
        )))
        return .known(.image(preparedImage))
    }

    public struct MediaEntry: Equatable, Identifiable, Sendable {
        public init(importedImage: ImportImages.ImportedImage) {
            let imageValue = ImageAssetPicker.ImageValue(importedImage: importedImage)
            self.init(
                id: imageValue.id,
                value: .known(.image(imageValue.image)),
                importedImage: imageValue.importedImage
            )
        }

        public init(
            id: UUID? = nil,
            value: Open<OME.Media>,
            importedImage: ImportImages.ImportedImage? = nil,
            managedByImagePicker: Bool = false
        ) {
            @Dependency(\.uuid) var uuid
            self.id = id ?? uuid()
            self.value = value
            self.importedImage = importedImage
            self.managedByImagePicker = managedByImagePicker
        }

        public var id: UUID
        public var value: Open<OME.Media>
        public var importedImage: ImportImages.ImportedImage?
        public var managedByImagePicker: Bool

        public var imageValue: ImageAssetPicker.ImageValue? {
            guard case let .known(.image(image)) = value else { return nil }
            return ImageAssetPicker.ImageValue(
                id: id,
                image: image,
                importedImage: importedImage
            )
        }

        public func imageInfoState(recordID: Event.ID?) -> ImageInfo.State? {
            guard let imageValue else { return nil }
            return ImageInfo.State(
                id: id,
                image: imageValue.image,
                configuration: .allImages,
                sourceLabel: imageValue.displaySource,
                recordID: recordID,
                previewData: importedImage?.data
            )
        }

        public mutating func updateImageInfo(_ image: OME.Image) {
            guard case .known(.image) = value else { return }
            value = .known(.image(image))
            importedImage?.image = image
        }

        public var title: String {
            switch value {
            case let .known(.external(external)):
                external.title?.nilIfEmpty ?? "External media"
            case .known(.record):
                "AT Protocol record"
            case .known(.image):
                "Image"
            case .unknown:
                "Unrecognized media"
            }
        }

        public var subtitle: String? {
            switch value {
            case let .known(.external(external)):
                external.uri.absoluteString
            case let .known(.record(reference)):
                reference.uri.description
            case .known(.image), .unknown:
                nil
            }
        }

        public var canEditLink: Bool {
            switch value {
            case .known(.external), .known(.record): true
            case .known(.image), .unknown: false
            }
        }
    }

    public struct MediaDraft: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case external
            case record
        }

        public init(kind: Kind, entryID: UUID? = nil) {
            @Dependency(\.uuid) var uuid
            self.kind = kind
            self.entryID = entryID
            self.thumbnailID = uuid()
        }

        public init(entryID: UUID, external: OME.Media.External) {
            self.init(kind: .external, entryID: entryID)
            uri = external.uri.absoluteString
            title = external.title ?? ""
            description = external.description ?? ""
            thumbnail = external.thumbnail
            if let thumbnail = external.thumbnail,
               case let .known(.url(url)) = thumbnail.source {
                thumbnailURL = url.absoluteString
                originalThumbnailURL = url.absoluteString
            }
            thumbnailAlt = external.thumbnail?.alt?.rawValue ?? ""
            originalMediaKind = external.mediaKind
            switch external.mediaKind {
            case let .some(.known(kind)): mediaKind = kind.rawValue
            case let .some(.unknown(value)): mediaKind = value.string ?? ""
            case nil: break
            }
            originalMediaKindString = mediaKind
        }

        public init(entryID: UUID, reference: OME.Media.RecordReference) {
            self.init(kind: .record, entryID: entryID)
            uri = reference.uri.description
        }

        public var kind: Kind
        public var entryID: UUID?
        public var thumbnailID: UUID
        public var uri = ""
        public var title = ""
        public var description = ""
        public var mediaKind = ""
        public var thumbnailURL = ""
        public var thumbnailAlt = ""
        public var removeThumbnail = false
        public var thumbnail: OME.Image? = nil
        private var originalMediaKind: Open<OME.Media.Kind>? = nil
        private var originalMediaKindString = ""
        private var originalThumbnailURL = ""

        public var validationMessage: String? {
            switch kind {
            case .record:
                guard let uri = ATProto.URI(uri.trimmingCharacters(in: .whitespacesAndNewlines)),
                      case .did = uri.authority,
                      uri.collection != nil,
                      uri.rkey != nil
                else { return "Enter a DID-based AT Protocol record URI." }
            case .external:
                guard Self.httpsURL(uri) != nil else {
                    return "Enter a public HTTPS media URL."
                }
                if !thumbnailURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   Self.httpsURL(thumbnailURL) == nil {
                    return "Enter a public HTTPS thumbnail URL."
                }
            }
            return nil
        }

        public func thumbnailImageInfoState(recordID: Event.ID?) -> ImageInfo.State? {
            guard let image = thumbnailImage else { return nil }
            return ImageInfo.State(
                id: thumbnailID,
                image: image,
                configuration: .allImages,
                sourceLabel: thumbnailURL.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                recordID: recordID
            )
        }

        public mutating func updateThumbnailImageInfo(_ image: OME.Image) {
            thumbnail = image
            thumbnailAlt = image.alt?.rawValue ?? ""
            removeThumbnail = false
            if case let .known(.url(url)) = image.source {
                thumbnailURL = url.absoluteString
            }
        }

        private var thumbnailImage: OME.Image? {
            guard !removeThumbnail else { return nil }
            let enteredURL = thumbnailURL.trimmingCharacters(in: .whitespacesAndNewlines)
            var image: OME.Image?
            if enteredURL == originalThumbnailURL {
                image = thumbnail
            } else if let url = Self.httpsURL(enteredURL) {
                image = thumbnail ?? OME.Image(
                    source: .known(.url(url)),
                    role: .known(.photo),
                    renderingMode: .known(.original)
                )
                image?.source = .known(.url(url))
            } else if originalThumbnailURL.isEmpty {
                image = thumbnail
            }
            image?.alt = thumbnailAlt.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty.map(OME.AltText.init(rawValue:))
            return image
        }

        public func value() -> Open<OME.Media>? {
            guard validationMessage == nil else { return nil }
            switch kind {
            case .record:
                guard let uri = ATProto.URI(uri.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    return nil
                }
                return .known(.record(.init(uri: uri)))
            case .external:
                guard let url = Self.httpsURL(uri) else { return nil }
                var external = OME.Media.External(uri: url)
                external.title = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                external.description = description.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                let kind = mediaKind.trimmingCharacters(in: .whitespacesAndNewlines)
                if kind == originalMediaKindString {
                    external.mediaKind = originalMediaKind
                } else if !kind.isEmpty {
                    if let known = OME.Media.Kind(rawValue: kind) {
                        external.mediaKind = .known(known)
                    } else {
                        external.mediaKind = .unknown(.string(kind))
                    }
                }
                external.thumbnail = thumbnailImage
                return .known(.external(external))
            }
        }

        private static func httpsURL(_ string: String) -> URL? {
            guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme?.lowercased() == "https",
                  let host = url.host,
                  !host.isEmpty
            else { return nil }
            return url
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
