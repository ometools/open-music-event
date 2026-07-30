import Foundation
import XCTest
import SkipAndroidBridge
import SkipBridge
import SwiftUITabFeaturesFuseFixtures

#if SKIP
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
#endif

/// Exercises EventViewer's visible-tab plus More navigation shape through the Fuse bridge.
final class MoreNavigationComposeTests: XCTestCase {
    // SKIP INSERT: @get:org.junit.Rule val composeRule = createComposeRule()

    var mainActorRelaxed = true

    override func setUp() {
        #if SKIP
        composeRule.runOnUiThread {
            try! loadPeerLibrary(
                packageName: "open-music-event",
                moduleName: "SwiftUITabFeaturesFuseFixtures"
            )
            let context = ProcessInfo.processInfo.androidContext
            try! AndroidBridgeBootstrap.initAndroidBridge(
                filesDir: context.getFilesDir().getAbsolutePath(),
                cacheDir: context.getCacheDir().getAbsolutePath()
            )
        }
        mainActorRelaxed = FuseUITestSupport.prepareJVMHostedTesting()
        #endif
    }

    func testMoreDestinationBackPopsAndClearsOverflowSelection() throws {
        #if !SKIP
        throw XCTSkip("Compose UI testing is Android-only")
        #else
        guard mainActorRelaxed else {
            throw XCTSkip("host Swift runtime cannot relax bridged main-actor checks")
        }

        composeRule.setContent {
            MoreNavigationFixture().Compose()
        }
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("schedule-root").assertIsDisplayed()
        composeRule.onNodeWithTag("more-navigation-state")
            .assertTextEquals("selection: schedule; overflow: none")

        // The attendee opens Stages from the More tab.
        composeRule.onNodeWithText("More").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithText("Stages").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("stages-destination").assertIsDisplayed()
        composeRule.onNodeWithTag("more-navigation-state")
            .assertTextEquals("selection: schedule; overflow: stages")

        // Android Back must pop the More path and clear its external selection.
        composeRule.onNodeWithContentDescription("Back").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("more-navigation-state")
            .assertTextEquals("selection: schedule; overflow: none")
        composeRule.onAllNodesWithTag("stages-destination").assertCountEquals(0)
        composeRule.onNodeWithText("Stages").assertIsDisplayed()
        #endif
    }
}
