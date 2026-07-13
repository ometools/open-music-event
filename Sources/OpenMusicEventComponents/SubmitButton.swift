#if canImport(SwiftUI)
import SwiftUI

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
                Label(kind.title, systemImage: kind.systemImage)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDisabled)
        }
    }
}

private extension SubmitButton.Kind {
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
