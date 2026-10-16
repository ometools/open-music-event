import Foundation
import Observation
#if os(Android)
import SkipSharing
#else
import Sharing
#endif
import Testing

final class NonGenericReference: Observable {
    let registrar = ObservationRegistrar()
    var _isLoading = false

    var isLoading: Bool {
        get {
            registrar.access(self, keyPath: \._isLoading)
            return _isLoading
        }
        set {
            registrar.withMutation(of: self, keyPath: \._isLoading) {
                _isLoading = newValue
            }
        }
    }
}

final class GenericReference<Key>: Observable {
    let registrar = ObservationRegistrar()
    var _isLoading = false

    var isLoading: Bool {
        get {
            registrar.access(self, keyPath: \._isLoading)
            return _isLoading
        }
        set {
            registrar.withMutation(of: self, keyPath: \._isLoading) {
                _isLoading = newValue
            }
        }
    }
}

@Test
func nonGenericObservationMutationIsAControl() {
    let reference = NonGenericReference()

    reference.isLoading = true

    #expect(reference.isLoading)
}

@Test
func genericObservationMutationReproducesAndroidKeyPathCrash() {
    #if os(Android)
    guard ProcessInfo.processInfo.environment["RUN_GENERIC_KEYPATH_REPRO"] == "manual" else {
        return
    }
    #endif

    let reference = GenericReference<Int>()

    reference.isLoading = true

    #expect(reference.isLoading)
}

@Test
func sharingAppStorageConstructionReproducesAndroidKeyPathCrash() {
    #if os(Android)
    guard ProcessInfo.processInfo.environment["RUN_GENERIC_KEYPATH_REPRO"] == "sharing" else {
        return
    }
    #endif

    let selectedID = Shared<Int?>(.appStorage("generic-key-path-repro-selected-id"))

    #expect(selectedID.wrappedValue == nil)
}
