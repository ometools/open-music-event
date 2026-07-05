import SwiftUI

private enum NeedsStageDisambiguationEnvironmentKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var needsStageDisambiguation: Bool {
        get { self[NeedsStageDisambiguationEnvironmentKey.self] }
        set { self[NeedsStageDisambiguationEnvironmentKey.self] = newValue }
    }
}
