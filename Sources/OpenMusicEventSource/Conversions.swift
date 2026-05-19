import FileTree
import Foundation
import FrontmatterParsing
import Yams

struct YamlConversion<Value: Codable>: Conversion {
    typealias Input = Data
    typealias Output = Value

    func apply(_ input: Data) throws -> Value {
        try YAMLDecoder().decode(Value.self, from: input)
    }

    func unapply(_ output: Value) throws -> Data {
        try Data(YAMLEncoder().encode(output).utf8)
    }
}

public struct ParticipantMarkdownConversion: Conversion {
    public typealias Input = FileContent<Data>
    public typealias Output = FileContent<ParticipantDTO>

    public init() {}

    public func apply(_ input: FileContent<Data>) throws -> FileContent<ParticipantDTO> {
        let markdown = try MarkdownWithFrontMatterConversion<ParticipantDTO>()
            .apply(String(decoding: input.data, as: UTF8.self))
        guard var participant = markdown.frontMatter else {
            throw MissingFrontMatterError(fileName: input.fileName)
        }

        if let body = markdown.body?.nonEmptyMarkdownBody {
            participant.bio = body
        }

        return try input.map { _ in participant }
    }

    public func unapply(_ output: FileContent<ParticipantDTO>) throws -> FileContent<Data> {
        try output.map { participant in
            try Self.markdownData(for: participant)
        }
    }

    public func unapply(
        _ output: FileContent<ParticipantDTO>,
        in context: FileTreeWriteContext
    ) -> Conversions.Result<FileContent<Data>> {
        do {
            let rootedContext = context.rooted(at: output)
            return .value(
                try output.map { participant in
                    try Self.markdownData(for: participant, context: rootedContext)
                }
            )
        } catch {
            return .invalid(
                diagnostics: .init(
                    diagnostics: [
                        Diagnostic(
                            severity: .error,
                            code: "open-music-event.participant-markdown.print.failed",
                            message: String(describing: error),
                            location: .init(path: output.path.rawValue)
                        )
                    ]
                )
            )
        }
    }

    private static func markdownData(
        for participant: ParticipantDTO,
        context: FileTreeWriteContext? = nil
    ) throws -> Data {
        try Data(markdownString(for: participant, context: context).utf8)
    }

    private static func markdownString(
        for participant: ParticipantDTO,
        context: FileTreeWriteContext? = nil
    ) throws -> String {
        let conversion = MarkdownWithFrontMatterConversion<ParticipantDTO>()
        let frontMatter = frontMatterParticipant(for: participant)

        if let existing = try context?.rootText(),
           let existingMarkdown = try? conversion.apply(existing),
           existingMarkdown.frontMatter == frontMatter
        {
            return try conversion.unapply(
                MarkdownWithFrontMatter(
                    frontMatter: existingMarkdown.frontMatter,
                    body: participant.bio
                )
            )
        }

        return try conversion.unapply(
            MarkdownWithFrontMatter(
                frontMatter: frontMatter,
                body: participant.bio
            )
        )
    }

    private static func frontMatterParticipant(for participant: ParticipantDTO) -> ParticipantDTO {
        var frontMatter = participant
        frontMatter.bio = nil
        return frontMatter
    }
}

public struct MissingFrontMatterError: Error, Equatable {
    public var fileName: String

    public init(fileName: String) {
        self.fileName = fileName
    }
}

private extension String {
    var nonEmptyMarkdownBody: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
