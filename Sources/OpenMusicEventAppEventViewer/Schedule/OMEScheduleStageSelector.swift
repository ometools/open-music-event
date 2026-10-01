#if os(iOS) || os(macOS)
import LiquidGlassSegmentedPicker
#endif
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

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
    let stages: [EventPlace]
    let unavailableStageIDs: Set<EventPlace.ID>
    @Binding var selectedStageID: EventPlace.ID?

    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    @Environment(\.showStageNameLabels) var showStageNameLabels

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
    }

    #if os(iOS) || os(macOS)
    @available(iOS 26, macOS 26, *)
    var liquidGlassPicker: some View {
        LiquidGlassSegmentedPicker(
            selection: $selectedStageID,
            itemAccessibilityIdentifier: { stageID in
                stageID.map {
                    "button.schedule-stage.\($0.description)"
                }
            },
            itemAccessibilityLabel: { stageID in
                stages.first { $0.id == stageID }?.name
            }
        ) {
            ForEach(stages) { stage in
                Label {
                    Text(stage.name)
                } icon: {
                    ScheduleStageIcon(stage: stage)
                }
                .pickerItemColor(stage.stageUIColor)
                .opacity(unavailableStageIDs.contains(stage.id) ? 0.45 : 1)
                .tag(Optional(stage.id))
            }
        }
        .labelsVisibility(showStageNameLabels ? .visible : .hidden)
        .padding(.vertical, 8)
    }
    #endif

    var standardPicker: some View {
        #if os(Android)
        AndroidScheduleStagePicker(
            stages: stages,
            selectedStageID: $selectedStageID,
            showStageNameLabels: showStageNameLabels
        )
        #else
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(stages) { stage in
                    Button {
                        selectedStageID = stage.id
                    } label: {
                        VStack(spacing: 4) {
                            ScheduleStageIcon(stage: stage)
                                .frame(width: 34, height: 34)
                                .padding(9)
                                .foregroundStyle(
                                    selectedStageID == stage.id
                                    ? .white
                                    : stage.stageUIColor
                                )
                                .background {
                                    Circle()
                                        .fill(
                                            selectedStageID == stage.id
                                            ? stage.stageUIColor
                                            : Color.secondary.opacity(0.12)
                                        )
                                }

                            if showStageNameLabels {
                                Text(stage.name)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.78)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: showStageNameLabels ? 112 : 76)
                        .opacity(unavailableStageIDs.contains(stage.id) ? 0.45 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "button.schedule-stage.\(stage.id.description)"
                    )
                    .accessibilityLabel(Text(stage.name))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        #endif
    }
}

struct AndroidScheduleStagePicker: View {
    let stages: [EventPlace]
    @Binding var selectedStageID: EventPlace.ID?
    let showStageNameLabels: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(stages) { stage in
                    AndroidScheduleStagePickerItem(
                        stage: stage,
                        isSelected: selectedStageID == stage.id,
                        showStageNameLabel: showStageNameLabels
                    ) {
                        selectedStageID = stage.id
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }
}

struct AndroidScheduleStagePickerItem: View {
    let stage: EventPlace
    let isSelected: Bool
    let showStageNameLabel: Bool
    let select: () -> Void

    var itemWidth: CGFloat {
        showStageNameLabel ? 124 : 82
    }

    var iconForegroundColor: Color {
        isSelected ? .white : stage.stageUIColor
    }

    var iconBackgroundColor: Color {
        isSelected ? stage.stageUIColor : Color.secondary.opacity(0.12)
    }

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                ScheduleStageIcon(stage: stage)
                    .frame(width: 54, height: 54)
                    .padding(8)
                    .foregroundStyle(iconForegroundColor)
                    .background {
                        Circle()
                            .fill(iconBackgroundColor)
                    }

                if showStageNameLabel {
                    Text(stage.name)
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                }
            }
            .frame(width: itemWidth)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            "button.schedule-stage.\(stage.id.description)"
        )
        .accessibilityLabel(Text(stage.name))
    }
}

struct ScheduleStageIcon: View {
    let stage: EventPlace

    var body: some View {
        ImageAssetAsyncImage(
            image: stage.stageLogoDisplayImage,
            contentMode: .fit
        ) {
            EventPlaceStageIconFallback(place: stage, size: 66)
        }
    }
}
