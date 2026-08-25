import Foundation
import OpenMusicEventAppRouting
import OpenMusicEventComponents
#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

public struct EventEntryState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case loading
        case failed(String)
    }

    public init(
        id: UUID,
        route: AppRoute,
        title: String? = nil,
        logoURL: URL? = nil,
        phase: Phase = .loading
    ) {
        self.id = id
        self.route = route
        self.title = title
        self.logoURL = logoURL
        self.phase = phase
    }

    public let id: UUID
    public let route: AppRoute
    public var title: String?
    public var logoURL: URL?
    public var phase: Phase
}

public struct EventEntryView: View {
    public init(
        state: EventEntryState,
        retry: @escaping () -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.state = state
        self.retry = retry
        self.dismiss = dismiss
    }

    let state: EventEntryState
    let retry: () -> Void
    let dismiss: () -> Void

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                CachedRemoteImage(url: state.logoURL) { phase in
                    switch phase {
                    case let .success(image, _):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .empty:
                        ProgressView()
                    case .failure, .unavailable:
                        Image(systemName: "music.note")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(48)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 180, height: 180)
                .accessibilityLabel(Text(state.title ?? "Event"))

                if let title = state.title {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                }

                switch state.phase {
                case .loading:
                    ProgressView("Entering event…")
                case let .failed(message):
                    VStack(spacing: 12) {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again", action: retry)
                            .buttonStyle(.borderedProminent)
                        Button("Back to Events", action: dismiss)
                    }
                }
            }
            .padding(32)
        }
    }
}
