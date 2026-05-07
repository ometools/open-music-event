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
        List {
            if query.isEmpty {
                Section {
                    if let selectedTimeZone {
                        timeZoneButton(selectedTimeZone, showsCurrentBadge: selectedTimeZone.identifier == currentTimeZone.identifier)
                    }

                    if let currentTimeZone = pinnedCurrentTimeZone {
                        timeZoneButton(currentTimeZone, showsCurrentBadge: true)
                    }
                }

            }

            Section(query.isEmpty ? "All Time Zones" : "Results") {
                ForEach(filteredTimeZones, id: \.identifier) { timeZone in
                    timeZoneButton(timeZone, showsCurrentBadge: timeZone.identifier == currentTimeZone.identifier)
                }
            }
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
        guard !trimmedQuery.isEmpty else {
            let excludedIdentifiers = Set(pinnedTimeZones.map(\.identifier))
            return Self.allTimeZones.filter { !excludedIdentifiers.contains($0.identifier) }
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

    @ViewBuilder
    private func timeZoneButton(_ timeZone: TimeZone, showsCurrentBadge: Bool) -> some View {
        Button {
            selection = timeZone
            dismiss()
        } label: {
            TimeZoneRow(
                timeZone: timeZone,
                isCurrent: showsCurrentBadge,
                isSelected: timeZone.identifier == selection.identifier
            )
        }
        .buttonStyle(.plain)
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
