import Foundation
import OpenMusicEventImages
import OpenMusicEventLexicon
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

struct ProposalStageRowView: View {
    let stage: OMERecord.Stage

    var body: some View {
        HStack(spacing: 12) {
            ProposalStageArtworkView(stage: stage, size: 60)

            VStack(alignment: .leading, spacing: 3) {
                Text(stage.name)
                    .lineLimit(1)

                if let category = stage.category?.displayName {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .foregroundStyle(.primary)
    }
}

struct ProposalStageArtworkView: View {
    let stage: OMERecord.Stage
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(stage.color.swiftUIColor.opacity(0.18))

            ImageAssetAsyncImage(
                asset: stage.images?.imageAsset(role: .logo),
                cacheContext: .init(stageID: stage.id),
                contentMode: .fit
            ) {
                ProposalStageIconFallback(stage: stage, size: size)
            }
            .foregroundStyle(stage.color.swiftUIColor)
            .padding(10)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct ProposalStageIconFallback: View {
    let stage: OMERecord.Stage
    let size: CGFloat

    var body: some View {
        if let systemIconName = stage.systemIconName {
            Image(systemName: systemIconName)
                .font(.system(size: size * 0.42, weight: .semibold))
        } else if let iconShortCode = stage.iconShortCode {
            Text(iconShortCode)
                .font(.system(size: size * 0.36, weight: .heavy))
                .lineLimit(1)
                #if os(iOS)
                .minimumScaleFactor(0.2)
                #endif
        } else {
            Text(stage.initials)
                .font(.system(size: size * 0.36, weight: .heavy))
                .lineLimit(1)
                #if os(iOS)
                .minimumScaleFactor(0.2)
                #endif
        }
    }
}

private extension OMERecord.Stage {
    var initials: String {
        let initials = name
            .split(separator: " ")
            .filter { !$0.localizedCaseInsensitiveContains("the") }
            .compactMap(\.first)
            .prefix(2)
            .map(String.init)
            .joined()
        return initials.isEmpty ? "?" : initials
    }
}

private extension OMERecord.Stage.Category {
    var displayName: String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
            .split { $0 == "-" || $0 == "_" || $0 == " " }
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
