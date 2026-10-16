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

    func testFlattenedSectionRowsUseStableIdentitiesAndContactNavigates() throws {
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

        // Android flattens sectioned tab features into one More list until
        // Compose can represent the shared section structure directly.
        composeRule.onNodeWithText("More").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithText("Event").assertDoesNotExist()
        composeRule.onNodeWithText("Resources").assertDoesNotExist()
        composeRule.onNodeWithText("Contact").assertIsDisplayed()
        composeRule.onNodeWithText("Location").assertIsDisplayed()
        composeRule.onNodeWithText("Site Map").assertIsDisplayed()
        composeRule.onNodeWithText("Contact").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("contact-destination").assertIsDisplayed()
        composeRule.onNodeWithTag("more-navigation-state")
            .assertTextEquals("selection: schedule; overflow: contact")

        // Android Back must pop the More path and clear its external selection.
        composeRule.onNodeWithContentDescription("Back").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("more-navigation-state")
            .assertTextEquals("selection: schedule; overflow: none")
        composeRule.onAllNodesWithTag("contact-destination").assertCountEquals(0)
        composeRule.onNodeWithText("Contact").assertIsDisplayed()
        #endif
    }

    func testContactSectionsUseDisjointRowIdentities() throws {
        #if !SKIP
        throw XCTSkip("Compose UI testing is Android-only")
        #else
        guard mainActorRelaxed else {
            throw XCTSkip("host Swift runtime cannot relax bridged main-actor checks")
        }

        composeRule.setContent {
            ContactInfoViewerFixture().Compose()
        }
        composeRule.waitForIdle()
        composeRule.onNodeWithText("REPORTING").assertIsDisplayed()
        composeRule.onNodeWithText("Report Incident").assertIsDisplayed()
        composeRule.onNodeWithText("CONTACT NUMBERS").assertIsDisplayed()
        composeRule.onNodeWithText("On Site Emergency Services").assertIsDisplayed()
        #endif
    }
}
