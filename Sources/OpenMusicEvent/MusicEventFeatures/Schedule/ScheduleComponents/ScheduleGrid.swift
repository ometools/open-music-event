//
//  File.swift
//  
//
//  Created by Woodrow Melling on 5/22/23.
//

import SwiftUI
import SkipFuse

public struct ScheduleGrid<Content: View>: View {
    public init(@ViewBuilder content: () -> Content = { EmptyView() }) {
        self.content = content()
    }

    var content: Content

    @State var width: CGFloat = 0
    
    public var body: some View {
        ZStack {
        
            HStack {
                ScheduleHourLabelsView()
                    .zIndex(0)
                    .offset(y: -7)


                ZStack {
                    ScheduleHourLines()
                        .zIndex(0)
                    
                    content
                        .zIndex(10)
                    #if os(iOS)
                        .coordinateSpace(name: "Timeline")
                    #endif
                }
                
            }
//            .onPreferenceChange(HourLabelsWidthPreferenceKey.self) { width = $0 }
            
            
            TimeIndicatorView()
        }
        .ignoresSafeArea(edges: .trailing)

    }
}



//
//#Preview {
//    ScrollView {
//
//        ScheduleGrid()
//    }
//}
