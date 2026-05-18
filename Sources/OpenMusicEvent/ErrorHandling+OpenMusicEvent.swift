import ErrorHandling
import Foundation
import OpenMusicEventSource

extension UserFacingText {
    static let sourceImportArchiveDestinationExists = Self(
        "Unable to prepare the downloaded source because a file already exists.",
        fallback: "Unable to prepare the downloaded source because a file already exists."
    )
    static let sourceImportArchiveEmpty = Self(
        "The Tangled source archive was empty.",
        fallback: "The Tangled source archive was empty."
    )
    static let sourceImportArchiveExtractionFailed = Self(
        "Unable to extract the Tangled source archive.",
        fallback: "Unable to extract the Tangled source archive."
    )
    static let sourceImportArchiveUnavailable = Self(
        "Tangled did not return a source archive.",
        fallback: "Tangled did not return a source archive."
    )
    static let sourceImportFailed = Self(
        "Unable to import source.",
        fallback: "Unable to import source."
    )
    static let sourceImportInvalidOrganizerID = Self(
        "The source organizer ID is not valid.",
        fallback: "The source organizer ID is not valid."
    )
    static let sourceImportInvalidRef = Self(
        "Enter a valid source ref.",
        fallback: "Enter a valid source ref."
    )
    static let sourceImportInvalidRepository = Self(
        "Enter a valid Tangled repository.",
        fallback: "Enter a valid Tangled repository."
    )
    static let sourceImportInvalidResolvedOwner = Self(
        "The repository owner did not resolve to a valid organizer.",
        fallback: "The repository owner did not resolve to a valid organizer."
    )
    static let sourceImportLocalSourceUnsupported = Self(
        "Enter a Tangled repository, not a local source path.",
        fallback: "Enter a Tangled repository, not a local source path."
    )
    static let sourceImportOutputUnsupported = Self(
        "Source import output can only be used with Tangled repositories.",
        fallback: "Source import output can only be used with Tangled repositories."
    )
    static let sourceImportOwnerResolutionFailed = Self(
        "Unable to resolve the repository owner.",
        fallback: "Unable to resolve the repository owner."
    )
    static let sourceImportStorageDestinationExists = Self(
        "Unable to store the imported source because a file already exists.",
        fallback: "Unable to store the imported source because a file already exists."
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
    static let sourceImportArchiveDestinationExists = Self("source.import.archive.destination-exists")
    static let sourceImportArchiveEmpty = Self("source.import.archive.empty")
    static let sourceImportArchiveExtractionFailed = Self("source.import.archive.extraction-failed")
    static let sourceImportArchiveUnavailable = Self("source.import.archive.unavailable")
    static let sourceImportFailed = Self("source.import.failed")
    static let sourceImportInvalidOrganizerID = Self("source.import.invalid-organizer-id")
    static let sourceImportInvalidRef = Self("source.import.invalid-ref")
    static let sourceImportInvalidRepository = Self("source.import.invalid-repository")
    static let sourceImportInvalidResolvedOwner = Self("source.import.invalid-resolved-owner")
    static let sourceImportLocalSourceUnsupported = Self("source.import.local-source")
    static let sourceImportOutputUnsupported = Self("source.import.output-unsupported")
    static let sourceImportOwnerResolutionFailed = Self("source.import.owner-resolution-failed")
    static let sourceImportStorageDestinationExists = Self("source.import.storage.destination-exists")
}

enum SourceImportError {
    static var parser: ErrorParser {
        .oneOf(
            sourceValidationParser,
            contains(
                "Tangled did not return an archive",
                message: .sourceImportArchiveUnavailable,
                kind: .sourceImportArchiveUnavailable
            ),
            contains(
                "Downloaded archive did not contain any files",
                message: .sourceImportArchiveEmpty,
                kind: .sourceImportArchiveEmpty
            ),
            contains(
                "Failed to extract Tangled source archive",
                anyOf: [
                    "File exists",
                    "already exists",
                    "NSCocoaErrorDomain Code=516",
                    "NSPOSIXErrorDomain Code=17",
                ],
                message: .sourceImportArchiveDestinationExists,
                kind: .sourceImportArchiveDestinationExists
            ),
            contains(
                "Failed to extract Tangled source archive",
                message: .sourceImportArchiveExtractionFailed,
                kind: .sourceImportArchiveExtractionFailed
            ),
            contains(
                "Output path already exists",
                message: .sourceImportArchiveDestinationExists,
                kind: .sourceImportArchiveDestinationExists
            ),
            contains(
                anyOf: [
                    "Repository reference cannot be empty",
                    "Source cannot be empty",
                    "Source must be an existing local path or Tangled repository reference",
                    "Local source path does not exist",
                    "SSH repository references are not supported",
                    "Unsupported repository URL scheme",
                    "Repository URL is missing a host",
                    "Repository reference must be shaped like owner/repo",
                    "Repository reference must include both owner and repository name",
                    "Repository owner is not a valid handle",
                    "Could not construct Tangled archive URL",
                    "Could not encode URL path component",
                ],
                message: .sourceImportInvalidRepository,
                kind: .sourceImportInvalidRepository
            ),
            contains(
                "Could not resolve repository owner",
                message: .sourceImportOwnerResolutionFailed,
                kind: .sourceImportOwnerResolutionFailed
            ),
            contains(
                "Ref cannot be empty",
                message: .sourceImportInvalidRef,
                kind: .sourceImportInvalidRef
            ),
            contains(
                anyOf: [
                    "File exists",
                    "already exists",
                    "NSCocoaErrorDomain Code=516",
                    "NSPOSIXErrorDomain Code=17",
                ],
                message: .sourceImportStorageDestinationExists,
                kind: .sourceImportStorageDestinationExists
            )
        )
    }

