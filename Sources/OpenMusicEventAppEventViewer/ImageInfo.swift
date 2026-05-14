import ComposableArchitecture2
import Foundation
import OpenMusicEventDatabase
import SwiftUI

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
            sourceLabel: String? = nil
        ) {
            self.id = id
            self.asset = asset
            self.configuration = configuration
            self.sourceLabel = sourceLabel
        }

        public var asset: OMERecord.ImageAsset
        public var configuration: Configuration
        public var errorMessage: String?
        public var id: UUID
        public var isSaving = false
        public var sourceLabel: String?

        var appearanceOptions: [OMERecord.ImageAsset.Appearance] {
            OMERecord.ImageAsset.Appearance.allCases
        }

        var canSave: Bool {
            !isSaving
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

        public static var posters: Self {
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
            if let sourceDescription = store.sourceDescription {
                Section("Source") {
                    LabeledContent("Image", value: sourceDescription)
                }
            }

            Section("Display") {
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
            }

            if store.configuration.allowsMaterializationPolicy {
                Section("Storage") {
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

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .disabled(store.isSaving)
        .navigationTitle("Image Info")
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
                    Button("Save") {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.canSave)
                }
            }
        }
    }
}

private extension Array where Element: Equatable {
    func including(_ element: Element) -> Self {
        contains(element) ? self : [element] + self
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
