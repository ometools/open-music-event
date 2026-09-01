#if os(Android) || canImport(SwiftUI)
#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

public struct SubmitButton: View {
    public enum Kind {
        case save
        case propose
    }

    let kind: Kind
    let isInProgress: Bool
    let isDisabled: Bool
    let action: () -> Void

    public init(
        _ kind: Kind = .save,
        isInProgress: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.kind = kind
        self.isInProgress = isInProgress
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        if isInProgress {
            ProgressView()
        } else {
            Button(action: action) {
                Label(kind.title, mappedSystemImage: kind.systemImage)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDisabled)
        }
    }
}

extension SubmitButton.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .save:
            "Save"
        case .propose:
            "Propose"
        }
    }

    var systemImage: String {
        switch self {
        case .save:
            "checkmark"
        case .propose:
            "paperplane"
        }
    }
}
#endif
