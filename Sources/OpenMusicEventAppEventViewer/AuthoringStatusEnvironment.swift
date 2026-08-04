import ComposableAuthoring
import OpenMusicEventSourceEditing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

private struct OpenMusicEventAuthoringPhaseKey: EnvironmentKey {
    static let defaultValue: AuthoringPhase<AuthoringEligibility, AuthoringGrant>? = nil
}

public extension EnvironmentValues {
    var openMusicEventAuthoringPhase: AuthoringPhase<AuthoringEligibility, AuthoringGrant>? {
        get { self[OpenMusicEventAuthoringPhaseKey.self] }
        set { self[OpenMusicEventAuthoringPhaseKey.self] = newValue }
    }
}

public extension View {
    func openMusicEventAuthoringPhase(
        _ phase: AuthoringPhase<AuthoringEligibility, AuthoringGrant>
    ) -> some View {
        environment(\.openMusicEventAuthoringPhase, phase)
    }
}
