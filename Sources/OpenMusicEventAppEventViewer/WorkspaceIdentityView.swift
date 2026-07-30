import ATProto
import OpenMusicEventComponents
import SwiftUI

public enum WorkspaceActorIdentity: Equatable, Sendable {
    case loading
    case loaded(ActorIdentity)
    case unavailable
    case signedOut
}

public struct WorkspaceActorIdentityView: View {
    public let label: String
    public let identity: WorkspaceActorIdentity
    public let avatarSize: OMEViewerCGFloat

    public init(
        label: String,
        identity: WorkspaceActorIdentity,
        avatarSize: OMEViewerCGFloat = 36
    ) {
        self.label = label
        self.identity = identity
        self.avatarSize = avatarSize
    }

    public var body: some View {
        HStack(spacing: 10) {
            WorkspaceActorAvatar(
                identity: loadedIdentity,
                initials: avatarInitials,
                size: avatarSize
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .portableAccessibilityElement()
        .accessibilityLabel("\(label): \(title)")
    }

    private var loadedIdentity: ActorIdentity? {
        guard case let .loaded(identity) = identity else { return nil }
        return identity
    }

    private var title: String {
        switch identity {
        case .loading:
            "Loading account"
        case let .loaded(identity):
            identity.displayName?.trimmedWorkspaceIdentity
                ?? identity.handle.map { "@\($0.rawValue)" }
                ?? "Account"
        case .unavailable:
            "Identity unavailable"
        case .signedOut:
            "Not signed in"
        }
    }

    private var subtitle: String? {
        switch identity {
        case .loading:
            return "Checking account details"
        case let .loaded(identity):
            guard identity.displayName?.trimmedWorkspaceIdentity != nil,
                  let handle = identity.handle
            else { return nil }
            return "@\(handle.rawValue)"
        case .unavailable:
            return "Account details could not be loaded"
        case .signedOut:
            return "Sign in to submit or approve changes"
        }
    }

    private var avatarInitials: String {
        guard let loadedIdentity else {
            switch identity {
            case .signedOut:
                return "—"
            default:
                return "?"
            }
        }

        let source = loadedIdentity.displayName?.trimmedWorkspaceIdentity
            ?? loadedIdentity.handle?.rawValue
            ?? "?"
        return String(source.prefix(2)).uppercased()
    }
}

public struct WorkspaceActorHandleView: View {
    public let identity: WorkspaceActorIdentity
    public let avatarSize: OMEViewerCGFloat

    public init(
        identity: WorkspaceActorIdentity,
        avatarSize: OMEViewerCGFloat = 28
    ) {
        self.identity = identity
        self.avatarSize = avatarSize
    }

    public var body: some View {
        HStack(spacing: 8) {
            WorkspaceActorAvatar(
                identity: loadedIdentity,
                initials: avatarInitials,
                size: avatarSize
            )

            Text(handleTitle)
                .font(.subheadline)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .portableAccessibilityElement()
        .accessibilityLabel(Text(handleTitle))
    }

    private var loadedIdentity: ActorIdentity? {
        guard case let .loaded(identity) = identity else { return nil }
        return identity
    }

    private var handleTitle: String {
        switch identity {
        case .loading:
            "Loading account"
        case let .loaded(identity):
            identity.handle.map { "@\($0.rawValue)" }
                ?? identity.displayName?.trimmedWorkspaceIdentity
                ?? "Account"
        case .unavailable:
            "Account unavailable"
        case .signedOut:
            "Not signed in"
        }
    }

    private var avatarInitials: String {
        guard let loadedIdentity else { return "?" }
        let source = loadedIdentity.handle?.rawValue
            ?? loadedIdentity.displayName?.trimmedWorkspaceIdentity
            ?? "?"
        return String(source.prefix(2)).uppercased()
    }
}

struct WorkspaceActorAvatar: View {
    let identity: ActorIdentity?
    let initials: String
    let size: CGFloat

    var body: some View {
        CachedRemoteImage(
            url: identity?.avatar,
            targetSize: CGSize(width: size, height: size)
        ) { phase in
            switch phase {
            case let .success(image, _):
                image
                    .resizable()
                    .scaledToFill()
            case .empty, .failure, .unavailable:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.secondary.opacity(0.16))
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(.secondary.opacity(0.18))
            .overlay {
                Text(initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
    }
}

private extension String {
    var trimmedWorkspaceIdentity: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
