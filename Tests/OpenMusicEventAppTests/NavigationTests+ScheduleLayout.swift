import Bluesky
import ATProto
import Clocks
import ComposableArchitecture2
import ComposableNotifications
import CustomDump
import Dependencies
import DependenciesTestSupport
import DebugSnapshots
import Foundation
import IssueReporting
import Observation
import OpenMusicEventDatabase
import OpenMusicEventAuthentication
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import Sharing
import SQLiteData
import SourceEditing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Testing
import ATProto

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventEditors

extension NavigationTests {
    @Test
    func `empty schedule titles are friendly`() {
        expectNoDifference(
            ScheduleViewer.emptyScheduleTitle(
                scheduleDivision: .schedule,
                scheduleTitle: "Friday"
            ),
            "No Schedule on Friday"
        )
        expectNoDifference(
            ScheduleViewer.emptyScheduleTitle(
                scheduleDivision: .init(category: "workshop"),
                scheduleTitle: "Friday"
            ),
            "No Workshops on Friday"
        )
    }

    @Test
    func manyStagesTimelineGroupsKeepEmptyStageLanes() {
        #expect(ScheduleManyStagesAtOnceView.timelineGroups(stageCount: 4) == [0, 1, 2, 3])
    }

    @Test
    func manyStagesContentWidthShowsPartialLastStageOnCompactLayouts() {
        let width = ScheduleManyStagesAtOnceView.contentWidth(
            availableWidth: 393,
            stageCount: 3,
            minimumStageLaneWidth: 132,
            hourLabelsWidth: 43
        )

        #expect(width == 463)
    }

    @Test
    func manyStagesContentWidthDoesNotAddOverflowCueForSingleStage() {
        let width = ScheduleManyStagesAtOnceView.contentWidth(
            availableWidth: 393,
            stageCount: 1,
            minimumStageLaneWidth: 132,
            hourLabelsWidth: 43
        )

        #expect(width == 393)
    }

    @Test
    func manyStagesContentWidthDoesNotAddOverflowCueForTwoStages() {
        let width = ScheduleManyStagesAtOnceView.contentWidth(
            availableWidth: 393,
            stageCount: 2,
            minimumStageLaneWidth: 132,
            hourLabelsWidth: 43
        )

        #expect(width == 393)
    }

    @Test
    func manyStagesContentWidthKeepsMinimumLaneWidthWhenCompactTargetWouldShrinkLanes() {
        let width = ScheduleManyStagesAtOnceView.contentWidth(
            availableWidth: 320,
            stageCount: 4,
            minimumStageLaneWidth: 132,
            hourLabelsWidth: 43
        )

        #expect(width == 571)
    }

    @Test
    func manyStagesContentWidthDoesNotAddCompactStageRevealToWideLayouts() {
        let width = ScheduleManyStagesAtOnceView.contentWidth(
            availableWidth: 700,
            stageCount: 3,
            minimumStageLaneWidth: 132,
            hourLabelsWidth: 43
        )

        #expect(width == 700)
    }

    @Test
    func manyStagesTimelineWidthExcludesHourLabelRail() {
        let width = ScheduleManyStagesAtOnceView.timelineContentWidth(
            totalWidth: 463,
            hourLabelsWidth: 43
        )

        #expect(width == 420)
    }

    @Test
    func manyStagesResolvedTimelineWidthExcludesHourLabelRail() {
        let width = ScheduleManyStagesAtOnceView.resolvedTimelineWidth(
            totalWidth: 463,
            hourLabelsWidth: 43
        )

        expectNoDifference(width, 420)
    }

    @Test
    func manyStagesHorizontalLaneHeightUsesAvailableHeight() {
        let laneHeight = ScheduleManyStagesAtOnceView.horizontalStageLaneHeight(
            availableHeight: 700,
            stageCount: 4,
            hourLabelsHeight: 32,
            minimumStageLaneHeight: 84
        )

        #expect(laneHeight == 167)
    }

    @Test
    func manyStagesHorizontalLaneHeightKeepsMinimumHeight() {
        let laneHeight = ScheduleManyStagesAtOnceView.horizontalStageLaneHeight(
            availableHeight: 300,
            stageCount: 4,
            hourLabelsHeight: 32,
            minimumStageLaneHeight: 84
        )

        #expect(laneHeight == 84)
    }

    @Test
    func scheduleViewerDefaultsToSingleStageKind() throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            ScheduleViewer.State(eventID: eventID)
        }

        #expect(state.scheduleKind == .singleStageAtOnce)
    }

}
