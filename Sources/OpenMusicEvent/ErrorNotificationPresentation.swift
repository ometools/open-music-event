import Dependencies
import ErrorHandling
import Foundation

struct ErrorNotificationPresentationClient: Sendable {
    var hideCurrent: @Sendable () async -> Void
    var selections: @Sendable () async -> AsyncStream<HandledError>
    var show: @Sendable (_ error: HandledError) async -> Void
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
            show: { error in
                await MainActor.run {
                    let message = error.message.localizedString
                    let drop = Drop(
                        title: "OpenMusicEvent",
                        subtitle: message.isEmpty ? error.message.fallback : message,
                        icon: UIImage(systemName: "music.note"),
                        action: .init {
                            Task { @MainActor in
                                ErrorNotificationSelectionCenter.shared.select(error)
                                Drops.hideCurrent()
                            }
                        },
                        position: .top,
                        duration: 5.0,
                        accessibility: .init(message: "Alert: OpenMusicEvent, \(error.message.fallback)")
                    )

                    Drops.show(drop)
                }
            }
        )
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
