import ComposableArchitecture2
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventImages
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
        onSave: @escaping (State.ID, OMERecord.ImageAsset) throws -> Void = { _, _ in }
    ) {
        self.onSave = onSave
    }

    public struct State: Equatable, Identifiable, Sendable {
        public init(
            id: UUID = UUID(),
            asset: OMERecord.ImageAsset,
            configuration: Configuration = .allImageAssets,
            sourceLabel: String? = nil,
            cacheContext: LocalImageCacheContext? = nil,
            previewData: Data? = nil
        ) {
            self.id = id
            self.asset = asset
            self.configuration = configuration
            self.sourceLabel = sourceLabel
            self.cacheContext = cacheContext
            self.previewData = previewData
        }

        public var asset: OMERecord.ImageAsset
        public var cacheContext: LocalImageCacheContext?
        public var configuration: Configuration
        public var errorMessage: String?
        public var id: UUID
        public var isSaving = false
        public var previewData: Data?
        public var sourceLabel: String?

        var appearanceOptions: [OMERecord.ImageAsset.Appearance] {
            OMERecord.ImageAsset.Appearance.allCases
        }

        var canSave: Bool {
            !isSaving
        }

        var canEditFocusPoint: Bool {
            asset.renderKind == .fullImage
                && asset.dimensions?.size != nil
        }

        var materializationPolicyOptions: [OMERecord.ImageAsset.MaterializationPolicy] {
            configuration.materializationPolicyOptions(including: asset.materializationPolicy)
        }

        var renderKindOptions: [OMERecord.ImageAsset.RenderKind] {
            configuration.renderKindOptions(including: asset.renderKind)
        }

        var roleOptions: [OMERecord.ImageAsset.Role] {
            configuration.roleOptions(including: asset.role)
        }

        var sourceDescription: String? {
            sourceLabel
                ?? asset.url?.absoluteString
        }
    }

    public enum Action {
        case cancelButtonTapped
        case saveButtonTapped
    }

    let onSave: (State.ID, OMERecord.ImageAsset) throws -> Void

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .saveButtonTapped:
                guard state.canSave else { return }

                let asset = state.asset
                let id = state.id
                state.errorMessage = nil
                state.isSaving = true

                store.addTask {
                    do {
                        try onSave(id, asset)
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
            allowedRoles: [OMERecord.ImageAsset.Role] = OMERecord.ImageAsset.Role.allCases,
            allowedRenderKinds: [OMERecord.ImageAsset.RenderKind] = OMERecord.ImageAsset.RenderKind.allCases,
            allowsAppearance: Bool = true,
            allowsMaterializationPolicy: Bool = true,
            allowedMaterializationPolicies: [OMERecord.ImageAsset.MaterializationPolicy] = OMERecord.ImageAsset.MaterializationPolicy.allCases
        ) {
            self.allowedRoles = allowedRoles
            self.allowedRenderKinds = allowedRenderKinds
            self.allowsAppearance = allowsAppearance
            self.allowsMaterializationPolicy = allowsMaterializationPolicy
            self.allowedMaterializationPolicies = allowedMaterializationPolicies
        }

        public var allowedMaterializationPolicies: [OMERecord.ImageAsset.MaterializationPolicy]
        public var allowedRenderKinds: [OMERecord.ImageAsset.RenderKind]
        public var allowedRoles: [OMERecord.ImageAsset.Role]
        public var allowsAppearance: Bool
        public var allowsMaterializationPolicy: Bool

        public static var allImageAssets: Self {
            Self()
        }

        public static var calendarHero: Self {
            Self(
                allowedRoles: [.hero],
                allowedRenderKinds: [.fullImage],
                allowsAppearance: true,
                allowsMaterializationPolicy: false,
                allowedMaterializationPolicies: [.lazy]
            )
        }

        public static var calendarLogo: Self {
            Self(
                allowedRoles: [.logo],
                allowedRenderKinds: [.transparent],
                allowsAppearance: true,
                allowsMaterializationPolicy: false,
                allowedMaterializationPolicies: [.lazy]
            )
        }

        public static var posters: Self {
            Self(
                allowedRoles: [.poster],
                allowedRenderKinds: [.fullImage],
                allowsAppearance: true,
                allowsMaterializationPolicy: false,
                allowedMaterializationPolicies: [.lazy]
            )
        }

        public static var contributorLogo: Self {
            Self(
                allowedRoles: [.logo],
                allowedRenderKinds: [.transparent],
                allowsAppearance: true,
                allowsMaterializationPolicy: false,
                allowedMaterializationPolicies: [.lazy]
            )
        }

        public static var contributorPhoto: Self {
            Self(
                allowedRoles: [.photo],
                allowedRenderKinds: [.fullImage],
                allowsAppearance: true,
                allowsMaterializationPolicy: false,
                allowedMaterializationPolicies: [.lazy]
            )
        }

        public static var stageHero: Self {
            Self(
                allowedRoles: [.hero],
                allowedRenderKinds: [.fullImage],
                allowsAppearance: true,
                allowsMaterializationPolicy: false,
                allowedMaterializationPolicies: [.prefetchOnOpen]
            )
        }

        public static var stageLogo: Self {
            Self(
                allowedRoles: [.logo],
                allowedRenderKinds: [.transparent],
                allowsAppearance: true,
                allowsMaterializationPolicy: false,
                allowedMaterializationPolicies: [.prefetchOnOpen]
            )
        }

        public static var stagePoster: Self {
            Self(
                allowedRoles: [.poster],
                allowedRenderKinds: [.fullImage],
                allowsAppearance: true,
                allowsMaterializationPolicy: false,
                allowedMaterializationPolicies: [.lazy]
            )
        }

        func materializationPolicyOptions(
            including policy: OMERecord.ImageAsset.MaterializationPolicy
        ) -> [OMERecord.ImageAsset.MaterializationPolicy] {
            allowedMaterializationPolicies.including(policy)
        }

        func renderKindOptions(
            including renderKind: OMERecord.ImageAsset.RenderKind
        ) -> [OMERecord.ImageAsset.RenderKind] {
            allowedRenderKinds.including(renderKind)
        }

        func roleOptions(
            including role: OMERecord.ImageAsset.Role
        ) -> [OMERecord.ImageAsset.Role] {
            allowedRoles.including(role)
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
                    Label("Cancel", systemImage: "close")
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

            if store.roleOptions.count > 1 {
                Picker("Type", selection: $store.asset.role) {
                    ForEach(store.roleOptions, id: \.self) { role in
                        Text(role.imageInfoTitle)
                            .tag(role)
                    }
                }
            } else {
                LabeledContent("Type", value: store.asset.role.imageInfoTitle)
            }

            if store.renderKindOptions.count > 1 {
                Picker("Render", selection: $store.asset.renderKind) {
                    ForEach(store.renderKindOptions, id: \.self) { renderKind in
                        Text(renderKind.imageInfoTitle)
                            .tag(renderKind)
                    }
                }
            } else {
                LabeledContent("Render", value: store.asset.renderKind.imageInfoTitle)
            }

            if store.configuration.allowsAppearance {
                Picker("Appearance", selection: $store.asset.appearance) {
                    Text("Any")
                        .tag(nil as OMERecord.ImageAsset.Appearance?)
                    ForEach(store.appearanceOptions, id: \.self) { appearance in
                        Text(appearance.imageInfoTitle)
                            .tag(appearance as OMERecord.ImageAsset.Appearance?)
                    }
                }
            }

            if store.configuration.allowsMaterializationPolicy {
                if store.materializationPolicyOptions.count > 1 {
                    Picker("Import", selection: $store.asset.materializationPolicy) {
                        ForEach(store.materializationPolicyOptions, id: \.self) { policy in
                            Text(policy.imageInfoTitle)
                                .tag(policy)
                        }
                    }
                } else {
                    LabeledContent("Import", value: store.asset.materializationPolicy.imageInfoTitle)
                }
            }
        }

        if store.canEditFocusPoint {
            Section("Focus") {
                ImageFocusPointEditor(
                    asset: $store.asset,
                    cacheContext: store.cacheContext,
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
    @Binding var asset: OMERecord.ImageAsset
    let cacheContext: LocalImageCacheContext?
    let previewData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ImageFocusPointPreview(
                asset: $asset,
                cacheContext: cacheContext,
                previewData: previewData
            )
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                LabeledContent("Point", value: focusPointDescription)

                Spacer()

                Button {
                    asset.focalPoint = nil
                } label: {
                    Label("Clear Focus", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .disabled(asset.focalPoint == nil)
            }
        }
        .padding(.vertical, 4)
    }

    var focusPointDescription: String {
        guard let focalPoint = asset.focalPoint else { return "Center" }
        return "\(Int((focalPoint.x * 100).rounded()))%, \(Int((focalPoint.y * 100).rounded()))%"
    }
}

struct ImageFocusPointPreview: View {
    @Binding var asset: OMERecord.ImageAsset
    let cacheContext: LocalImageCacheContext?
    let previewData: Data?

    var body: some View {
        GeometryReader { geometry in
            let imageRect = fittedImageRect(in: geometry.size)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.secondary.opacity(0.12))

                ImageFocusPreviewImage(
                    asset: asset,
                    cacheContext: cacheContext,
                    previewData: previewData
                )
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)

                focusMarker(in: imageRect)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        focusLocationChanged(value.location, in: imageRect)
                    }
            )
        }
    }

    func fittedImageRect(in size: CGSize) -> CGRect {
        guard let imageSize = asset.dimensions?.size else {
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
        asset.focalPoint = OMERecord.ImageAsset.FocalPoint(
            x: Double(((location.x - imageRect.minX) / imageRect.width).clamped(to: 0...1)),
            y: Double(((location.y - imageRect.minY) / imageRect.height).clamped(to: 0...1))
        )
    }

    @ViewBuilder
    func focusMarker(in imageRect: CGRect) -> some View {
        let focalPoint = asset.focalPoint ?? OMERecord.ImageAsset.FocalPoint(x: 0.5, y: 0.5)
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
    let asset: OMERecord.ImageAsset
    let cacheContext: LocalImageCacheContext?
    let previewData: Data?

    var body: some View {
        Group {
            #if !SKIP && canImport(UIKit)
            if let previewData,
               let image = UIImage(data: previewData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                storedImage
            }
            #elseif !SKIP && canImport(AppKit)
            if let previewData,
               let image = NSImage(data: previewData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
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
            asset: asset,
            cacheContext: cacheContext,
            contentMode: .fit
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

private extension OMERecord.ImageAsset.Dimensions {
    var size: CGSize? {
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
}

private extension OMERecord.ImageAsset.Appearance {
    var imageInfoTitle: String {
        switch self {
        case .dark:
            return "Dark"
        case .light:
            return "Light"
        }
    }
}

private extension OMERecord.ImageAsset.MaterializationPolicy {
    var imageInfoTitle: String {
        switch self {
        case .lazy:
            return "Lazy"
        case .prefetchOnOpen:
            return "Prefetch"
        }
    }
}

private extension OMERecord.ImageAsset.RenderKind {
    var imageInfoTitle: String {
        switch self {
        case .fullImage:
            return "Full Image"
        case .transparent:
            return "Transparent"
        }
    }
}

private extension OMERecord.ImageAsset.Role {
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
