import ATProto
import ATProtoTypes
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct EditSiteMap {
    public init() {}

    public struct State {
        public init(event: Event) {
            self.original = event
            self.title = event.siteMap?.title ?? ""
            self.styles = (event.siteMap?.styles ?? []).map(StyleDraft.init)
            self.defaultStyleID = event.siteMap?.defaultStyleID
        }

        let original: Event
        var title: String
        var styles: [StyleDraft]
        var defaultStyleID: String?
        var editingStyleID: String?
        var editingImageStyleID: String?
        var destination: Destination.State?
        var errorMessage: String?
        var isRemovingMap = false
        var isSaving = false

        var validationMessage: String? {
            if isRemovingMap { return nil }
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Enter a site map title."
            }
            if styles.isEmpty { return "Add at least one map style." }
            for style in styles {
                if style.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "Enter a title for each map style."
                }
                if style.imageForInfo == nil {
                    return "Choose an image or enter an HTTPS image URL for each style."
                }
                if !style.sourceURLString.isEmpty && !style.hasValidURL {
                    return "Map image URLs must use HTTPS."
                }
            }
            return nil
        }

        var canSubmit: Bool { !isSaving && validationMessage == nil }
    }

    public struct StyleDraft: Equatable, Identifiable {
        init(_ style: Event.SiteMap.Style) {
            self.id = style.id
            self.title = style.title
            self.image = style.image
            if case let .known(.url(url)) = style.image.source {
                self.sourceURLString = url.absoluteString
            } else {
                self.sourceURLString = ""
            }
        }

        init(id: String) {
            self.id = id
            self.title = ""
            self.image = nil
            self.sourceURLString = ""
        }

        public let id: String
        var title: String
        var image: OME.Image?
        var sourceURLString: String
        var importedImage: ImportImages.ImportedImage?

        var hasValidURL: Bool {
            guard let url = URL(string: sourceURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return false
            }
            return url.scheme == "https" && url.host != nil
        }

        var imageForInfo: OME.Image? {
            let value = sourceURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                guard let url = URL(string: value), url.scheme == "https", url.host != nil else {
                    return nil
                }
                var result = image ?? OME.Image(source: .known(.url(url)), role: .known(.siteMap))
                result.source = .known(.url(url))
                result.role = .known(.siteMap)
                return result
            }
            guard let image else { return nil }
            if importedImage == nil, case .known(.url) = image.source { return nil }
            return image
        }

        func preparedStyle() throws -> Event.SiteMap.Style {
            guard var image = imageForInfo else { throw SaveError.invalidImage }
            if let importedImage, sourceURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let blob = try stageLocalImageBlob(
                    importedImage.data,
                    mimeType: ATProto.MIMEType(rawValue: importedImage.mimeType)
                )
                image.source = .known(.blob(blob))
            }
            image.role = .known(.siteMap)
            return Event.SiteMap.Style(
                id: id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                image: image
            )
        }
    }

    public enum Action {
        case addStyleButtonTapped
        case cancelButtonTapped
        case deleteStyleButtonTapped(String)
        case destination(Destination.Action)
        case editStyleButtonTapped(String)
        case imageInfoButtonTapped(String)
        case importImageButtonTapped(String)
        case moveStyleButtonTapped(String, Int)
        case removeMapButtonTapped
        case restoreMapButtonTapped
        case saveButtonTapped
    }

    @Feature
    public enum Destination {
        case imageInfo(ImageInfo)
        case importImages(ImportImages)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.uuid) var uuid

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addStyleButtonTapped:
                let id = uuid().uuidString.lowercased()
                state.styles.append(StyleDraft(id: id))
                state.editingStyleID = id
                state.isRemovingMap = false

            case .cancelButtonTapped:
                store.addTask { try store.dismiss() }

            case let .deleteStyleButtonTapped(id):
                state.styles.removeAll { $0.id == id }
                if state.defaultStyleID == id { state.defaultStyleID = nil }
                if state.editingStyleID == id { state.editingStyleID = nil }

            case .destination:
                break

            case let .editStyleButtonTapped(id):
                guard state.styles.contains(where: { $0.id == id }) else { return }
                state.editingStyleID = id

            case let .imageInfoButtonTapped(id):
                guard let style = state.styles.first(where: { $0.id == id }),
                      let image = style.imageForInfo else { return }
                state.editingImageStyleID = id
                state.destination = .imageInfo(ImageInfo.State(
                    image: image,
                    configuration: .init(
                        allowedRoles: [.siteMap],
                        allowedRenderingModes: [.original]
                    ),
                    recordID: state.original.id,
                    previewData: style.importedImage?.data
                ))

            case let .importImageButtonTapped(id):
                guard state.styles.contains(where: { $0.id == id }) else { return }
                state.editingImageStyleID = id
                state.destination = .importImages(ImportImages.State(configuration: .init(
                    cardinality: .single,
                    title: "Choose Map Image",
                    role: .siteMap,
                    renderingMode: .original
                )))

            case let .moveStyleButtonTapped(id, offset):
                guard let index = state.styles.firstIndex(where: { $0.id == id }),
                      state.styles.indices.contains(index + offset) else { return }
                state.styles.swapAt(index, index + offset)

            case .removeMapButtonTapped:
                guard state.original.siteMap != nil else { return }
                state.isRemovingMap = true

            case .restoreMapButtonTapped:
                state.isRemovingMap = false

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                if let message = state.validationMessage {
                    state.errorMessage = message
                    return
                }
                let original = state.original
                let title = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let styles = state.styles
                let defaultStyleID = state.defaultStyleID
                let isRemovingMap = state.isRemovingMap
                state.errorMessage = nil
                state.isSaving = true
                store.addTask {
                    do {
                        try database.write { db in
                            guard var event = try Event.find(original.id).fetchOne(db) else {
                                throw SaveError.deleted
                            }
                            guard event.siteMap == original.siteMap else {
                                throw SaveError.changed
                            }
                            if isRemovingMap {
                                event.siteMap = nil
                            } else {
                                let map = Event.SiteMap(
                                    title: title,
                                    styles: try styles.map { try $0.preparedStyle() },
                                    defaultStyleID: defaultStyleID
                                )
                                try map.validate()
                                event.siteMap = map
                            }
                            try event.validateReferences()
                            try Event.upsert { event }.execute(db)
                        }
                        try store.modify { $0.isSaving = false }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = (error as? SaveError)?.message
                                ?? "Unable to save the site map."
                            $0.isSaving = false
                        }
                    }
                }
            }
        }
        .ifLet(\.destination) {
            EmptyFeature()
                .ifCaseLet(\.imageInfo) {
                    ImageInfo { _, image in
                        try store.modify {
                            guard let id = $0.editingImageStyleID,
                                  let index = $0.styles.firstIndex(where: { $0.id == id }) else {
                                return
                            }
                            $0.styles[index].image = image
                        }
                    }
                }
                .ifCaseLet(\.importImages) {
                    ImportImages()
                }
        }
        .onEvent(ImportedImagesSubmitted.self) { images, state in
            guard case .importImages = state.destination,
                  let id = state.editingImageStyleID,
                  let index = state.styles.firstIndex(where: { $0.id == id }),
                  let image = images.last else { return }
            state.styles[index].image = image.image
            state.styles[index].importedImage = image
            state.styles[index].sourceURLString = ""
        }
    }

    enum SaveError: Error {
        case changed, deleted, invalidImage

        var message: String {
            switch self {
            case .changed: "The site map changed while you were editing. Reopen it to edit the latest version."
            case .deleted: "This event is no longer available."
            case .invalidImage: "Choose an image or enter an HTTPS image URL for each style."
            }
        }
    }
}

