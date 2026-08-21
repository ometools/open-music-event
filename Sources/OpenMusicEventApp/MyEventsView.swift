import ComposableArchitecture2
import Foundation
import OpenMusicEventComponents
import OpenMusicEventImages
import OpenMusicEventLexicon
import SQLiteData
import SwiftUI

struct MyEventsView: View {
    @Bindable var store: StoreOf<MyEvents>

    var body: some View {
        List {
            if let error = store.$events.loadError {
                Text("Unable to load installed events: \(error.localizedDescription)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            ForEach(store.events) { event in
                Button {
                    store.send(.eventButtonTapped(event.id))
                } label: {
                    EventRowView(
                        event: event,
                        notificationIndicatorCount:
                            store.notificationIndicatorCountsByEventID[event.id, default: 0]
                    )
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("My Events")
    }
}

struct EventRowView: View {
    let event: OMERecord.Event
    let notificationIndicatorCount: Int

    init(
        event: OMERecord.Event,
        notificationIndicatorCount: Int = 0
    ) {
        self.event = event
        self.notificationIndicatorCount = notificationIndicatorCount
    }

    nonisolated static func imageAssets(
        icon: OME.ImageAsset?,
        poster: OME.ImageAsset?
    ) -> [OME.ImageAsset] {
        [poster, icon].compactMap { $0 }
    }

    static func posterQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Poster> {
        OMERecord.Poster
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
    }

    var body: some View {
        HStack(spacing: 10) {
            EventIconImageView(event: event)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading) {
                Text(event.name)
                if let date = event.eventDateText(dateStyle: .long) {
                    Text(date)
                        .lineLimit(1)
                        .font(.caption2)
                }
            }
            Spacer()
            if notificationIndicatorCount > 0 {
                Text("\(notificationIndicatorCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    #if !os(Android)
                    .monospacedDigit()
                    #endif
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.tint, in: Capsule())
                    .accessibilityLabel(
                        Text("\(notificationIndicatorCount) unread notifications")
                    )
            }
        }
        .foregroundStyle(.primary)
    }

    struct EventIconImageView: View {
        let event: OMERecord.Event
        @FetchOne var poster: OMERecord.Poster?

        init(event: OMERecord.Event) {
            self.event = event
            _poster = FetchOne(EventRowView.posterQuery(eventID: event.id))
        }

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.secondary.opacity(0.12))
                EventImageSourceChain(sources: imageSources[...]) {
                    MappedSystemImage(systemName: "music.note")
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        private var imageSources: [DisplayImageAsset] {
            EventRowView.imageAssets(
                icon: event.images?.imageAsset(role: .icon),
                poster: poster?.image
            ).map { asset in
                DisplayImageAsset(
                    asset: asset,
                    cacheContext: asset.role == .poster
                        ? poster.map { .init(posterID: $0.id) }
                        : .init(eventID: event.id)
                )
            }
        }
    }
}

struct EventImageSourceChain<Placeholder: View>: View {
    let sources: ArraySlice<DisplayImageAsset>
    @ViewBuilder var placeholder: () -> Placeholder

    @ViewBuilder
    var body: some View {
        if let source = sources.first {
            ImageAssetAsyncImage(image: source, contentMode: .fit) { reason in
                switch reason {
                case .loading:
                    Color.clear
                case .failure, .unavailable:
                    if sources.dropFirst().isEmpty {
                        placeholder()
                    } else {
                        EventImageSourceChain(
                            sources: sources.dropFirst(),
                            placeholder: placeholder
                        )
                    }
                }
            }
        } else {
            placeholder()
        }
    }
}

private extension OMERecord.Event {
    func eventDateText(dateStyle: DateFormatter.Style) -> String? {
        switch (startDate, endDate) {
        case let (.some(startDate), .some(endDate)):
            let formatter = DateIntervalFormatter()
            formatter.timeZone = timeZone
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            return formatter.string(
                from: startDate.atStartOfDay(in: timeZone),
                to: endDate.atStartOfDay(in: timeZone)
            )
        case let (.some(startDate), .none):
            return startDate.formatted(dateStyle: dateStyle, in: timeZone)
        case let (.none, .some(endDate)):
            return endDate.formatted(dateStyle: dateStyle, in: timeZone)
        case (.none, .none):
            return nil
        }
    }
}

private extension LocalDate {
    func formatted(dateStyle: DateFormatter.Style, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = .none
        return formatter.string(from: atStartOfDay(in: timeZone))
    }
}
