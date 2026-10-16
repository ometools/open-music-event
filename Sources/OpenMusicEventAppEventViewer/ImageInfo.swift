import ATProtoTypes
import ComposableArchitecture2
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
import SwiftUI

#if !SKIP && canImport(AppKit)
import AppKit
#endif

#if !SKIP && canImport(UIKit)
import UIKit
#endif

@Feature
public struct ImageInfo {
    public init(
        onSave: @escaping (State.ID, OME.Image) throws -> Void = { _, _ in }
    ) {
        self.onSave = onSave
    }

    public struct State: Equatable, Identifiable, Sendable {
        public init(
            id: UUID = UUID(),
            image: OME.Image,
            configuration: Configuration = .allImages,
            sourceLabel: String? = nil,
            recordID: Event.ID? = nil,
            previewData: Data? = nil
        ) {
            self.id = id
            self.image = image
            self.configuration = configuration
            self.sourceLabel = sourceLabel
            self.recordID = recordID
            self.previewData = previewData
        }

        public var image: OME.Image
        public var recordID: Event.ID?
        public var configuration: Configuration
        public var errorMessage: String?
        public var id: UUID
        public var isSaving = false
        public var previewData: Data?
        public var sourceLabel: String?

        var appearanceOptions: [OME.Image.Appearance] {
            OME.Image.Appearance.allCases
        }

        var canSave: Bool {
            !isSaving
        }

        var canEditFocusPoint: Bool {
            image.renderingMode != .known(.template)
        }

        var renderingModeOptions: [OME.Image.RenderingMode] {
            configuration.renderingModeOptions(including: image.renderingMode)
        }

        var roleOptions: [OME.Image.Role] {
            configuration.roleOptions(including: image.role)
        }

        var roleRawValue: String {
            get {
                guard case let .known(role) = image.role else { return "" }
                return role.rawValue
            }
            set {
                guard newValue != roleRawValue else { return }
                image.role = OME.Image.Role(rawValue: newValue).map(Open.known)
            }
        }

        var isIcon: Bool {
            guard case .known(.icon) = image.role else { return false }
            return true
        }

        var iconCanRepresentSubjectWithoutLabel: Bool {
            get {
                guard case let .known(.icon(icon)) = image.role else { return false }
                return icon.canRepresentSubjectWithoutLabel == true
            }
            set {
                guard case let .known(.icon(icon)) = image.role else { return }
                var updated = icon
                updated.canRepresentSubjectWithoutLabel = newValue
                image.role = .known(.icon(updated))
            }
        }

        var renderingModeRawValue: String {
            get {
                guard case let .known(mode) = image.renderingMode else { return "" }
                return mode.rawValue
            }
            set {
                guard let mode = OME.Image.RenderingMode(rawValue: newValue) else { return }
                image.renderingMode = .known(mode)
            }
        }

        var appearanceRawValue: String? {
            get {
                guard case let .known(appearance) = image.appearance else { return nil }
                return appearance.rawValue
            }
            set { image.appearance = newValue.flatMap(OME.Image.Appearance.init(rawValue:)).map(Open.known) }
        }

        var title: String {
            get { image.title ?? "" }
            set {
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                image.title = trimmed.isEmpty ? nil : trimmed
            }
        }

        var alt: String {
            get { image.alt?.rawValue ?? "" }
            set {
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                image.alt = trimmed.isEmpty ? nil : OME.AltText(rawValue: trimmed)
            }
        }

        var sourceDescription: String? {
            if let sourceLabel { return sourceLabel }
            guard case let .known(source) = image.source else { return nil }
            switch source {
            case let .url(url): return url.absoluteString
            case let .blob(blob): return blob.ref.rawValue
            }
        }
    }

    public enum Action {
        case cancelButtonTapped
        case saveButtonTapped
    }

    let onSave: (State.ID, OME.Image) throws -> Void

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .saveButtonTapped:
                guard state.canSave else { return }

                let image = state.image
                let id = state.id
                state.errorMessage = nil
                state.isSaving = true

                store.addTask {
                    do {
                        try onSave(id, image)
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to save image info."
                            $0.isSaving = false
                        }
                    }
                }
            }
        }
    }
}

public extension ImageInfo {
    struct Configuration: Equatable, Sendable {
        public init(
            allowedRoles: [OME.Image.Role] = OME.Image.Role.allCases,
            allowedRenderingModes: [OME.Image.RenderingMode] = [.original, .template],
            allowsAppearance: Bool = true,
            showsTitle: Bool = true
        ) {
            self.allowedRoles = allowedRoles
            self.allowedRenderingModes = allowedRenderingModes
            self.allowsAppearance = allowsAppearance
            self.showsTitle = showsTitle
        }

