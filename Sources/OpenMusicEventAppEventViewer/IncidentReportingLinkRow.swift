import Foundation
import OpenMusicEventLexicon
import SwiftUI

struct IncidentReportingLinkRow: View {
    let reportingLink: OMERecord.Event.ReportingLink

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Link(destination: reportingLink.url) {
                Text(reportingLink.name)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .portableAccessibilityHint(
                Text("Opens \(reportingLink.name) in a browser.")
            )

            if let description = reportingLink.displayDescription {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private extension OMERecord.Event.ReportingLink {
    var displayDescription: String? {
        guard let description else { return nil }

        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
