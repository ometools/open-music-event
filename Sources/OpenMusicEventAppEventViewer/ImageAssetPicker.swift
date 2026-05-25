import ComposableArchitecture2
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventImages
import SwiftUI

@Feature
public struct ImageAssetPicker {
    public init() {}

    public struct State {
        public init(
            configuration: ImportImages.Configuration,
            cacheContext: LocalImageCacheContext? = nil,
            imageInfo: Spawn<ImageInfo>? = nil,
            images: [ImageValue] = [],
            importImages: Spawn<ImportImages>? = nil
        ) {
            self.cacheContext = cacheContext
            self.configuration = configuration
            self.imageInfo = imageInfo
            self.images = images
            self.importImages = importImages
        }

        public init(
            configuration: ImportImages.Configuration,
            assets: [OMERecord.ImageAsset]?,
            cacheContext: LocalImageCacheContext? = nil
        ) {
            self.init(
                configuration: configuration,
                cacheContext: cacheContext,
                images: Self.imageValues(
                    for: assets,
                    configuration: configuration,
                    cacheContext: cacheContext
                )
            )
        }

        public var cacheContext: LocalImageCacheContext?
        public var configuration: ImportImages.Configuration
        public var imageInfo: Spawn<ImageInfo>?
        public var images: [ImageValue]
        public var importImages: Spawn<ImportImages>?

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
            let imageValues = importedImages.map {
                ImageValue(
                    importedImage: $0,
                    usesUniqueAssetKey: configuration.cardinality == .multiple
                )
            }

            switch configuration.cardinality {
            case .single:
                images = imageValues.last.map { [$0] } ?? []
            case .multiple:
                images.append(contentsOf: imageValues)
            }
        }

        public func materializedImages(
            context: LocalImageCacheContext
        ) throws -> (images: [OMERecord.ImageAsset], blobs: [LocalImageBlob]) {
            var assets: [OMERecord.ImageAsset] = []
            var blobs: [LocalImageBlob] = []

            for image in images {
                if let importedImage = image.importedImage {
                    var request = importedImage.localImageImportRequest
                    request.assetKeyDiscriminator = image.assetKeyDiscriminator
                    let materializedImage = try materializeImportedLocalImage(
                        request,
                        context: context
                    )
                    assets.append(materializedImage.image)
                    blobs.append(materializedImage.blob)
                } else {
                    assets.append(
                        image.asset.resolvingAssetKey(
                            context: context,
                            discriminator: image.assetKeyDiscriminator
                        )
                    )
                }
            }

            return (assets, blobs)
        }

        mutating func replaceURLString(_ urlString: String) {
            let value = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = value.nilIfEmpty.flatMap(URL.init(string:)) else {
                images = []
                return
            }

            let image = ImageValue(
                asset: configuration.imageAsset(url: url),
                usesUniqueAssetKey: configuration.cardinality == .multiple
            )

            switch configuration.cardinality {
            case .single:
                images = [image]
            case .multiple:
                images.append(image)
            }
        }

        var firstURLString: String {
            images.first?.asset.url?.absoluteString ?? ""
        }

