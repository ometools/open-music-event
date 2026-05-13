import ComposableArchitecture2
import Foundation
import SQLiteData
import SwiftUI

@Feature
public struct PostersViewer {
    public init() {}

    public struct State {
        public init(eventID: OMERecord.Event.ID? = nil) {
            @Dependency(\.defaultEventID) var defaultEventID
            let eventID = eventID ?? defaultEventID
            self.eventID = eventID
            _posters = FetchAll(
                PostersViewer.postersQuery(eventID: eventID)
            )
        }

        let eventID: OMERecord.Event.ID
        @FetchAll public var posters: [OMERecord.Poster]

        var sortedPosters: [OMERecord.Poster] {
            posters.sorted { lhs, rhs in
                let lhsTitle = lhs.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let rhsTitle = rhs.title?.trimmingCharacters(in: .whitespacesAndNewlines)

                switch (lhsTitle?.isEmpty == false ? lhsTitle : nil, rhsTitle?.isEmpty == false ? rhsTitle : nil) {
                case let (.some(lhsTitle), .some(rhsTitle)):
                    let comparison = lhsTitle.localizedStandardCompare(rhsTitle)
                    if comparison != .orderedSame {
                        return comparison == .orderedAscending
                    }

                case (.some, .none):
                    return true

                case (.none, .some):
                    return false

                case (.none, .none):
                    break
                }

                return lhs.id.posterID.rawValue.rawValue.localizedStandardCompare(
                    rhs.id.posterID.rawValue.rawValue
                ) == .orderedAscending
            }
        }
    }

    public enum Action {}

    static func postersQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Poster> {
        OMERecord.Poster
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
    }

    public var body: some Feature {
        Update { _, _ in }
    }
}

public struct PostersViewerView: View {
    let store: StoreOf<PostersViewer>

    public init(store: StoreOf<PostersViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.posters.isEmpty {
                ViewerPlaceholderView(
                    title: "Posters",
                    systemImage: "photo.on.rectangle",
                    description: "No posters have been added to this event yet."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(store.sortedPosters) { poster in
                            PosterCardView(poster: poster)
                        }
                    }
                    .padding()
                }
                .navigationTitle("Posters")
            }
        }
    }
}

struct PosterCardView: View {
    let poster: OMERecord.Poster

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ImageAssetAsyncImage(asset: poster.image, contentMode: .fit) {
                PosterPlaceholderView()
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let title = displayTitle {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayTitle: String? {
        let title = poster.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title : nil
    }
}

struct PosterPlaceholderView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.secondary.opacity(0.12))
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }
}
