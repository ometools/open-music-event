import ErrorHandling

extension UserFacingText {
    static let sourceImportFailed = Self(
        "Unable to import source.",
        fallback: "Unable to import source."
    )
}

extension ErrorOperation {
    static let sourceImport = Self("source.import")
}

extension ErrorKind {
    static let sourceImportFailed = Self("source.import.failed")
}

enum SourceImportError {
    static var parser: ErrorParser { .none }
}
