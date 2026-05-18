import ErrorHandling

extension UserFacingText {
    static let sourceImportFailed = Self(
        "Unable to import source.",
        fallback: "Unable to import source."
    )
    static let settingsTestError = Self(
        "Test error.",
        fallback: "Test error."
    )
}

extension ErrorOperation {
    static let sourceImport = Self("source.import")
    static let settingsTestError = Self("settings.test-error")
}

extension ErrorKind {
    static let settingsTestError = Self("settings.test-error")
    static let sourceImportFailed = Self("source.import.failed")
}

enum SourceImportError {
    static var parser: ErrorParser { .none }
}
