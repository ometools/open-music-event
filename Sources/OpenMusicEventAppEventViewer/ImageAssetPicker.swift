import ATProtoTypes
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct ImageAssetPicker {
    public init() {}

    public struct State: Sendable {
        public init(
            configuration: ImportImages.Configuration,
            recordID: Event.ID? = nil,
            images: [ImageValue] = []
        ) {
            self.configuration = configuration
            self.recordID = recordID
            self.images = images
        }

        public init(
            configuration: ImportImages.Configuration,
            recordImages: [OME.Image]?,
            recordID: Event.ID? = nil
        ) {
            self.init(
                configuration: configuration,
                recordID: recordID,
                images: Self.imageValues(
                    for: recordImages,
                    configuration: configuration
                )
            )
        }

        public var configuration: ImportImages.Configuration
        public var recordID: Event.ID?
        public var images: [ImageValue]

        var addButtonTitle: String {
            switch configuration.cardinality {
            case .single:
                images.isEmpty ? "Choose \(configuration.role.imageAssetPickerTitle)" : "Replace \(configuration.role.imageAssetPickerTitle)"
            case .multiple:
                "Add \(configuration.role.imageAssetPickerPluralTitle)"
            }
        }

        var canAddImages: Bool {
            switch configuration.cardinality {
            case .single:
                images.isEmpty
            case .multiple:
                true
            }
        }

        var sectionTitle: String {
            configuration.role.imageAssetPickerSectionTitle
        }

        mutating func append(_ importedImages: [ImportImages.ImportedImage]) {
            let imageValues = importedImages.map { ImageValue(importedImage: $0) }

            switch configuration.cardinality {
            case .single:
                images = imageValues.last.map { [$0] } ?? []
            case .multiple:
                images.append(contentsOf: imageValues)
            }
        }

        func importImagesState() -> ImportImages.State {
            ImportImages.State(configuration: configuration)
        }

        func imageInfoState(for id: ImageValue.ID) -> ImageInfo.State? {
            guard let image = images.first(where: { $0.id == id }) else {
                return nil
            }

            return ImageInfo.State(
                id: image.id,
                image: image.image,
                configuration: configuration.imageInfoConfiguration,
                sourceLabel: image.displaySource,
                recordID: recordID,
                previewData: image.importedImage?.data
            )
        }

        mutating func updateImageInfo(
            imageID: ImageValue.ID,
            image: OME.Image
        ) {
            guard let index = images.firstIndex(where: { $0.id == imageID }) else {
                return
            }
            images[index].image = image
            images[index].importedImage?.image = image
        }

        mutating func replaceURLString(_ urlString: String) {
            let value = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = value.nilIfEmpty.flatMap(URL.init(string:)) else {
                images = []
                return
            }

            let image = ImageValue(image: configuration.image(url: url))

            switch configuration.cardinality {
            case .single:
                images = [image]
            case .multiple:
                images.append(image)
            }
        }

        var firstURLString: String {
            guard let image = images.first?.image,
                  case let .known(.url(url)) = image.source else { return "" }
            return url.absoluteString
        }

        private static func imageValues(
            for images: [OME.Image]?,
            configuration: ImportImages.Configuration
        ) -> [ImageValue] {
            (images ?? [])
                .filter {
                    $0.role == .known(configuration.role)
                        || (configuration.role == .photo && $0.role == nil)
                }
                .map { ImageValue(image: $0) }
        }
    }

    public struct ImageValue: Equatable, Identifiable, Sendable {
        public init(
            id: UUID? = nil,
            image: OME.Image,
            importedImage: ImportImages.ImportedImage? = nil,
            sourceLabel: String? = nil
        ) {
            @Dependency(\.uuid) var uuid
            let id = id ?? uuid()
            self.image = image
            self.id = id
            self.importedImage = importedImage
            self.sourceLabel = sourceLabel
        }

        public init(importedImage: ImportImages.ImportedImage) {
            var importedImage = importedImage
            importedImage.image.title = importedImage.trimmedTitle.nilIfEmpty
            self.init(
                id: importedImage.id,
                image: importedImage.image,
                importedImage: importedImage,
                sourceLabel: importedImage.sourceLabel
            )
        }

        public var image: OME.Image
        public var id: UUID
        public var importedImage: ImportImages.ImportedImage?
        public var sourceLabel: String?

        var displaySource: String {
            sourceLabel
                ?? importedImage?.sourceLabel
                ?? image.sourceURL.map { url in
                    url.isFileURL ? url.lastPathComponent : url.absoluteString
                }
                ?? image.role?.knownRole?.imageAssetPickerTitle
                ?? "Image"
        }
    }

    public enum Action {
        case addButtonTapped
        case imageInfoButtonTapped(ImageValue.ID)
        case removeButtonTapped(ImageValue.ID)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addButtonTapped:
                break

            case .imageInfoButtonTapped:
                break

            case let .removeButtonTapped(id):
                state.images.removeAll { $0.id == id }
            }
        }
    }
}

