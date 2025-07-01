////
////  File.swift
////
////
////  Created by Woodrow Melling on 5/24/23.
////
//
//import Foundation
//import  SwiftUI; import SkipFuse
//import OpenFestivalModels
//
//public extension View {
//    func toolbarDateSelector(
//        selectedDate: Binding<CalendarDate>,
//        addtionalContent: @escaping () -> some View = { EmptyView() }
//    ) -> some View {
//        self.modifier(ToolbarDateSelectorViewModifier(selectedDate: selectedDate, additionalContent: addtionalContent))
//    }
//}
//
//struct ToolbarDateSelectorViewModifier<Items, AdditionalContent: View>: ViewModifier {
//    @Binding var selectedDate: CalendarDate
//
//
//    var additionalContent: () -> AdditionalContent
//
//
//    func body(content: Content) -> some View {
//        #if os(iOS)
//        content
//            .navigationTitle(Text(FestivlFormatting.weekdayFormat(for: selectedDate)))
//            .toolbarTitleMenu {
//                ForEach(event.festivalDates, id: \.self) { date in
//                    Button {
//                        selectedDate = date
//                    } label: {
//                        Text(FestivlFormatting.weekdayFormat(for: date))
//                    }
//                }
//
//                Section {
//                    additionalContent()
//                }
//            }
//            .navigationBarTitleDisplayMode(.inline)
//
//        #elseif os(macOS)
//        content
//            .toolbar {
//                ToolbarItem(placement: .principal) {
//                    Menu(FestivlFormatting.weekdayFormat(for: selectedDate)) {
//                        ForEach(event.festivalDates, id: \.self) { date in
//                            Button {
//                                selectedDate = date
//                            } label: {
//                                Text(FestivlFormatting.weekdayFormat(for: date))
//                            }
//                        }
//
//                        Section {
//                            additionalContent()
//                        }
//                    }
//                }
//
//            }
//
//
//        #endif
//    }
//}
//
//#Preview("", body: {
//    NavigationStack {
//        Text("Hi Mom!")
//            .frame(square: 400)
//            .toolbarDateSelector(selectedDate: .constant(.today))
//    }
//})
