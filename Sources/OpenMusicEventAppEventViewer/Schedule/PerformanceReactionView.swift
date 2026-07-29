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
    var showOther: @MainActor @Sendable (OMERecord.Performance.ID) -> Void = { _ in }

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
        let selected = Set(context.selectedEmojis(for: performanceID))

        Section("Reactions") {
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

            Button("Other…") {
                context.showOther(performanceID)
            }
            .accessibilityLabel("Choose another emoji reaction")
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
