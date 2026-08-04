import ComposableAuthoring
import OpenMusicEventSourceEditing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

private struct OpenMusicEventAuthoringAdmissionKey: EnvironmentKey {
    static let defaultValue: ComposableAuthoring.AuthoringAdmission? = nil
}

private struct OpenMusicEventAuthoringPhaseKey: EnvironmentKey {
    static let defaultValue: AuthoringPhase<AuthoringGrant>? = nil
}

public extension EnvironmentValues {
    var openMusicEventAuthoringAdmission: ComposableAuthoring.AuthoringAdmission? {
        get { self[OpenMusicEventAuthoringAdmissionKey.self] }
        set { self[OpenMusicEventAuthoringAdmissionKey.self] = newValue }
    }

    var openMusicEventAuthoringPhase: AuthoringPhase<AuthoringGrant>? {
        get { self[OpenMusicEventAuthoringPhaseKey.self] }
        set { self[OpenMusicEventAuthoringPhaseKey.self] = newValue }
    }
}

public extension View {
    func openMusicEventAuthoringStatus(
        admission: ComposableAuthoring.AuthoringAdmission,
        phase: AuthoringPhase<AuthoringGrant>
    ) -> some View {
        environment(\.openMusicEventAuthoringAdmission, admission)
            .environment(\.openMusicEventAuthoringPhase, phase)
    }
}
