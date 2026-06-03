import ComposableArchitecture2
import Dependencies

public extension FeatureStore {
    func withDependencies<T>(operation: () -> T) -> T? {
        withErrorReporting {
            try Dependencies.withDependencies { $0 = try self.dependencies } operation: {
                operation()
            }
        }
    }
}
