import SwiftUI

struct ImageAssetAsyncImage<Placeholder: View>: View {
    let asset: OMERecord.ImageAsset?
    var contentMode: ContentMode?
    @ViewBuilder var placeholder: () -> Placeholder

    init(
        asset: OMERecord.ImageAsset?,
        contentMode: ContentMode? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.asset = asset
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        if let url = asset?.url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholder()
                case let .success(image):
                    image
                        .renderingMode(asset?.isTemplateLike == true ? .template : .original)
                        .resizable()
                        .aspectRatio(contentMode: resolvedContentMode)
                case .failure:
                    placeholder()
                @unknown default:
                    placeholder()
                }
            }
        } else {
            placeholder()
        }
    }

    private var resolvedContentMode: ContentMode {
        if let contentMode {
            return contentMode
        }
        return asset?.renderKind == .transparent ? .fit : .fill
    }
}
