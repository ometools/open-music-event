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

            ForEach(store.sortedEvents) { event in
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
        .toolbar {
            Button("Import Events") { store.send(.importButtonTapped) }
                .accessibilityIdentifier("events.import")
        }
        .navigationDestination(item: $store.scope(\.sourceImport)) { importStore in
            ImportEventSourceView(store: importStore)
        }
    }
}

struct EventRowView: View {
    let event: Event
    let notificationIndicatorCount: Int

    init(
        event: Event,
        notificationIndicatorCount: Int = 0
    ) {
        self.event = event
        self.notificationIndicatorCount = notificationIndicatorCount
    }

    var body: some View {
        HStack(spacing: 10) {
            EventIconImageView(event: event)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading) {
                Text(event.name)
                if let date = eventDateText {
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

    private var eventDateText: String? {
        let start = event.start?.date(in: event.timeZone)
        let end = event.end?.date(in: event.timeZone)
        switch (start, end) {
        case let (.some(start), .some(end)):
            let formatter = DateIntervalFormatter()
            formatter.timeZone = event.timeZone
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            return formatter.string(from: start, to: end)
        case let (.some(date), .none), let (.none, .some(date)):
            let formatter = DateFormatter()
            formatter.timeZone = event.timeZone
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            return formatter.string(from: date)
        case (.none, .none):
            return nil
        }
    }

    struct EventIconImageView: View {
        let event: Event

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
            event.heroImageSources.map(\.image)
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
