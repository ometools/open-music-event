import ComposableArchitecture2
import Foundation
import SQLiteData
import SwiftUI

@Feature
public struct ContactInfoViewer {
    public init() {}

    public struct State {
        @FetchOne(OMERecord.Event.defaultEvent) public var event: OMERecord.Event?

        public init() {}
    }

    public enum Action {}

    public var body: some Feature {
        Update { _, _ in }
    }
}

public struct ContactInfoViewerView: View {
    let store: StoreOf<ContactInfoViewer>

    public init(store: StoreOf<ContactInfoViewer>) {
        self.store = store
    }

    public var body: some View {
        if let contactNumbers = store.event?.contactNumbers?.displayContactNumbers, !contactNumbers.isEmpty {
            List {
                ForEach(Array(contactNumbers.enumerated()), id: \.offset) { _, contactNumber in
                    if let url = contactNumber.phoneURL {
                        Link(destination: url) {
                            ContactNumberRow(contactNumber: contactNumber)
                        }
                        .buttonStyle(.plain)
                    } else {
                        ContactNumberRow(contactNumber: contactNumber)
                    }
                }
            }
            .navigationTitle("Contact Info")
        } else {
            ViewerPlaceholderView(
                title: "Contact Info",
                systemImage: "phone",
                description: "No contact information has been added to this event yet."
            )
        }
    }
}

struct ContactNumberRow: View {
    let contactNumber: OMERecord.Event.ContactNumber

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(contactNumber.displayTitle)
                    .font(.headline)

                Text(contactNumber.phoneNumber.formattedPhoneNumber)
                    .foregroundStyle(.secondary)
                    #if !os(Android)
                    .textSelection(.enabled)
                    #endif

                if let description = contactNumber.displayDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Image(systemName: "phone.fill")
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 4)
    }
}

private extension Array where Element == OMERecord.Event.ContactNumber {
    var displayContactNumbers: Self {
        filter { !$0.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

private extension OMERecord.Event.ContactNumber {
    var displayTitle: String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Contact" : title
    }

    var displayDescription: String? {
        let description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return description?.isEmpty == false ? description : nil
    }

    var phoneURL: URL? {
        let phoneNumber = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasInternationalPrefix = phoneNumber.first == "+"
        let digits = phoneNumber.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(hasInternationalPrefix ? "+" : "")\(digits)")
    }
}

private extension String {
    var formattedPhoneNumber: String {
        let digits = filter(\.isNumber)
        guard digits.count == 10 else { return self }

        let areaCode = digits.prefix(3)
        let prefix = digits.dropFirst(3).prefix(3)
        let lineNumber = digits.suffix(4)
        return "(\(areaCode)) \(prefix)-\(lineNumber)"
    }
}
