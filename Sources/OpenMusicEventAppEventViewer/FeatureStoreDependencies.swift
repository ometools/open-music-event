import ComposableArchitecture2

public extension FeatureStore {
    func withDependencies<T>(operation: () -> T) -> T? {
        operation()
    }
}
