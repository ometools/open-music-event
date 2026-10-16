import Foundation
import SwiftUI

struct CommsMarkdownText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        #if os(Android)
        Text(CommsMarkdown.fallbackText(text))
        #else
        Text(CommsMarkdown.renderedText(text))
        #endif
    }
}

enum CommsMarkdown {
    static func fallbackText(_ markdown: String) -> String {
        markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                var text = String(line)
                while text.first == "#" {
                    text.removeFirst()
                }
                text = text.trimmingCharacters(in: .whitespaces)

                if text.hasPrefix("- ") || text.hasPrefix("* ") {
                    text = "• " + String(text.dropFirst(2))
                }

                return text
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "*", with: "")
                    .replacingOccurrences(of: "`", with: "")
            }
            .joined(separator: "\n")
    }

    #if !os(Android)
    static func renderedText(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(markdown)
    }

    static func richEditorText(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(markdown)
    }

    @available(iOS 26.0, macOS 26.0, *)
    static func markdown(from richText: AttributedString) -> String {
        richText.runs.map { run in
            var text = String(richText[run.range].characters)
            let intents = run.inlinePresentationIntent ?? []

            if intents.contains(.code) {
                return "`\(text)`"
            }
            if intents.contains(.stronglyEmphasized) {
                text = "**\(text)**"
            }
            if intents.contains(.emphasized) {
                text = "*\(text)*"
            }
            if intents.contains(.strikethrough) {
                text = "~~\(text)~~"
            }
            return text
        }
        .joined()
    }
    #endif
}
