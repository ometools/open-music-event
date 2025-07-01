//
//  SwiftUIView.swift
//  
//
//  Created by Woody on 2/21/22.
//

// import SharingGRDB
import GRDB
import  SwiftUI
import SkipFuse

extension ScheduleView {

    struct AllStagesAtOnceView: View {
        let store: ScheduleFeature

//        var schedule: [TimelineWrapper<Performance>] {
//            // TODO: Replace @SharedReader(.event) with proper state management
//            // @SharedReader(.event) var event
//
//            let orderedStageIndexes: [Stage.ID : Int] = Stages.enumerated().reduce(into: [:]) {
//                $0[$1.element.id] = $1.offset
//            }
//
//            guard let stageSchedules = store.event.schedule[day: store.selectedDay]?.stageSchedules
//            else { return [] }
//
//            let performancesWithColumns: [(Int, [Performance])] = stageSchedules.compactMap { stageID, performances in
//                guard let column: Int = orderedStageIndexes[stageID]
//                else { return nil }
//
//                return (column, performances)
//            }
//
//            return performancesWithColumns.flatMap { column, performances in
//                return performances.map {
//                    TimelineWrapper(
//                        groupWidth: column..<column,
//                        item: $0
//                    )
//                }
//            }
//        }

        var body: some View {
            ScrollView {
//                SchedulePageView([]) { performance in
//                    ScheduleCardView(
//                        performance.item,
//                        isSelected: false,
//                        isFavorite: false
//                    )
////                    .onTapGesture { store.send(.didTapCard(performance.id)) }
//                    .tag(performance.id)
//                }
//                .frame(height: 1500)
            }
//            .zoomable()
        }
    }
}