public struct ImageAssetPickerSection: View {
    @Bindable var store: StoreOf<ImageAssetPicker>

    public init(store: StoreOf<ImageAssetPicker>) {
        self.store = store
    }

    public var body: some View {
        Section(store.sectionTitle) {
            ForEach(store.images) { image in
                ImageAssetPickerRowView(
                    recordID: store.recordID,
                    image: image
                ) {
                    store.send(.imageInfoButtonTapped(image.id))
                } onRemove: {
                    store.send(.removeButtonTapped(image.id))
                }
            }

            if store.canAddImages {
                Button {
                    store.send(.addButtonTapped)
                } label: {
                    Label(store.addButtonTitle, systemImage: "photo.badge.plus")
                }
            }
        }
    }
}

struct ImageAssetPickerRowView: View {
    let recordID: Event.ID?
    let image: ImageAssetPicker.ImageValue
    let onEditInfo: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(image.image.role?.knownRole?.imageAssetPickerTitle ?? "Image")
                    .font(.headline)

                Text(image.displaySource)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onEditInfo()
            } label: {
                Image(systemName: "info.circle")
                    .accessibilityLabel("Image Info")
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .accessibilityLabel("Remove Image")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let importedImage = image.importedImage {
            ImportedImageThumbnail(data: importedImage.data)
        } else {
            ImageAssetAsyncImage(
                image: recordID.flatMap { image.image.displayImageAsset(recordID: $0) },
                contentMode: .fit
            ) {
                ImageAssetPickerThumbnailPlaceholder()
            }
        }
    }
}

struct ImageAssetPickerThumbnailPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.secondary.opacity(0.12))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }
}

private extension ImportImages.Configuration {
    func image(url: URL) -> OME.Image {
        OME.Image(
            source: .known(.url(url)),
            role: .known(role),
            renderingMode: .known(renderingMode),
            appearance: appearance.map(Open.known)
        )
    }
}

private extension OME.Image {
    var sourceURL: URL? {
        guard case let .known(.url(url)) = source else { return nil }
        return url
    }
}

private extension Open<OME.Image.Role> {
    var knownRole: OME.Image.Role? {
        guard case let .known(role) = self else { return nil }
        return role
    }
}

private extension OME.Image.Role {
    var imageAssetPickerPluralTitle: String {
        switch self {
        case .hero:
            return "Heroes"
        case .icon:
            return "Icons"
        case .logo:
            return "Logos"
        case .photo:
            return "Photos"
        case .poster:
            return "Posters"
        case .siteMap:
            return "Site Maps"
        }
    }

    var imageAssetPickerSectionTitle: String {
        switch self {
        case .hero:
            return "Hero Image"
        case .icon:
            return "Icon Image"
        case .logo:
            return "Logo"
        case .photo:
            return "Photos"
        case .poster:
            return "Posters"
        case .siteMap:
            return "Site Map"
        }
    }

    var imageAssetPickerTitle: String {
        switch self {
        case .hero:
            return "Hero"
        case .icon:
            return "Icon"
        case .logo:
            return "Logo"
        case .photo:
            return "Photo"
        case .poster:
            return "Poster"
        case .siteMap:
            return "Site Map"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
