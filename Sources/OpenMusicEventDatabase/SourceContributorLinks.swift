import Foundation
import OpenMusicEventLexicon

/// Keeps ambiguous source strings as text instead of inventing account URLs.
struct SourceContributorLinks {
    var links: [OME.Link] = []
    var unresolved: [String] = []
    var normalized: [String] = []

    init(_ source: [ExternalPlatform.Link]) {
        for link in source {
            let raw = link.url.absoluteString
            let text = (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = text.components(separatedBy: " , ")
            if parts.count == 1, ["https", "http"].contains(link.url.scheme?.lowercased() ?? ""),
               link.url.host != nil, link.url.user == nil, link.url.password == nil {
                links.append(.init(url: link.url, platform: link.platform.map { .known($0) }))
                continue
            }
            for part in parts {
                let text = part.trimmingCharacters(in: .whitespacesAndNewlines)
                var candidate = text
                if candidate.hasPrefix("https//:") { candidate = "https://" + candidate.dropFirst(8) }
                else if candidate.hasPrefix("https//") { candidate = "https://" + candidate.dropFirst(7) }
                if URL(string: candidate)?.scheme == nil {
                    let host = candidate.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
                    let website = link.platform == .website || host.lowercased().hasPrefix("www.")
                    let explicitHost = candidate.contains("/")
                    if (website || explicitHost), host.contains("."),
                       host.range(of: "^[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil {
                        candidate = "https://" + candidate
                    }
                }
                guard let url = URL(string: candidate), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      let host = url.host, host.contains("."), url.user == nil, url.password == nil,
                      !candidate.contains(where: { $0.isWhitespace }) else {
                    unresolved.append("\(link.platform?.rawValue ?? "Link"): \(text)")
                    continue
                }
                // Leave already-valid escaped URLs byte-for-byte unchanged.
                let resolved = parts.count == 1 && raw == candidate ? link.url : url
                links.append(.init(url: resolved, platform: link.platform.map { .known($0) }))
                if resolved != link.url { normalized.append("\(raw) -> \(resolved.absoluteString)") }
            }
        }
    }
}
