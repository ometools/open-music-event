#if os(iOS) || os(macOS)
import LiquidGlassSegmentedPicker
#endif
import OpenMusicEventDatabase
import OpenMusicEventImages
import SwiftUI

private enum ShowStageNameLabelsEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var showStageNameLabels: Bool {
        get { self[ShowStageNameLabelsEnvironmentKey.self] }
        set { self[ShowStageNameLabelsEnvironmentKey.self] = newValue }
    }
}

struct OMEScheduleStageSelector: View {
    let stages: [OMERecord.Stage]
    let unavailableStageIDs: Set<OMERecord.ID<OMERecord.Stage>>
    @Binding var selectedStageID: OMERecord.ID<OMERecord.Stage>?

    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    @Environment(\.showStageNameLabels) var showStageNameLabels

    var resolvedSelectedStageID: OMERecord.ID<OMERecord.Stage>? {
        if let selectedStageID,
           stages.contains(where: { $0.id.stageID == selectedStageID }) {
            return selectedStageID
        }
        return stages.first?.id.stageID
    }

    var body: some View {
        Group {
            if needsStageDisambiguation {
                #if os(iOS) || os(macOS)
                if #available(iOS 26, macOS 26, *) {
                    liquidGlassPicker
                } else {
                    standardPicker
                }
                #else
                standardPicker
                #endif
            }
        }
        .onAppear {
            selectedStageID = resolvedSelectedStageID
        }
        .onChange(of: resolvedSelectedStageID) { _, newValue in
            guard selectedStageID != newValue else { return }
            selectedStageID = newValue
        }
    }

    #if os(iOS) || os(macOS)
    @available(iOS 26, macOS 26, *)
    var liquidGlassPicker: some View {
        LiquidGlassSegmentedPicker(selection: $selectedStageID) {
            ForEach(stages) { stage in
                Label {
                    Text(stage.name)
                } icon: {
                    ScheduleStageIcon(stage: stage)
                }
                .pickerItemColor(stage.color.swiftUIColor)
                .opacity(unavailableStageIDs.contains(stage.id.stageID) ? 0.45 : 1)
                .tag(Optional(stage.id.stageID))
            }
        }
        .labelsVisibility(showStageNameLabels ? .visible : .hidden)
        .padding(.vertical, 8)
    }
    #endif

    var standardPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(stages) { stage in
                    Button {
                        selectedStageID = stage.id.stageID
                    } label: {
                        VStack(spacing: 4) {
                            ScheduleStageIcon(stage: stage)
                                .frame(width: 34, height: 34)
                                .padding(9)
                                .foregroundStyle(resolvedSelectedStageID == stage.id.stageID ? .white : stage.color.swiftUIColor)
                                .background {
                                    Circle()
                                        .fill(
                                            resolvedSelectedStageID == stage.id.stageID
                                            ? stage.color.swiftUIColor
                                            : Color.secondary.opacity(0.12)
                                        )
                                }

                            if showStageNameLabels {
                                Text(stage.name)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.78)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(
                                        resolvedSelectedStageID == stage.id.stageID
                                        ? stage.color.swiftUIColor
                                        : .secondary
                                    )
                            }
                        }
                        .frame(width: showStageNameLabels ? 112 : 76)
                        .opacity(unavailableStageIDs.contains(stage.id.stageID) ? 0.45 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(stage.name)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.secondary.opacity(0.06))
    }
}

struct ScheduleStageIcon: View {
    let stage: OMERecord.Stage

    var body: some View {
        ImageAssetAsyncImage(
            asset: stage.images?.imageAsset(role: .logo),
            cacheContext: .init(stageID: stage.id),
            contentMode: .fit
        ) {
            fallback
        }
    }

    @ViewBuilder
    var fallback: some View {
        if let systemIconName = stage.systemIconName {
            Image(systemName: systemIconName)
                .resizable()
                .scaledToFit()
        } else if let iconShortCode = stage.iconShortCode {
            Text(iconShortCode)
                .font(.system(size: 24, weight: .heavy))
                #if os(iOS)
                .minimumScaleFactor(0.2)
                #endif
        } else {
            Text(stage.initials)
                .font(.system(size: 24, weight: .heavy))
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