        public var allowedRenderingModes: [OME.Image.RenderingMode]
        public var allowedRoles: [OME.Image.Role]
        public var allowsAppearance: Bool
        public var showsTitle: Bool

        public static var allImages: Self {
            Self()
        }

        public static var posters: Self {
            Self(
                allowedRoles: [.poster],
                allowedRenderingModes: [.original]
            )
        }

        public static var contributorLogo: Self {
            Self(
                allowedRoles: [.logo],
                allowedRenderingModes: [.template]
            )
        }

        public static var contributorPhoto: Self {
            Self(
                allowedRoles: [.photo],
                allowedRenderingModes: [.original]
            )
        }

        public static var stageHero: Self {
            Self(
                allowedRoles: [.hero],
                allowedRenderingModes: [.original]
            )
        }

        public static var stageLogo: Self {
            Self(
                allowedRoles: [.logo],
                allowedRenderingModes: [.template]
            )
        }

        public static var stagePoster: Self {
            Self(
                allowedRoles: [.poster],
                allowedRenderingModes: [.original]
            )
        }

        func renderingModeOptions(
            including mode: Open<OME.Image.RenderingMode>
        ) -> [OME.Image.RenderingMode] {
            guard case let .known(mode) = mode else { return allowedRenderingModes }
            return allowedRenderingModes.including(mode)
        }

        func roleOptions(
            including role: Open<OME.Image.Role>?
        ) -> [OME.Image.Role] {
            guard case let .known(role) = role else { return allowedRoles }
            guard !allowedRoles.contains(where: { $0.rawValue == role.rawValue }) else {
                return allowedRoles
            }
            return allowedRoles + [role]
        }
    }
}

public struct ImageInfoView: View {
    @Bindable var store: StoreOf<ImageInfo>

    public init(store: StoreOf<ImageInfo>) {
        self.store = store
    }

    public var body: some View {
        Form {
            ImageInfoEditorSection(store: store)
        }
        .disabled(store.isSaving)
        .navigationTitle("Image Info")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    store.send(.cancelButtonTapped)
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                SubmitButton(
                    isInProgress: store.isSaving,
                    isDisabled: !store.canSave
                ) {
                    store.send(.saveButtonTapped)
                }
            }
        }
    }
}

public struct ImageInfoEditorSection: View {
    @Bindable var store: StoreOf<ImageInfo>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    public init(store: StoreOf<ImageInfo>) {
        self.store = store
    }

