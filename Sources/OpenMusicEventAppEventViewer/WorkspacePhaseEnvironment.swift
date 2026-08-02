import ComposableWorkspace
import SourceEditing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

private struct OpenMusicEventWorkspacePhaseKey: EnvironmentKey {
    static let defaultValue: WorkspacePhase<SourcePatch> = .inactive
}

public extension EnvironmentValues {
    var openMusicEventWorkspacePhase: WorkspacePhase<SourcePatch> {
        get { self[OpenMusicEventWorkspacePhaseKey.self] }
        set { self[OpenMusicEventWorkspacePhaseKey.self] = newValue }
    }
}

public extension View {
    func openMusicEventWorkspacePhase(
        _ phase: WorkspacePhase<SourcePatch>
    ) -> some View {
        environment(\.openMusicEventWorkspacePhase, phase)
    }
}

extension WorkspacePhase where ChangeSet == SourcePatch {
    var canRequestReconciliation: Bool {
        switch self {
        case .ready, .reconciliationFailed, .stale:
            true
        case .capturingSubmission, .inactive, .preparingSource, .publicationFailed,
             .publicationInterrupted, .publishing, .reconciling,
             .sourcePreparationFailed, .submissionCaptureFailed:
            false
        }
    }

    var isReconciling: Bool {
        guard case .reconciling = self else { return false }
        return true
    }

    var reconciliationFailure: WorkspaceFailure? {
        guard case let .reconciliationFailed(_, failure) = self else { return nil }
        return failure
    }
}
