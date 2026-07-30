#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

private enum NeedsStageDisambiguationEnvironmentKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var needsStageDisambiguation: Bool {
        get { self[NeedsStageDisambiguationEnvironmentKey.self] }
        set { self[NeedsStageDisambiguationEnvironmentKey.self] = newValue }
    }
}
