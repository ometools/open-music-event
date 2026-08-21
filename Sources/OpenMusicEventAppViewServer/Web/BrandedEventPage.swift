import Foundation
import Hummingbird
import OpenMusicEventLexicon

enum BrandedEventPage {
    static func response(
        event: OME.CalendarEvent,
        canonicalURL: URL
    ) -> Response {
        let hero = event.media.first { $0.role == OME.ImageAsset.Role.hero.rawValue }
            ?? event.media.first
        let organizerName = event.organizer.displayName ?? "OpenMusicEvent"
        let heroMarkup = hero.map {
            "<img class=\"hero-mark\" src=\"\($0.url.absoluteString.htmlEscaped)\" alt=\"\(($0.alt ?? event.name).htmlEscaped)\">"
        } ?? ""
        let descriptionMarkup = event.description.map {
            "<p class=\"lede\">\($0.htmlEscaped)</p>"
        } ?? ""
        let imageMetadata = hero.map {
            "<meta property=\"og:image\" content=\"\($0.url.absoluteString.htmlEscaped)\">"
        } ?? ""
        let canonicalURLString = canonicalURL.absoluteString.htmlEscaped
        let eventName = event.name.htmlEscaped
        let html = """
            <!doctype html>
            <html lang="en">
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <title>\(eventName)</title>
                <link rel="canonical" href="\(canonicalURLString)">
                <meta property="og:title" content="\(eventName)">
                <meta property="og:url" content="\(canonicalURLString)">
                \(imageMetadata)
                <link rel="stylesheet" href="/styles.css">
              </head>
              <body>
                <main>
                  <section class="hero" aria-label="\(eventName)">
                    \(heroMarkup)
                    <div class="hero-copy">
                      <p class="eyebrow">\(organizerName.htmlEscaped)</p>
                      <h1>\(eventName)</h1>
                      \(descriptionMarkup)
                    </div>
                  </section>
                </main>
              </body>
            </html>
            """
        return Response(
            status: .ok,
            headers: [.contentType: "text/html; charset=utf-8"],
            body: .init(byteBuffer: .init(data: Data(html.utf8)))
        )
    }
}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