        private static func imageValues(
            for assets: [OMERecord.ImageAsset]?,
            configuration: ImportImages.Configuration,
            cacheContext: LocalImageCacheContext?
        ) -> [ImageValue] {
            (assets ?? [])
                .filter { $0.role == configuration.role }
                .map { asset in
                    var image = ImageValue(
                        asset: asset,
                        usesUniqueAssetKey: configuration.cardinality == .multiple
                    )
                    if let cacheContext {
                        image.asset = image.asset.resolvingAssetKey(
                            context: cacheContext,
                            discriminator: image.assetKeyDiscriminator
                        )
                    }
                    return image
                }
        }
    }

    public struct ImageValue: Equatable, Identifiable, Sendable {
        public init(
            id: UUID = UUID(),
            asset: OMERecord.ImageAsset,
            importedImage: ImportImages.ImportedImage? = nil,
            sourceLabel: String? = nil,
            usesUniqueAssetKey: Bool = false
        ) {
            self.asset = asset
            self.assetKeyDiscriminator = usesUniqueAssetKey && asset.assetKey == nil
                ? id.uuidString.lowercased()
                : nil
            self.id = id
            self.importedImage = importedImage
            self.sourceLabel = sourceLabel
        }

        public init(
            importedImage: ImportImages.ImportedImage,
            usesUniqueAssetKey: Bool = false
        ) {
            self.init(
                id: importedImage.id,
                asset: importedImage.asset,
                importedImage: importedImage,
                sourceLabel: importedImage.sourceLabel,
                usesUniqueAssetKey: usesUniqueAssetKey
            )
        }

        public var asset: OMERecord.ImageAsset
        public var assetKeyDiscriminator: String?
        public var id: UUID
        public var importedImage: ImportImages.ImportedImage?
        public var sourceLabel: String?

        var displaySource: String {
            sourceLabel
                ?? importedImage?.sourceLabel
                ?? asset.url?.lastPathComponent.nilIfEmpty
                ?? asset.url?.absoluteString
                ?? asset.role.imageAssetPickerTitle
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
                state.importImages = Spawn(
                    ImportImages.State(configuration: state.configuration)
                )

            case let .imageInfoButtonTapped(id):
                guard let image = state.images.first(where: { $0.id == id }) else {
                    return
                }
                state.imageInfo = Spawn(
                    ImageInfo.State(
                        id: image.id,
                        asset: image.asset,
                        configuration: state.configuration.imageInfoConfiguration,
                        sourceLabel: image.displaySource
                    )
                )

            case let .removeButtonTapped(id):
                state.images.removeAll { $0.id == id }
            }
        }
        .ifLet(\.imageInfo) {
            ImageInfo { imageID, asset in
                try store.modify {
                    guard let index = $0.images.firstIndex(where: { $0.id == imageID }) else {
                        return
                    }
                    $0.images[index].asset = asset
                    $0.images[index].importedImage?.asset = asset
                }
            }
        }
        .ifLet(\.importImages) {
            ImportImages { images in
                try store.modify {
                    $0.append(images)
                }
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
                    cacheContext: store.cacheContext,
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
        .sheet(isPresented: $store.importImages.isPresented) {
            if let importStore = store.spawn(\.importImages) {
                NavigationStack {
                    ImportImagesView(store: importStore)
                }
            }
        }
        .sheet(isPresented: $store.imageInfo.isPresented) {
            if let imageInfoStore = store.spawn(\.imageInfo) {
                NavigationStack {
                    ImageInfoView(store: imageInfoStore)
                }
            }
        }
    }
}

struct ImageAssetPickerRowView: View {
    let cacheContext: LocalImageCacheContext?
    let image: ImageAssetPicker.ImageValue
    let onEditInfo: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(image.asset.role.imageAssetPickerTitle)
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
                asset: image.asset,
                cacheContext: cacheContext,
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
    func imageAsset(url: URL) -> OMERecord.ImageAsset {
        OMERecord.ImageAsset(
            source: .url(url),
            role: role,
            renderKind: renderKind,
            appearance: appearance,
            materializationPolicy: materializationPolicy
        )
    }
}

private extension OMERecord.ImageAsset {
    func resolvingAssetKey(
        context: LocalImageCacheContext,
        discriminator: String?
    ) -> Self {
        guard assetKey == nil else { return self }
        var image = self
        image.assetKey = LocalImageBlob.assetKey(
            organizerID: context.organizerID,
            eventID: context.eventID,
            parentKind: context.parentKind,
            parentLocalID: context.parentLocalID,
            role: role,
            discriminator: discriminator
        )
        return image
    }
}

private extension OMERecord.ImageAsset.Role {
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