public struct EditSiteMapView: View {
    @Bindable var store: StoreOf<EditSiteMap>

    public init(store: StoreOf<EditSiteMap>) {
        self.store = store
    }

    public var body: some View {
        Form {
            if store.isRemovingMap {
                Section {
                    Text("The site map will be removed when you save.")
                    Button("Keep Site Map") {
                        store.send(.restoreMapButtonTapped)
                    }
                }
            } else {
                Section("Site Map") {
                    TextField("Title", text: $store.title)
                }
                Section("Styles") {
                    ForEach(store.styles) { style in
                        HStack {
                            Text(style.title.isEmpty ? "New Style" : style.title)
                            Spacer()
                            Menu {
                                Button("Edit") { store.send(.editStyleButtonTapped(style.id)) }
                                Button("Move Up") {
                                    store.send(.moveStyleButtonTapped(style.id, -1))
                                }
                                Button("Move Down") {
                                    store.send(.moveStyleButtonTapped(style.id, 1))
                                }
                                Button("Delete", role: .destructive) {
                                    store.send(.deleteStyleButtonTapped(style.id))
                                }
                            } label: {
                                Label("Style Actions", systemImage: "ellipsis.circle")
                                    .labelStyle(.iconOnly)
                            }
                        }
                    }
                    Button("Add Style") { store.send(.addStyleButtonTapped) }
                }
                if let index = store.styles.firstIndex(where: { $0.id == store.editingStyleID }) {
                    Section("Edit Style") {
                        TextField("Style Title", text: $store.styles[index].title)
                        TextField("Image URL", text: $store.styles[index].sourceURLString)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                        Button("Choose Image") {
                            store.send(.importImageButtonTapped(store.styles[index].id))
                        }
                        Button("Image Info") {
                            store.send(.imageInfoButtonTapped(store.styles[index].id))
                        }
                        .disabled(store.styles[index].imageForInfo == nil)
                    }
                }
                Section("Default Style") {
                    Picker("Default Style", selection: $store.defaultStyleID) {
                        Text("First style").tag(nil as String?)
                        ForEach(store.styles) { style in
                            Text(style.title.isEmpty ? "New Style" : style.title)
                                .tag(Optional(style.id))
                        }
                    }
                }
                if store.original.siteMap != nil {
                    Section {
                        Button("Remove Site Map", role: .destructive) {
                            store.send(.removeMapButtonTapped)
                        }
                    }
                }
            }
            if let message = store.errorMessage ?? store.validationMessage {
                Section {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .disabled(store.isSaving)
        .navigationTitle("Edit Site Map")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { store.send(.cancelButtonTapped) }
            }
            ToolbarItem(placement: .confirmationAction) {
                SubmitButton(isInProgress: store.isSaving, isDisabled: !store.canSubmit) {
                    store.send(.saveButtonTapped)
                }
            }
        }
        .sheet(item: $store.scope(\.destination).importImages) { importStore in
            NavigationStack { ImportImagesView(store: importStore) }
        }
        .sheet(item: $store.scope(\.destination).imageInfo) { imageInfoStore in
            NavigationStack { ImageInfoView(store: imageInfoStore) }
        }
    }
}
