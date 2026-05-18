import ComposableArchitecture2
import Dependencies
import ErrorHandling
import IssueReporting
import Testing

@testable import OpenMusicEvent

@MainActor
struct SettingsFeatureTests {
    @Test
    func testErrorButtonReportsGlobalError() async {
        let store = withDependencies {
            $0.exhaustivity = .off
        } operation: {
            TestStore(initialState: SettingsErrorHost.State()) {
                SettingsErrorHost()
            }
        }

        await withIssueReporters([]) {
            await store.send(to: \.settings, .testErrorButtonTapped)?.value
        }

        let latestError = store.state.errorNotifications.state.latestError
        #expect(latestError?.kind == .settingsTestError)
        #expect(latestError?.message.fallback == "Test error.")
        #expect(latestError?.operation == .settingsTestError)
        #expect(latestError?.debugDescription == "Settings test error")
    }
}

@Feature
private struct SettingsErrorHost {
    struct State {
        var errorNotifications = Spawn(ErrorNotifications.State())
        @DebugSnapshotIgnored
        var settings = Spawn(Settings.State())
    }

    enum Action {}

    var body: some Feature {
        Update { _, _ in }
            .spawn(\.errorNotifications) {
                ErrorNotifications()
            }
            .spawn(\.settings) {
                Settings()
            }
            .onEvent(ErrorReported.self) { error, state in
                state.errorNotifications.state.report(error)
            }
    }
}