    private static var sourceValidationParser: ErrorParser {
        ErrorParser { error, _ in
            guard let validationError = error as? OpenMusicEventSourceValidationError else {
                return nil
            }

            switch validationError {
            case .invalidOrganizerID:
                return parsed(
                    error,
                    message: .sourceImportInvalidOrganizerID,
                    kind: .sourceImportInvalidOrganizerID
                )

            case .invalidResolvedOrganizerID:
                return parsed(
                    error,
                    message: .sourceImportInvalidResolvedOwner,
                    kind: .sourceImportInvalidResolvedOwner
                )

            case .missingOrganizerIDForLocalSource:
                return parsed(
                    error,
                    message: .sourceImportLocalSourceUnsupported,
                    kind: .sourceImportLocalSourceUnsupported
                )

            case .outputRequiresTangledSource:
                return parsed(
                    error,
                    message: .sourceImportOutputUnsupported,
                    kind: .sourceImportOutputUnsupported
                )
            }
        }
    }

    private static func contains(
        _ requiredNeedle: String,
        _ additionalNeedles: String...,
        message: UserFacingText,
        kind: ErrorKind
    ) -> ErrorParser {
        ErrorParser { error, _ in
            let text = text(for: error)
            guard text.matches(requiredNeedle),
                  additionalNeedles.allSatisfy({ text.matches($0) })
            else {
                return nil
            }
            return ParsedError(
                message: message,
                kind: kind,
                debugDescription: text.debugDescription
            )
        }
    }

    private static func contains(
        _ requiredNeedle: String,
        anyOf additionalNeedles: [String],
        message: UserFacingText,
        kind: ErrorKind
    ) -> ErrorParser {
        ErrorParser { error, _ in
            let text = text(for: error)
            guard text.matches(requiredNeedle),
                  additionalNeedles.contains(where: { text.matches($0) })
            else {
                return nil
            }
            return ParsedError(
                message: message,
                kind: kind,
                debugDescription: text.debugDescription
            )
        }
    }

    private static func contains(
        anyOf needles: [String],
        message: UserFacingText,
        kind: ErrorKind
    ) -> ErrorParser {
        ErrorParser { error, _ in
            let text = text(for: error)
            guard needles.contains(where: { text.matches($0) }) else {
                return nil
            }
            return ParsedError(
                message: message,
                kind: kind,
                debugDescription: text.debugDescription
            )
        }
    }

    private static func parsed(
        _ error: any Error,
        message: UserFacingText,
        kind: ErrorKind
    ) -> ParsedError {
        let text = text(for: error)
        return ParsedError(
            message: message,
            kind: kind,
            debugDescription: text.debugDescription
        )
    }

    private static func text(for error: any Error) -> ErrorText {
        let debugDescription: String
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            debugDescription = errorDescription
        } else {
            debugDescription = String(describing: error)
        }

        let localizedDescription = (error as NSError).localizedDescription
        let searchText = [debugDescription, localizedDescription]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return ErrorText(
            debugDescription: debugDescription,
            searchText: searchText
        )
    }
}

private struct ErrorText {
    var debugDescription: String
    var searchText: String

    func matches(_ needle: String) -> Bool {
        searchText.localizedCaseInsensitiveContains(needle)
    }
}
