import Foundation
#if os(Android) || canImport(SwiftUI)
#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

// SKIP INSERT: import skip.ui.*

public struct TimeZonePicker: View {
    @Environment(\.dismiss) var dismiss
    @Binding private var selection: TimeZone
    @State var query = ""

    public init(selection: Binding<TimeZone>) {
        self._selection = selection
    }

    public var body: some View {
        List(displayedTimeZones, id: \.identifier) { timeZone in
            TimeZonePickerButtonRow(
                timeZone: timeZone,
                isCurrent: timeZone.identifier == currentTimeZone.identifier,
                isSelected: timeZone.identifier == selection.identifier
            ) {
                selection = timeZone
                dismiss()
            }
        }
        .navigationTitle("Time Zone")
        .searchable(text: $query, prompt: "Search city or identifier")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
            }
        }
    }

    private var displayedTimeZones: [TimeZone] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return pinnedTimeZones + remainingTimeZones
        }

        let normalizedQuery = trimmedQuery.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return Self.allTimeZones.filter { timeZone in
            timeZone.searchText.localizedStandardContains(normalizedQuery)
        }
    }

    private var currentTimeZone: TimeZone {
        .current
    }

    private var selectedTimeZone: TimeZone? {
        TimeZone(identifier: selection.identifier)
    }

    private var pinnedCurrentTimeZone: TimeZone? {
        guard currentTimeZone.identifier != selectedTimeZone?.identifier else { return nil }
        return currentTimeZone
    }

    private var pinnedTimeZones: [TimeZone] {
        [selectedTimeZone, pinnedCurrentTimeZone].compactMap { $0 }
    }

    private var remainingTimeZones: [TimeZone] {
        let excludedIdentifiers = Set(pinnedTimeZones.map(\.identifier))
        return Self.allTimeZones.filter { !excludedIdentifiers.contains($0.identifier) }
    }

    private static let allTimeZones: [TimeZone] = TimeZone.knownTimeZoneIdentifiers
        .compactMap(TimeZone.init(identifier:))
        .sorted {
            if $0.pickerTitle == $1.pickerTitle {
                return $0.identifier < $1.identifier
            }
            return $0.pickerTitle < $1.pickerTitle
        }
}

struct TimeZonePickerButtonRow: View {
    let timeZone: TimeZone
    let isCurrent: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TimeZoneRow(
                timeZone: timeZone,
                isCurrent: isCurrent,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
    }
}

struct TimeZoneRow: View {
    let timeZone: TimeZone
    let isCurrent: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeZone.pickerTitle)
                    .foregroundStyle(.primary)

                Text(timeZone.pickerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            } else if isCurrent {
                Text("Current")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .timeZoneRowContentShape()
    }
}

private extension View {
    @ViewBuilder
    func timeZoneRowContentShape() -> some View {
        #if TARGET_OS_ANDROID || SKIP_BRIDGE
        self
        #else
        self.contentShape(Rectangle())
        #endif
    }
}
#endif

public extension TimeZone {
    var pickerTitle: String {
        identifier
            .split(separator: "/")
            .last
            .map { String($0).replacingOccurrences(of: "_", with: " ") }
        ?? identifier.replacingOccurrences(of: "_", with: " ")
    }

    var pickerSubtitle: String {
        var parts = [identifier]

        if let abbreviation = abbreviation(), abbreviation != identifier {
            parts.append(abbreviation)
        }

        parts.append(offsetDescription)
        return parts.joined(separator: " • ")
    }

    var searchText: String {
        [pickerTitle, identifier, pickerSubtitle]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private var offsetDescription: String {
        let totalSeconds = secondsFromGMT()
        let sign = totalSeconds >= 0 ? "+" : "-"
        let absoluteSeconds = Swift.abs(totalSeconds)
        let hours = absoluteSeconds / 3600
        let minutes = (absoluteSeconds % 3600) / 60
        return String(format: "UTC%@%02d:%02d", sign, hours, minutes)
    }
}
