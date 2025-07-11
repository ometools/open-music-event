//
//  SwiftUIView.swift
//
//
//  Created by Woody on 2/17/22.
//

import  SwiftUI; import SkipFuse

struct ScheduleStageSelector: View {
    var stages: [Stage]

    @Binding var selectedStage: Stage.ID?

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack {
                ForEach(stages) { stage in
                    Spacer()
                    ScheduleHeaderButton(
                        stage: stage,
                        isSelected: selectedStage == stage.id,
                        onSelect: {
                            selectedStage = $0
                        }
                    )
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .shadow()
        }

    }
}

internal extension View {
    func shadow() -> some View {
        self.modifier(FestivlShadowViewModifier())
    }
}

struct FestivlShadowViewModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    func body(content: Content) -> some View {
        if colorScheme == .light {
            content.shadow(radius: 3, x: 0, y:2)
        } else {
            content.shadow(color: Color.black, radius: 3, x: 0, y: 2)
        }
    }
}


struct ScheduleHeaderButton: View {
    var stage: Stage
    var isSelected: Bool
    @State var press = false
    var onSelect: (Stage.ID) -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        StageIconView(stageID: stage.id)
            .foregroundStyle(isSelected ? .white : stage.color.swiftUIColor)
            .frame(idealWidth: 60, idealHeight: 60)
            .frame(maxWidth: 60, maxHeight: 60)
        #if os(iOS)
            .contentShape(Circle())
        #endif
            .background {
                if isSelected {
                    Circle()
                        .fill(stage.color.swiftUIColor)
                        .shadow()
                }
            }
            .scaleEffect(press ? 0.8 : 1)
            .sensoryFeedback(.success, trigger: isSelected)
            .pressAndReleaseAction(
                pressing: $press,
                animation: .easeInOut(duration: 0.05),
                onRelease: {
                    withAnimation {
                        onSelect(stage.id)
                    }
                }
            )
    }
}
//
//struct ScheduleHeaderView_Previews: PreviewProvider {
//
//    static var previews: some View {
//        PreviewWrapper()
//    }
//
//    struct PreviewWrapper: View {
//
//        @State var selectedStage = Stage.testValues[1].id
//        var body: some View {
//            ScheduleStageSelector(
//                stages: IdentifiedArray(uniqueElements: Stage.testValues),
//                selectedStage: $selectedStage
//            )
//            .previewLayout(.sizeThatFits)
//            .previewAllColorModes()
//        }
//    }
//}

struct PressAndReleaseModifier: ViewModifier {
    @Binding var pressing: Bool
    var animation: Animation? = nil
    var onRelease: () -> Void

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged{ state in
                        if let animation = animation {
                            withAnimation(animation) {
                                pressing = true
                            }
                        } else {
                            pressing = true
                        }
                    }
                    .onEnded{ _ in
                        pressing = false
                        onRelease()
                    }
            )
    }
}

extension View {
    func pressAndReleaseAction(pressing: Binding<Bool>, animation: Animation? = nil, onRelease: @escaping (() -> Void)) -> some View {
        modifier(PressAndReleaseModifier(pressing: pressing, animation: animation, onRelease: onRelease))
    }
}
