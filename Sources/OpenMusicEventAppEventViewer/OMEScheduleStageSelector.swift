import LiquidGlassSegmentedPicker
import SwiftUI

struct OMEScheduleStageSelector: View {
    let onSelect: (OMERecord.ID<OMERecord.Stage>) -> Void
    let selectedStageID: OMERecord.ID<OMERecord.Stage>?
    let stages: [OMERecord.Stage]

    @State var liquidGlassSelection: OMERecord.ID<OMERecord.Stage>?

    init(
        stages: [OMERecord.Stage],
        selectedStageID: OMERecord.ID<OMERecord.Stage>?,
        onSelect: @escaping (OMERecord.ID<OMERecord.Stage>) -> Void
    ) {
        self.stages = stages
        self.selectedStageID = selectedStageID
        self.onSelect = onSelect
        self._liquidGlassSelection = State(initialValue: selectedStageID)
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
        LiquidGlassSegmentedPicker(selection: $liquidGlassSelection) {
            ForEach(stages) { stage in
                Label {
                    Text(stage.name)
                } icon: {
                    ScheduleStageIcon(stage: stage)
                        .padding(12)
                }
                .pickerItemColor(stage.color.swiftUIColor)
                .tag(Optional(stage.id.stageID))
            }
        }
        .labelsVisibility(.hidden)
        .padding(.vertical, 8)
        .onAppear {
            liquidGlassSelection = selectedStageID
        }
        .onChange(of: selectedStageID) { _, newValue in
            liquidGlassSelection = newValue
        }
        .onChange(of: liquidGlassSelection) { _, newValue in
            guard let newValue, newValue != selectedStageID else { return }
            onSelect(newValue)
        }
    }

    var standardPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(stages) { stage in
                    Button {
                        onSelect(stage.id.stageID)
                    } label: {
                        VStack(spacing: 4) {
                            ScheduleStageIcon(stage: stage)
                                .frame(width: 34, height: 34)
                                .padding(9)
                                .foregroundStyle(selectedStageID == stage.id.stageID ? .white : stage.color.swiftUIColor)
                                .background {
                                    Circle()
                                        .fill(
                                            selectedStageID == stage.id.stageID
                                            ? stage.color.swiftUIColor
                                            : Color.secondary.opacity(0.12)
                                        )
                                }

                            Text(stage.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(
                                    selectedStageID == stage.id.stageID
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
        if let iconImageURL = stage.iconImageURL {
            AsyncImage(url: iconImageURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                default:
                    fallback
                }
            }
        } else {
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
