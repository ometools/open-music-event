import Dependencies
import ErrorHandling
import Foundation

struct GlobalNotificationMessage: Sendable {
    enum State: Sendable {
        case error
        case info
        case success
        case warning
    }

    var selectedError: HandledError?
    var state: State
    var subtitle: String?
    var title: String
}

extension GlobalNotificationMessage {
    static func error(_ error: HandledError) -> Self {
        let message = error.message.localizedString
        return Self(
            selectedError: error,
            state: .error,
            subtitle: message.isEmpty ? error.message.fallback : message,
            title: "Error"
        )
    }
}

struct ErrorNotificationPresentationClient: Sendable {
    var hideCurrent: @Sendable () async -> Void
    var selections: @Sendable () async -> AsyncStream<HandledError>
    var show: @Sendable (_ message: GlobalNotificationMessage) async -> Void
}

extension ErrorNotificationPresentationClient {
    static let noop = Self(
        hideCurrent: {},
        selections: { AsyncStream { _ in } },
        show: { _ in }
    )
}

private enum ErrorNotificationPresentationClientKey: DependencyKey {
    static var liveValue: ErrorNotificationPresentationClient {
        #if os(iOS) && canImport(Drops)
        .drops
        #else
        .noop
        #endif
    }

    static var testValue: ErrorNotificationPresentationClient {
        .noop
    }
}

extension DependencyValues {
    var errorNotificationPresentation: ErrorNotificationPresentationClient {
        get { self[ErrorNotificationPresentationClientKey.self] }
        set { self[ErrorNotificationPresentationClientKey.self] = newValue }
    }
}

#if os(iOS) && canImport(Drops) && canImport(UIKit)
import Drops
import UIKit

private extension ErrorNotificationPresentationClient {
    static var drops: Self {
        Self(
            hideCurrent: {
                await MainActor.run {
                    Drops.hideCurrent()
                }
            },
            selections: {
                await ErrorNotificationSelectionCenter.shared.selections
            },
            show: { message in
                await MainActor.run {
                    let action = message.selectedError.map { error in
                        Drop.Action {
                            Task { @MainActor in
                                ErrorNotificationSelectionCenter.shared.select(error)
                                Drops.hideCurrent()
                            }
                        }
                    }
                    let drop = Drop(
                        title: message.title,
                        subtitle: message.subtitle,
                        icon: message.state.icon,
                        action: action,
                        position: .top,
                        duration: 5.0,
                        accessibility: .init(message: message.accessibilityMessage)
                    )

                    Drops.show(drop)
                }
            }
        )
    }
}

private extension GlobalNotificationMessage {
    var accessibilityMessage: String {
        [title, subtitle].compactMap { $0 }.joined(separator: ", ")
    }
}

private extension GlobalNotificationMessage.State {
    var icon: UIImage? {
        UIImage(systemName: systemImageName)?
            .withTintColor(tintColor, renderingMode: .alwaysOriginal)
    }

    var systemImageName: String {
        switch self {
        case .error:
            "xmark.circle.fill"
        case .info:
            "info.circle.fill"
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        }
    }

    var tintColor: UIColor {
        switch self {
        case .error:
            .systemRed
        case .info:
            .systemBlue
        case .success:
            .systemGreen
        case .warning:
            .systemYellow
        }
    }
}

@MainActor
private final class ErrorNotificationSelectionCenter {
    static let shared = ErrorNotificationSelectionCenter()

    private let stream = AsyncStream.makeStream(of: HandledError.self)

    var selections: AsyncStream<HandledError> {
        stream.stream
    }

    func select(_ error: HandledError) {
        stream.continuation.yield(error)
    }
}
#endif
