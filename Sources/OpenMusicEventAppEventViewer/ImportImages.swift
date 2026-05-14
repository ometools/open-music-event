import ComposableArchitecture2
import Foundation
import OpenMusicEventDatabase
import SwiftUI

#if !SKIP && canImport(AppKit)
import AppKit
#endif

#if !SKIP && canImport(PhotosUI)
import PhotosUI
#endif

#if !SKIP && canImport(UIKit)
import UIKit
#endif

#if !SKIP && canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

@Feature
public struct ImportImages {
    public init(
        onSave: @escaping @Sendable ([ImportedImage]) async throws -> Void
    ) {
        self.onSave = onSave
    }

    public struct State {
        public init(
            configuration: Configuration,
            images: [ImportedImage] = []
        ) {
            self.configuration = configuration
            self.images = images
        }

        public var configuration: Configuration
        public var errorMessage: String?
        public var images: [ImportedImage]
        public var isImporting = false
        public var isSaving = false

        public var canSave: Bool {
            !images.isEmpty && !isImporting && !isSaving
        }

        mutating func append(_ importedImages: [ImportedImage]) {
            switch configuration.cardinality {
            case .single:
                images = importedImages.last.map { [$0] } ?? []
            case .multiple:
                images.append(contentsOf: importedImages)
            }
        }
    }

    public enum Action {
        case cancelButtonTapped
        case imageImportFailed(String)
        case imageImportStarted
        case imagesImported([ImportedImage])
        case removeImageButtonTapped(ImportedImage.ID)
        case saveButtonTapped
    }

    let onSave: @Sendable ([ImportedImage]) async throws -> Void

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case let .imageImportFailed(message):
                state.errorMessage = message
                state.isImporting = false

            case .imageImportStarted:
                state.errorMessage = nil
                state.isImporting = true

            case let .imagesImported(images):
                state.append(images)
                state.errorMessage = nil
                state.isImporting = false

            case let .removeImageButtonTapped(id):
                state.images.removeAll { $0.id == id }

            case .saveButtonTapped:
                guard state.canSave else { return }

                let images = state.images
                state.errorMessage = nil
                state.isSaving = true

                store.addTask {
                    do {
                        try await onSave(images)
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to import images."
                            $0.isSaving = false
                        }
                    }
                }
            }
        }
    }
}

public extension ImportImages {
    enum Cardinality: Equatable, Sendable {
        case single
        case multiple
    }

    struct Configuration: Equatable, Sendable {
        public init(
            cardinality: Cardinality,
            title: String,
            role: OMERecord.ImageAsset.Role,
            renderKind: OMERecord.ImageAsset.RenderKind,
            appearance: OMERecord.ImageAsset.Appearance? = nil,
            materializationPolicy: OMERecord.ImageAsset.MaterializationPolicy
        ) {
            self.cardinality = cardinality
            self.title = title
            self.role = role
            self.renderKind = renderKind
            self.appearance = appearance
            self.materializationPolicy = materializationPolicy
        }

        public var cardinality: Cardinality
        public var title: String
        public var role: OMERecord.ImageAsset.Role
        public var renderKind: OMERecord.ImageAsset.RenderKind
        public var appearance: OMERecord.ImageAsset.Appearance?
        public var materializationPolicy: OMERecord.ImageAsset.MaterializationPolicy

        public static var posters: Self {
            Self(
                cardinality: .multiple,
                title: "Add Posters",
                role: .poster,
                renderKind: .fullImage,
                materializationPolicy: .lazy
            )
        }

        var allowsMultipleSelection: Bool {
            cardinality == .multiple
        }

        func importedImage(
            id: UUID = UUID(),
            title: String? = nil,
            sourceName: String? = nil,
            sourceURL: URL? = nil,
            mimeType: String,
            data: Data
        ) -> ImportedImage {
            ImportedImage(
                id: id,
                title: title,
                sourceName: sourceName,
                sourceURL: sourceURL,
                mimeType: mimeType,
                data: data,
                role: role,
                renderKind: renderKind,
                appearance: appearance,
                materializationPolicy: materializationPolicy
            )
        }
    }

    struct ImportedImage: Identifiable, Equatable, Sendable {
        public init(
            id: UUID = UUID(),
            title: String? = nil,
            sourceName: String? = nil,
            sourceURL: URL? = nil,
            mimeType: String,
            data: Data,
            role: OMERecord.ImageAsset.Role = .photo,
            renderKind: OMERecord.ImageAsset.RenderKind = .fullImage,
            appearance: OMERecord.ImageAsset.Appearance? = nil,
            materializationPolicy: OMERecord.ImageAsset.MaterializationPolicy = .lazy
        ) {
            self.id = id
            self.title = title ?? sourceName?.deletingPathExtension ?? ""
            self.sourceName = sourceName
            self.sourceURL = sourceURL
            self.mimeType = mimeType
            self.data = data
            self.role = role
            self.renderKind = renderKind
            self.appearance = appearance
            self.materializationPolicy = materializationPolicy
        }

        public var id: UUID
        public var title: String
        public var sourceName: String?
        public var sourceURL: URL?
        public var mimeType: String
        public var data: Data
        public var role: OMERecord.ImageAsset.Role
        public var renderKind: OMERecord.ImageAsset.RenderKind
        public var appearance: OMERecord.ImageAsset.Appearance?
        public var materializationPolicy: OMERecord.ImageAsset.MaterializationPolicy

