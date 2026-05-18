import ComposableArchitecture2
import Dependencies
import ErrorHandling
import IssueReporting
import Testing

@testable import OpenMusicEvent
@testable import OpenMusicEventAppEventViewer

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

    @Test
    func eventSettingsTestErrorButtonReportsGlobalError() async {
        let store = withDependencies {
            $0.exhaustivity = .off
        } operation: {
            TestStore(initialState: EventSettingsErrorHost.State()) {
                EventSettingsErrorHost()
            }
        }

        await withIssueReporters([]) {
            await store.send(to: \.eventSettings, .testErrorButtonTapped)?.value
        }

        let latestError = store.state.errorNotifications.state.latestError
        #expect(latestError?.kind.rawValue == "event.settings.test-error")
        #expect(latestError?.message.fallback == "Test error.")
        #expect(latestError?.operation.rawValue == "event.settings.test-error")
        #expect(latestError?.debugDescription == "Event settings test error")
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

@Feature
private struct EventSettingsErrorHost {
    struct State {
        var errorNotifications = Spawn(ErrorNotifications.State())
        @DebugSnapshotIgnored
        var eventSettings = Spawn(EventSettings.State(eventID: testEventID()))
    }

    enum Action {}

    var body: some Feature {
        Update { _, _ in }
            .spawn(\.errorNotifications) {
                ErrorNotifications()
            }
            .spawn(\.eventSettings) {
                EventSettings()
            }
            .onEvent(ErrorReported.self) { error, state in
                state.errorNotifications.state.report(error)
            }
    }
}

private func testEventID() -> OMERecord.Event.ID {
    OMERecord.Event.ID(
        organizerID: OMERecord.Organizer.ID("did:web:example.com")!,
        eventID: .init("event-1")
    )
}
