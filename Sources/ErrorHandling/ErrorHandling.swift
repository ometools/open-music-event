import ComposableArchitecture2
import Dependencies
import Foundation

public struct UserFacingText: Sendable {
    public var resource: LocalizedStringResource
    public var fallback: String

    public init(
        _ resource: LocalizedStringResource,
        fallback: String
    ) {
        self.resource = resource
        self.fallback = fallback
    }

    public var localizedString: String {
        String(localized: resource)
    }
}

public struct ErrorOperation: Hashable, RawRepresentable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public struct ErrorKind: Hashable, RawRepresentable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension ErrorKind {
    static let unhandled = Self("unhandled")
}

public struct ErrorHandlingContext: Sendable {
    public var fallbackMessage: UserFacingText
    public var operation: ErrorOperation

    public init(
        fallbackMessage: UserFacingText,
        operation: ErrorOperation
    ) {
        self.fallbackMessage = fallbackMessage
        self.operation = operation
    }
}

public struct ParsedError: Sendable {
    public var debugDescription: String?
    public var kind: ErrorKind
    public var message: UserFacingText

    public init(
        message: UserFacingText,
        kind: ErrorKind,
        debugDescription: String? = nil
    ) {
        self.debugDescription = debugDescription
        self.kind = kind
        self.message = message
    }
}

public struct HandledError: Identifiable, Sendable {
    public var date: Date
    public var debugDescription: String
    public var id: UUID
    public var kind: ErrorKind
    public var message: UserFacingText
    public var operation: ErrorOperation

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        operation: ErrorOperation,
        kind: ErrorKind,
        message: UserFacingText,
        debugDescription: String
    ) {
        self.date = date
        self.debugDescription = debugDescription
        self.id = id
        self.kind = kind
        self.message = message
        self.operation = operation
    }
}

public struct ErrorParser {
    public var parse: (_ error: any Error, _ context: ErrorHandlingContext) -> ParsedError?

    public init(
        _ parse: @escaping (_ error: any Error, _ context: ErrorHandlingContext) -> ParsedError?
    ) {
        self.parse = parse
    }
}

public extension ErrorParser {
    static var none: Self { Self { _, _ in nil } }

    func orElse(_ other: Self) -> Self {
        Self { error, context in
            self.parse(error, context) ?? other.parse(error, context)
        }
    }

    static func oneOf(_ parsers: Self...) -> Self {
        oneOf(parsers)
    }

    static func oneOf(_ parsers: [Self]) -> Self {
        Self { error, context in
            parsers.lazy.compactMap { $0.parse(error, context) }.first
        }
    }
}

@resultBuilder
public enum ErrorParserBuilder {
    public static func buildArray(_ parsers: [ErrorParser]) -> ErrorParser {
        .oneOf(parsers)
    }

    public static func buildBlock(_ parsers: ErrorParser...) -> ErrorParser {
        .oneOf(parsers)
    }

    public static func buildEither(first parser: ErrorParser) -> ErrorParser {
        parser
    }

    public static func buildEither(second parser: ErrorParser) -> ErrorParser {
        parser
    }

    public static func buildOptional(_ parser: ErrorParser?) -> ErrorParser {
        parser ?? .none
    }
}

public protocol UserFacingErrorConvertible: Error {
    func userFacingError(in context: ErrorHandlingContext) -> ParsedError
}

public struct ErrorReported: FeatureEventKey {
    public init() {}
    public typealias Value = HandledError
}

public func resolvedHandledError(
    from error: any Error,
    fallbackMessage: UserFacingText,
    operation: ErrorOperation,
    id: UUID = UUID(),
    date: Date = Date(),
    @ErrorParserBuilder parseError: () -> ErrorParser = { .none }
) -> HandledError? {
    if error is CancellationError {
        return nil
    }

    let context = ErrorHandlingContext(
        fallbackMessage: fallbackMessage,
        operation: operation
    )
    let parsed = parseError().parse(error, context)
        ?? (error as? any UserFacingErrorConvertible)?.userFacingError(in: context)
        ?? ParsedError(
            message: fallbackMessage,
            kind: .unhandled,
            debugDescription: String(describing: error)
        )

    return HandledError(
        id: id,
        date: date,
        operation: operation,
        kind: parsed.kind,
        message: parsed.message,
        debugDescription: parsed.debugDescription ?? String(describing: error)
    )
}

public extension FeatureStore {
    nonisolated(nonsending) func withErrorHandling<Output>(
        fallbackMessage: UserFacingText,
        operation errorOperation: ErrorOperation,
        _ operation: nonisolated(nonsending) () async throws -> Output,
        cleanup: @escaping (inout State) -> Void = { _ in },
        @ErrorParserBuilder parseError: () -> ErrorParser = { .none }
    ) async -> Output? {
        do {
            return try await operation()
        } catch {
            _ = try? modify(cleanup)

            guard let handledError = resolvedHandledError(
                from: error,
                fallbackMessage: fallbackMessage,
                operation: errorOperation,
                parseError: parseError
            ) else {
                return nil
            }

            reportIssue(error)
            _ = try? post(key: ErrorReported.self, value: handledError)
            return nil
        }
    }
}
