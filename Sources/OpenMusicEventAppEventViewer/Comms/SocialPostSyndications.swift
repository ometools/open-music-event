import ATProto
import ComposableArchitecture2
import Foundation
import OpenMusicEventLexicon

struct SocialPostSyndicationEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    var source: Contributor.Source

    init(id: UUID = UUID(), source: Contributor.Source) {
        self.id = id
        self.source = source
    }
}

public struct SocialPostSyndicationDraft: Equatable, Sendable {
    var entryID: UUID?
    var reference: SocialPostStrongReference

    init(entryID: UUID? = nil, reference: SocialPostStrongReference = .init()) {
        self.entryID = entryID
        self.reference = reference
    }
}

@Feature
public struct SocialPostSyndications {
    public init() {}

    public struct State {
        public init(sources: [Contributor.Source]) {
            entries = sources.map { SocialPostSyndicationEntry(source: $0) }
        }

        var entries: [SocialPostSyndicationEntry]
        var draft: SocialPostSyndicationDraft?

        var sources: [Contributor.Source] { entries.map(\.source) }

        var canSaveDraft: Bool {
            guard let draft, let source = draft.reference.source else { return false }
            return !entries.contains { $0.id != draft.entryID && $0.source.uri == source.uri }
        }
    }

    public enum Action {
        case addButtonTapped
        case deleteButtonTapped(UUID)
        case draftCancelButtonTapped
        case draftChanged(SocialPostSyndicationDraft)
        case draftSaveButtonTapped
        case editButtonTapped(UUID)
        case moveButtonTapped(UUID, Int)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addButtonTapped:
                state.draft = SocialPostSyndicationDraft()

            case let .deleteButtonTapped(id):
                state.entries.removeAll { $0.id == id }
                if state.draft?.entryID == id { state.draft = nil }

            case .draftCancelButtonTapped:
                state.draft = nil

            case let .draftChanged(draft):
                guard state.draft != nil else { return }
                state.draft = draft

            case .draftSaveButtonTapped:
                guard state.canSaveDraft,
                      let draft = state.draft,
                      let source = draft.reference.source else { return }
                if let id = draft.entryID {
                    guard let index = state.entries.firstIndex(where: { $0.id == id }) else {
                        return
                    }
                    state.entries[index].source = source
                } else {
                    state.entries.append(SocialPostSyndicationEntry(source: source))
                }
                state.draft = nil

            case let .editButtonTapped(id):
                guard let entry = state.entries.first(where: { $0.id == id }) else { return }
                state.draft = SocialPostSyndicationDraft(
                    entryID: id,
                    reference: SocialPostStrongReference(entry.source)
                )

            case let .moveButtonTapped(id, offset):
                guard let index = state.entries.firstIndex(where: { $0.id == id }),
                      state.entries.indices.contains(index + offset) else { return }
                state.entries.swapAt(index, index + offset)
            }
        }
    }
}
