import ComposableArchitecture2
import Dependencies
import OpenMusicEventDatabase
import OpenMusicEventViewers
import SQLiteData
import SwiftUI

struct PerformanceReactionMenuContext: Sendable {
    var reactions: [PerformanceReaction] = []
    var usage: [PerformanceReactionEmojiUsage] = []
    var toggle: @MainActor @Sendable (OMERecord.Performance.ID, PerformanceReaction.Emoji) -> Void = { _, _ in }
    var showOther: (@MainActor @Sendable (OMERecord.Performance.ID) -> Void)?

    func selectedEmojis(
        for performanceID: OMERecord.Performance.ID
    ) -> [PerformanceReaction.Emoji] {
        reactions
            .filter { $0.performanceID == performanceID }
            .map(\.emoji)
    }

    func menuEmojis(
        for performanceID: OMERecord.Performance.ID
    ) -> [PerformanceReaction.Emoji] {
        PerformanceReaction.menuEmojis(
            selected: selectedEmojis(for: performanceID),
            usage: usage
        )
    }
}

enum PerformanceReactionMenuContextKey: EnvironmentKey {
    static let defaultValue = PerformanceReactionMenuContext()
}

extension EnvironmentValues {
    var performanceReactionMenuContext: PerformanceReactionMenuContext {
        get { self[PerformanceReactionMenuContextKey.self] }
        set { self[PerformanceReactionMenuContextKey.self] = newValue }
    }
}

struct PerformanceReactionMenuContent: View {
    let performanceID: OMERecord.Performance.ID
    let context: PerformanceReactionMenuContext

    var body: some View {
        Section("Reactions") {
            #if os(Android)
            let selected = Set(context.selectedEmojis(for: performanceID))

            ForEach(context.menuEmojis(for: performanceID), id: \.self) { emoji in
                Button {
                    context.toggle(performanceID, emoji)
                } label: {
                    if selected.contains(emoji) {
                        Label {
                            Text(verbatim: emoji.rawValue)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(verbatim: emoji.rawValue)
                    }
                }
                .accessibilityLabel(
                    selected.contains(emoji)
                        ? "Remove \(emoji.rawValue) reaction"
                        : "Add \(emoji.rawValue) reaction"
                )
            }

            if let showOther = context.showOther {
                Button("Other…") {
                    showOther(performanceID)
                }
                .accessibilityLabel("Choose another emoji reaction")
            }
            #else
            PerformanceReactionPicker(
                performanceID: performanceID,
                context: context
            )
            #endif
        }
    }
}

struct PerformanceReactionPicker: View {
    let performanceID: OMERecord.Performance.ID
    let context: PerformanceReactionMenuContext

    var body: some View {
        let selected = Set(context.selectedEmojis(for: performanceID))

        #if os(Android)
        HStack(spacing: 8) {
            ForEach(context.menuEmojis(for: performanceID), id: \.self) { emoji in
                reactionButton(emoji, isSelected: selected.contains(emoji))
            }

            if let showOther = context.showOther {
                Button {
                    showOther(performanceID)
                } label: {
                    Label("Other reaction", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Choose another emoji reaction")
            }
        }
        #else
        ControlGroup {
            ForEach(context.menuEmojis(for: performanceID), id: \.self) { emoji in
                reactionButton(emoji, isSelected: selected.contains(emoji))
            }

            if let showOther = context.showOther {
                Button {
                    showOther(performanceID)
                } label: {
                    Label("Other reaction", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Choose another emoji reaction")
            }
        }
        .controlGroupStyle(.palette)
        #endif
    }

    func reactionButton(
        _ emoji: PerformanceReaction.Emoji,
        isSelected: Bool
    ) -> some View {
        Button {
            context.toggle(performanceID, emoji)
        } label: {
            Text(verbatim: emoji.rawValue)
                .padding(4)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.2))
                    }
                }
        }
        .accessibilityLabel(
            isSelected
                ? "Remove \(emoji.rawValue) reaction"
                : "Add \(emoji.rawValue) reaction"
        )
    }
}

struct PerformanceReactionSummary: View {
    @Environment(\.performanceReactionMenuContext) var context
    let performanceID: OMERecord.Performance.ID
    var limit = 3

    var body: some View {
        let emojis = context.selectedEmojis(for: performanceID)

        if !emojis.isEmpty {
            HStack(spacing: 2) {
                ForEach(Array(emojis.prefix(limit)), id: \.self) { emoji in
                    Text(verbatim: emoji.rawValue)
                }

                if emojis.count > limit {
                    Text(verbatim: "+\(emojis.count - limit)")
                }
            }
            .font(.caption)
            .portableAccessibilityElementIgnoringChildren()
            .accessibilityLabel(
                Text(verbatim: "Reactions: \(emojis.map(\.rawValue).joined(separator: " "))")
            )
        }
    }
}

struct PerformanceReactionSummaryWhenFits: View {
    let performanceID: OMERecord.Performance.ID
    var axes: Axis.Set = .horizontal

    var body: some View {
        ViewThatFits(in: axes) {
            PerformanceReactionSummary(performanceID: performanceID)
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

@Feature
public struct PerformanceReactionEntry {
    public init() {}

    public struct State: Identifiable {
        public init(performanceID: OMERecord.Performance.ID) {
            self.performanceID = performanceID
        }

        public let performanceID: OMERecord.Performance.ID
        public var text = ""
        public var errorMessage: String?
        public var isSaving = false

        public var id: OMERecord.Performance.ID { performanceID }
        public var emoji: PerformanceReaction.Emoji? {
            PerformanceReaction.Emoji(rawValue: text)
        }
        public var canSave: Bool { emoji != nil && !isSaving }
    }

    public enum Action {
        case cancelButtonTapped
        case saveButtonTapped
    }

    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.getSelectedOAuthSessionID) var getSelectedOAuthSessionID
    @Dependency(\.uuid) var uuid

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .saveButtonTapped:
                guard let emoji = state.emoji, !state.isSaving else { return }
                let performanceID = state.performanceID
                let id = uuid()
                let date = now
                let userDID = getSelectedOAuthSessionID()?.rawValue
                state.isSaving = true
                state.errorMessage = nil

                store.addTask {
                    do {
                        try await database.write { db in
                            try PerformanceReaction.add(
                                performanceID: performanceID,
                                emoji: emoji,
                                id: id,
                                date: date,
                                userDID: userDID,
                                in: db
                            )
                        }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to save this reaction."
                            $0.isSaving = false
                        }
                    }
                }
            }
        }
    }
}

public struct PerformanceReactionEntryView: View {
    @Bindable var store: StoreOf<PerformanceReactionEntry>

    public init(store: StoreOf<PerformanceReactionEntry>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Emoji", text: $store.text)
                        .font(.largeTitle)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("Emoji reaction")
                } footer: {
                    Text("Enter one emoji.")
                }

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Other Reaction")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.send(.cancelButtonTapped)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.canSave)
                }
            }
        }
    }
}
