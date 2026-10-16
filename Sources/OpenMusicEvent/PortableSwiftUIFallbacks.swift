#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

extension Binding {
    func portableAnimation() -> Binding<Value> {
        #if os(Android)
        self
        #else
        self.animation()
        #endif
    }
}
