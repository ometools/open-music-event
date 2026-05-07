import Foundation
import SwiftUI

public struct TimeZonePicker: View {
    @Environment(\.dismiss) var dismiss
    @Binding private var selection: TimeZone
    @State var query = ""

    public init(selection: Binding<TimeZone>) {
        self._selection = selection
    }

    public var body: some View {
        List(filteredTimeZones, id: \.identifier) { timeZone in
            Button {
                selection = timeZone
                dismiss()
            } label: {
                TimeZoneRow(
                    timeZone: timeZone,
                    isSelected: timeZone.identifier == selection.identifier
                )
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Time Zone")
        .searchable(text: $query, prompt: "Search city or identifier")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }

    private var filteredTimeZones: [TimeZone] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return Self.allTimeZones }

        let normalizedQuery = trimmedQuery.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return Self.allTimeZones.filter { timeZone in
            timeZone.searchText.localizedStandardContains(normalizedQuery)
        }
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

struct TimeZoneRow: View {
    let timeZone: TimeZone
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
            }
        }
        .contentShape(Rectangle())
    }
}

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
