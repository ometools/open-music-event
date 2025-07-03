//
//  SwiftUIView.swift
//  
//
//  Created by Woodrow Melling on 5/24/23.
//

import  SwiftUI; import SkipFuse


private struct ScheduleCardStyleKey: EnvironmentKey {
    static let defaultValue: ScheduleCardStyle = .opaque
}

extension EnvironmentValues {
    var scheduleCardStyle: ScheduleCardStyle {
        get { self[ScheduleCardStyleKey.self] }
        set { self[ScheduleCardStyleKey.self] = newValue }
    }
}

enum ScheduleCardStyle {
    case transparent
    case opaque
}

public struct ScheduleCardBackground<Content: View>: View {
    var isSelected: Bool
    var color: Color
    var content: Content

    public init(color: Color, isSelected: Bool = false, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.color = color
        self.content = content()
    }

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scheduleCardStyle) var cardColorStyle

    public var body: some View {
        switch cardColorStyle {
        case .transparent:
            TransparentScheduleCardBackground(color: color, isSelected: isSelected, content: content)
        case .opaque:
            OpaqueScheduleCardBackground(color: color, isSelected: isSelected, content: content)
        }
    }


}

struct TransparentScheduleCardBackground<Content: View>: View {
    var isSelected: Bool
    var color: Color
    var content: Content

    public init(color: Color, isSelected: Bool = false, content: Content) {
        self.isSelected = isSelected
        self.color = color
        self.content = content
    }

    @Environment(\.colorScheme) var colorScheme

    public var body: some View {
        HStack(alignment: .top) {
            Rectangle()
                .fill(color)
                .frame(width: 5)

            GeometryReader { _ in
                content
//                    .brightness(colorScheme == .light ? -0.2 : 0)
            }
        }
        .background {
            /*
             We have a few goals for this color:
                1. We want to derive a few different colors from a single color
                2. The text color needs to be readable on top of the background color
                3. The background color should be slightly transparent, allowing the hour lines on the schedule to be visible through the card
             */
            Rectangle()
                .fill(color.opacity(isSelected ? 1 : 0.3))
                .background { Color.systemBackground.opacity(0.8)}

        }
        .foregroundStyle(isSelected ? .white : color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // This is to give a little bit of space between cards that bump against each other,
        // It makes it easier to differentiate between the
        .padding(.bottom, 0.2)
    }
}


struct OpaqueScheduleCardBackground<Content: View>: View {
    var isSelected: Bool
    var color: Color
    var content: Content

    public init(color: Color, isSelected: Bool = false, content: Content) {
        self.isSelected = isSelected
        self.color = color
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(.white)
                .frame(height: 1)
                .opacity(0.25)

            HStack(alignment: .top) {
                Rectangle()
                    .fill(.white)
                    .frame(width: 5)
                    .opacity(0.25)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                //                        .glow(color: isSelected ? .white : .clear, radius: 1)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .clipped()
        .frame(maxWidth: .infinity)
        .background(color)
        .overlay {
            if isSelected {
                Rectangle()
                    .stroke(.white, lineWidth: 1)
                //                        .glow(color: .white, radius: 2)
            }
        }
    }
}

//
//struct ScheduleCardBackgroundView_Previews: PreviewProvider {
//    
//    struct Preview: View {
//        @State var isSelected: Bool = false
//        @State var height: CGFloat = 200
//        
//        
//        var body: some View {
//            ScheduleCardBackground(color: .red, isSelected: isSelected) {
//                ViewThatFits {
//                    
//                    VStack(alignment: .leading) {
//                        
//                        Text(Date.now.formatted(.dateTime.hour(.conversationalDefaultDigits(amPM: .abbreviated)).minute()))
//                        
//                        
//                        Text("Astrid")
//                            .fontWeight(.heavy)
//                        
//                        
//                    }
//                    .padding(.vertical, 4)
//                    
//                    Text("Astrid")
//                        .fontWeight(.heavy)
//                        .padding(.vertical, 4)
//                    
//                    
//                    EmptyView()
//                }
//                
//            }
//            .frame(width: 200, height: height)
//            .overlay(alignment: .bottom) {
//                Rectangle()
//                    .fill(.clear)
//                    .contentShape(Rectangle())
//                    .frame(height: 5)
//                    .gesture(DragGesture()
//                        .onChanged({ height in
//                            self.height = self.height + height.translation.height
//                        }))
//            }
//            .onTapGesture {
//                isSelected.toggle()
//            }
//        }
//    }
//    
//    static var previews: some View {
//        Preview()
//    }
//}

//#Preview {
//
//    struct Preview: View {
//        var body: some View {
//            VStack {
//                ForEach([Color.red, .orange, .yellow, .green, .blue, .purple], id: \.self) {
//                    ScheduleCardBackground(
//                        color: $0,
//                        isSelected: false) {
//                            Text("This is the content")
//                        }
//                }
//
//            }
//        }
//    }
//
//    return HStack {
//        Preview()
//            .padding()
//            .background()
//            .environment(\.colorScheme, .light)
//
//        Preview()
//            .padding()
//            .background()
//            .environment(\.colorScheme, .dark)
//    }
//
//}

//struct ScheduleCardBackgroundView_Previews: PreviewProvider {
//    static var previews: some View {
//        ScheduleCardBackground(color: .red) {
//            VStack(alignment: .leading) {
//                Text("Blah")
//            }
//        }
//        .frame(width: 200, height: 100)
//    }
//}

//public struct ScheduleCardBackground<Content: View>: View {
//    var isSelected: Bool
//    var color: Color
//    var content: () -> Content
//
//    public init(color: Color, isSelected: Bool = false, @ViewBuilder content: @escaping () -> Content) {
//        self.isSelected = isSelected
//        self.color = color
//        self.content = content
//    }
//    
//    public var body: some View {
//        VStack(alignment: .leading, spacing: 0) {
//            Rectangle()
//                .fill(.white)
//                .frame(height: 1)
//                .opacity(0.25)
//
//            HStack(alignment: .top) {
//                Rectangle()
//                    .fill(.white)
//                    .frame(width: 5)
//                    .opacity(0.25)
//                
//                content()
//                    .frame(maxWidth: .infinity, maxHeight: .infinity)
//                    .glow(color: isSelected ? .white : .clear, radius: 1)
//            }
//            .foregroundColor(.white)
//            .frame(maxWidth: .infinity, maxHeight: .infinity)
//            
//        }
//        .clipped()
//        .frame(maxWidth: .infinity)
//        .overlay {
//            if isSelected {
//                Rectangle()
//                    .stroke(.white, lineWidth: 1)
////                    .glow(color: .white, radius: 2)
//            }
//        }
//        .background(color)
//    }
//}



extension View {
    func glow(color: Color = .red, radius: CGFloat = 20) -> some View {
        self
            .shadow(color: color, radius: radius / 3)
            .shadow(color: color, radius: radius / 3)
            .shadow(color: color, radius: radius / 3)
    }
}
