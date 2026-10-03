import Testing
import OpenMusicEventLexicon

@testable import OpenMusicEventAppEventViewer

@MainActor
@Suite("Comms posting", .serialized)
struct CommsPostingTests {
    @Test
    func `editing a referenced record preserves its attached media`() throws {
        let embed = Social.Post.Embed([
            "$type": "app.bsky.embed.recordWithMedia",
            "record": .object([
                "$type": "app.bsky.embed.record",
                "record": .object([
                    "uri": "at://did:plc:artist/app.bsky.feed.post/first",
                    "cid": "bafyfirst",
                ]),
            ]),
            "media": .object(["$type": "app.bsky.embed.images"]),
        ])
        var editor = try #require(SocialPostRecordEmbed(embed: embed))
        editor.reference.cid = "bafysecond"

        let updated = try #require(editor.embed)
        #expect(updated.object["media"] == embed.object["media"])
        #expect(
            updated.object["record"]?.object?["record"]?.object?["cid"]
                == "bafysecond"
        )
        #expect(
            SocialPostEmbedContent(updated)
                == .record("at://did:plc:artist/app.bsky.feed.post/first")
        )
    }

    @Test
    func `Android Markdown fallback is readable`() {
        #expect(
            CommsMarkdown.fallbackText("## Arrival\n\n**Bring ID** and *water*.")
                == "Arrival\n\nBring ID and water."
        )
    }

    #if !os(Android)
    @available(iOS 26.0, macOS 26.0, *)
    @Test
    func `rich text editor preserves normalized inline Markdown`() {
        let richText = CommsMarkdown.richEditorText("**Bold** and *italic*.")

        #expect(
            CommsMarkdown.markdown(from: richText)
                == "**Bold** and *italic*."
        )
    }
    #endif
}
