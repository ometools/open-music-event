import Testing

@testable import OpenMusicEventAppEventViewer

@MainActor
@Suite("Comms posting", .serialized)
struct CommsPostingTests {
    @Test
    func `Android Markdown fallback is readable`() {
        #expect(
            CommsMarkdown.fallbackText("## Arrival\n\n**Bring ID** and *water*.")
                == "Arrival\n\nBring ID and water."
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test
    func `rich text editor preserves normalized inline Markdown`() {
        let richText = CommsMarkdown.richEditorText("**Bold** and *italic*.")

        #expect(
            CommsMarkdown.markdown(from: richText)
                == "**Bold** and *italic*."
        )
    }
}
