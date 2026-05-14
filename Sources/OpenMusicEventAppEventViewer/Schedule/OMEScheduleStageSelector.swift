import LiquidGlassSegmentedPicker
import OpenMusicEventDatabase
import SwiftUI

struct OMEScheduleStageSelector: View {
    let stages: [OMERecord.Stage]
    @Binding var selectedStageID: OMERecord.ID<OMERecord.Stage>?

    var resolvedSelectedStageID: OMERecord.ID<OMERecord.Stage>? {
        if let selectedStageID,
           stages.contains(where: { $0.id.stageID == selectedStageID }) {
            return selectedStageID
        }
        return stages.first?.id.stageID
    }

    var body: some View {
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
                .tag(Optional(stage.id.stageID))
            }
        }
        .labelsVisibility(.hidden)
        .padding(.vertical, 8)
        .onAppear {
            selectedStageID = resolvedSelectedStageID
        }
        .onChange(of: resolvedSelectedStageID) { _, newValue in
            guard selectedStageID != newValue else { return }
            selectedStageID = newValue
        }
    }

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

                            Text(stage.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(
                                    resolvedSelectedStageID == stage.id.stageID
                                    ? stage.color.swiftUIColor
                                    : .secondary
                                )
                        }
                        .frame(width: 76)
                    }
                    .buttonStyle(.plain)
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