        public var trimmedTitle: String {
            title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public var suggestedIDSource: String {
            trimmedTitle.nilIfEmpty
                ?? sourceName?.deletingPathExtension.nilIfEmpty
                ?? "poster"
        }

        public var sourceLabel: String {
            sourceName
                ?? sourceURL?.lastPathComponent
                ?? "Photos"
        }

        public var localImageImportRequest: LocalImageImportRequest {
            LocalImageImportRequest(
                data: data,
                mimeType: mimeType,
                sourceURL: sourceURL,
                role: role,
                renderKind: renderKind,
                appearance: appearance,
                materializationPolicy: materializationPolicy
            )
        }
    }
}

public struct ImportImagesView: View {
    @Bindable var store: StoreOf<ImportImages>
    @State var isFileImporterPresented = false

    #if !SKIP && canImport(PhotosUI)
    @State var selectedPhotoItems: [PhotosPickerItem] = []
    #endif

    public init(store: StoreOf<ImportImages>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section {
                importControls
            }

            if !store.images.isEmpty {
                Section("Images") {
                    ForEach($store.images) { $image in
                        ImportImageRowView(image: $image) {
                            store.send(.removeImageButtonTapped(image.id))
                        }
                    }
                }
            }

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .disabled(store.isSaving)
        .navigationTitle(store.configuration.title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    store.send(.cancelButtonTapped)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if store.isSaving {
                    ProgressView()
                } else {
                    Button("Add") {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.canSave)
                }
            }
        }
        .importImagesFileImporter(
            isPresented: $isFileImporterPresented,
            allowsMultipleSelection: store.configuration.allowsMultipleSelection,
            onCompletion: fileImportCompleted
        )
        #if !SKIP && canImport(PhotosUI)
        .onChange(of: selectedPhotoItems) { _, items in
            photoItemsChanged(items)
        }
        #endif
    }

    @ViewBuilder
    var importControls: some View {
        #if !SKIP && canImport(PhotosUI)
        PhotosPicker(
            selection: $selectedPhotoItems,
            maxSelectionCount: store.configuration.allowsMultipleSelection ? nil : 1,
            matching: .images
        ) {
            Label("Choose Photos", systemImage: "photo.on.rectangle")
        }
        #endif

        #if !SKIP && canImport(UniformTypeIdentifiers)
        Button {
            isFileImporterPresented = true
        } label: {
            Label("Choose Files", systemImage: "folder")
        }
        #endif

        #if SKIP || (!canImport(PhotosUI) && !canImport(UniformTypeIdentifiers))
        ContentUnavailableView(
            "Image Import",
            systemImage: "photo",
            description: Text("Image import is not available on this platform yet.")
        )
        #endif
    }

    #if !SKIP && canImport(UniformTypeIdentifiers)
    func fileImportCompleted(_ result: Result<[URL], any Error>) {
        switch result {
        case let .success(urls):
            do {
                let images = try urls.map(importedImage(from:))
                if !images.isEmpty {
                    store.send(.imagesImported(images))
                }
            } catch {
                store.send(.imageImportFailed("Unable to import selected files."))
            }

        case .failure:
            store.send(.imageImportFailed("Unable to import selected files."))
        }
    }

    func importedImage(from url: URL) throws -> ImportImages.ImportedImage {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return store.configuration.importedImage(
            sourceName: url.lastPathComponent,
            sourceURL: url,
            mimeType: imageMimeType(for: url),
            data: try Data(contentsOf: url)
        )
    }

    func imageMimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }
        return fallbackImageMimeType(forPathExtension: url.pathExtension)
    }
    #endif

    #if !SKIP && canImport(PhotosUI)
    func photoItemsChanged(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        store.send(.imageImportStarted)

        Task {
            var importedImages: [ImportImages.ImportedImage] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    continue
                }
                importedImages.append(
                    store.configuration.importedImage(
                        sourceName: nil,
                        sourceURL: nil,
                        mimeType: item.supportedContentTypes.first?.preferredMIMEType ?? "application/octet-stream",
                        data: data
                    )
                )
            }

            await MainActor.run {
                selectedPhotoItems = []
                if importedImages.isEmpty {
                    store.send(.imageImportFailed("Unable to import selected photos."))
                } else {
                    store.send(.imagesImported(importedImages))
                }
            }
        }
    }
    #endif
}

struct ImportImageRowView: View {
    @Binding var image: ImportImages.ImportedImage
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ImportedImageThumbnail(data: image.data)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Title", text: $image.title)

                Text(image.sourceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

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
}

struct ImportedImageThumbnail: View {
    let data: Data

    var body: some View {
        Group {
            #if !SKIP && canImport(UIKit)
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
            #elseif !SKIP && canImport(AppKit)
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    var placeholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.secondary.opacity(0.12))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }
}

extension View {
    @ViewBuilder
    func importImagesFileImporter(
        isPresented: Binding<Bool>,
        allowsMultipleSelection: Bool,
        onCompletion: @escaping (Result<[URL], any Error>) -> Void
    ) -> some View {
        #if !SKIP && canImport(UniformTypeIdentifiers)
        self.fileImporter(
            isPresented: isPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: allowsMultipleSelection,
            onCompletion: onCompletion
        )
        #else
        self
        #endif
    }
}

func fallbackImageMimeType(forPathExtension pathExtension: String) -> String {
    switch pathExtension.lowercased() {
    case "png":
        return "image/png"
    case "jpg", "jpeg":
        return "image/jpeg"
    case "webp":
        return "image/webp"
    case "gif":
        return "image/gif"
    case "svg":
        return "image/svg+xml"
    default:
        return "application/octet-stream"
    }
}

private extension String {
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
