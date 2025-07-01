////
////  SelectingByComputViewModifier.swift
////  OpenFestival
////
////  Created by Woodrow Melling on 1/10/25.
////
//
//import  SwiftUI; import SkipFuse
//
//@available(iOS 18.0, *)
//extension View {
//    func scrollPosition<ID: Equatable>(_ id: Binding<ID?>, compute: @escaping (ID, CGSize) -> CGPoint?) -> some View {
//        self.modifier(ScrollPositionFromIDViewModifier(id: id, computeScrollDestination: compute))
//    }
//}
//
//@available(iOS 18.0, *)
//struct ScrollPositionFromIDViewModifier<ID: Equatable>: ViewModifier {
//
//    @Binding var id: ID?
//    var computeScrollDestination: (ID, CGSize) -> CGPoint?
//
//    @State var scrollPosition = ScrollPosition()
//    @State var contentSize: CGSize = .zero
//
//
//    func body(content: Content) -> some View {
//        content
//        #if os(iOS)
//            .onScrollGeometryChange(for: CGSize.self, of: \.contentSize) { _, newValue in
//                contentSize = newValue
//            }
//            .scrollPosition($scrollPosition)
//            .onChange(of: id) { _, newValue in
//                if let newValue, let destination = computeScrollDestination(newValue, contentSize) {
//                    print("Scrolling to: \(destination)")
//                    withAnimation {
//
//                        scrollPosition.scrollTo(point: destination)
//                    }
//                }
//            }
//            .onScrollPhaseChange { _, newPhase in
//                if newPhase == .interacting {
//                    id = nil
//                }
//            }
//        #endif
//    }
//}
