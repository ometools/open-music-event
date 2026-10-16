import Foundation
import OpenMusicEventLexicon
import SwiftUI

struct IncidentReportingLinkRow: View {
    let reportingLink: OME.Link

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Link(destination: reportingLink.url) {
                Text(reportingLink.displayTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .portableAccessibilityHint(
                Text("Opens \(reportingLink.displayTitle) in a browser.")
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