    public var body: some View {
        Section("Image") {
            if showsTechnicalDetails, let sourceDescription = store.sourceDescription {
                LabeledContent("Source", value: sourceDescription)
            }

            if store.configuration.showsTitle {
                TextField("Title", text: $store.title)
            }

            TextField("Alt Text", text: $store.alt, axis: .vertical)

            if store.roleOptions.count > 1 {
                Picker("Type", selection: $store.roleRawValue) {
                    ForEach(store.roleOptions, id: \.rawValue) { role in
                        Text(role.imageInfoTitle)
                            .tag(role.rawValue)
                    }
                }
            } else {
                LabeledContent("Type", value: store.roleOptions.first?.imageInfoTitle ?? "Other")
            }

            if store.isIcon {
                Toggle(
                    "Icon can stand alone",
                    isOn: $store.iconCanRepresentSubjectWithoutLabel
                )
                .accessibilityIdentifier("field.image-info.icon-without-label")
            }

            if store.renderingModeOptions.count > 1 {
                Picker("Render", selection: $store.renderingModeRawValue) {
                    ForEach(store.renderingModeOptions, id: \.rawValue) { mode in
                        Text(mode.imageInfoTitle)
                            .tag(mode.rawValue)
                    }
                }
            } else {
                LabeledContent("Render", value: store.renderingModeOptions.first?.imageInfoTitle ?? "Other")
            }

            if store.configuration.allowsAppearance {
                Picker("Appearance", selection: $store.appearanceRawValue) {
                    Text("Any")
                        .tag(nil as String?)
                    ForEach(store.appearanceOptions, id: \.rawValue) { appearance in
                        Text(appearance.imageInfoTitle)
                            .tag(appearance.rawValue as String?)
                    }
                }
            }
        }

        if store.canEditFocusPoint {
            Section("Focus") {
                ImageFocusPointEditor(
                    image: $store.image,
                    recordID: store.recordID,
                    previewData: store.previewData
                )
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
}

struct ImageFocusPointEditor: View {
    @Binding var image: OME.Image
    let recordID: Event.ID?
    let previewData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ImageFocusPointPreview(
                image: $image,
                recordID: recordID,
                previewData: previewData
            )
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                LabeledContent("Point", value: focusPointDescription)

                Spacer()

                Button {
                    image.focalPoint = nil
                } label: {
                    Label("Clear Focus", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .disabled(image.focalPoint == nil)
            }
        }
        .padding(.vertical, 4)
    }

    var focusPointDescription: String {
        guard let focalPoint = image.focalPoint else { return "Center" }
        return "\(Int((focalPoint.x * 100).rounded()))%, \(Int((focalPoint.y * 100).rounded()))%"
    }
}

struct ImageFocusPointPreview: View {
    @Binding var image: OME.Image
    let recordID: Event.ID?
    let previewData: Data?
    @State var intrinsicSize: CGSize?

    var body: some View {
        GeometryReader { geometry in
            let imageRect = fittedImageRect(in: geometry.size)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.secondary.opacity(0.12))

                ImageFocusPreviewImage(
                    image: image,
                    recordID: recordID,
                    previewData: previewData,
                    intrinsicSize: $intrinsicSize
                )
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)

                focusMarker(in: imageRect)
            }
            .portableContentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        focusLocationChanged(value.location, in: imageRect)
                    }
            )
            .allowsHitTesting(intrinsicSize != nil)
        }
    }

    func fittedImageRect(in size: CGSize) -> CGRect {
        guard let imageSize = intrinsicSize else {
            return CGRect(origin: .zero, size: size)
        }
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let fittedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGRect(
            x: (size.width - fittedSize.width) / 2,
            y: (size.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    func focusLocationChanged(_ location: CGPoint, in imageRect: CGRect) {
        guard imageRect.width > 0, imageRect.height > 0 else { return }
        image.focalPoint = OME.Image.FocalPoint(
            x: Double(((location.x - imageRect.minX) / imageRect.width).clamped(to: 0...1)),
            y: Double(((location.y - imageRect.minY) / imageRect.height).clamped(to: 0...1))
        )
    }

    @ViewBuilder
    func focusMarker(in imageRect: CGRect) -> some View {
        let focalPoint = image.focalPoint ?? OME.Image.FocalPoint(x: 0.5, y: 0.5)
        let position = CGPoint(
            x: imageRect.minX + CGFloat(focalPoint.x) * imageRect.width,
            y: imageRect.minY + CGFloat(focalPoint.y) * imageRect.height
        )

        ZStack {
            Circle()
                .stroke(.white, lineWidth: 3)
                .frame(width: 26, height: 26)
            Circle()
                .stroke(.black.opacity(0.72), lineWidth: 1)
                .frame(width: 26, height: 26)
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: 34)
            Rectangle()
                .fill(.white)
                .frame(width: 34, height: 2)
        }
        .shadow(color: .black.opacity(0.32), radius: 3, y: 1)
        .position(position)
    }
}

struct ImageFocusPreviewImage: View {
    let image: OME.Image
    let recordID: Event.ID?
    let previewData: Data?
    @Binding var intrinsicSize: CGSize?

    var body: some View {
        Group {
            #if !SKIP && canImport(UIKit)
            if let previewData,
               let image = UIImage(data: previewData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .onAppear {
                        intrinsicSize = image.size
                    }
            } else {
                storedImage
            }
            #elseif !SKIP && canImport(AppKit)
            if let previewData,
               let image = NSImage(data: previewData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .onAppear {
                        intrinsicSize = image.size
                    }
            } else {
                storedImage
            }
            #elseif os(Android)
            if let previewData,
               let image = UIImage(data: previewData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .onAppear {
                        intrinsicSize = image.size
                    }
            } else {
                storedImage
            }
            #else
            storedImage
            #endif
        }
    }

    var storedImage: some View {
        ImageAssetAsyncImage(
            image: image.displayImageAsset(recordID: recordID),
            contentMode: .fit,
            onIntrinsicSizeLoaded: { intrinsicSize in
                self.intrinsicSize = intrinsicSize
            }
        ) {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

private extension Array where Element: Equatable {
    func including(_ element: Element) -> Self {
        contains(element) ? self : [element] + self
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension OME.Image.Appearance {
    var imageInfoTitle: String {
        switch self {
        case .dark:
            return "Dark"
        case .light:
            return "Light"
        }
    }
}

private extension OME.Image.RenderingMode {
    var imageInfoTitle: String {
        switch self {
        case .original:
            return "Original"
        case .template:
            return "Template"
        }
    }
}

private extension OME.Image.Role {
    var imageInfoTitle: String {
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
