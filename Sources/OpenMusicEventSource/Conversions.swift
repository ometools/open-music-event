import FileTree
import Foundation
import FrontmatterParsing
import Yams

struct YamlConversion<Value: Codable & Equatable>: Conversion {
    typealias Input = Data
    typealias Output = Value

    func apply(_ input: Data) throws -> Value {
        try YAMLDecoder().decode(Value.self, from: input)
    }

    func unapply(_ output: Value) throws -> Data {
        try Data(YAMLEncoder().encode(output).utf8)
    }

    func unapply(
        _ output: Value,
        in context: FileTreeWriteContext
    ) -> Conversions.Result<Data> {
        if let existing = try? context.rootData(),
           (try? YAMLDecoder().decode(Value.self, from: existing)) == output {
            return .value(existing)
        }

        do {
            return .value(try unapply(output))
        } catch {
            return .invalid(
                diagnostics: .init(
                    diagnostics: [
                        Diagnostic(
                            severity: .error,
                            code: "open-music-event.yaml.print.failed",
                            message: String(describing: error)
                        )
                    ]
                )
            )
        }
    }
}

public struct ContributorMarkdownConversion: Conversion {
    public typealias Input = FileContent<Data>
    public typealias Output = FileContent<ContributorDTO>

    public init() {}

    public func apply(_ input: FileContent<Data>) throws -> FileContent<ContributorDTO> {
        let markdown = try MarkdownWithFrontMatterConversion<ContributorDTO>()
            .apply(String(decoding: input.data, as: UTF8.self))
        guard var contributor = markdown.frontMatter else {
            throw MissingFrontMatterError(fileName: input.fileName)
        }

        if let body = markdown.body?.nonEmptyMarkdownBody {
            contributor.bio = body
        }

        return try input.map { _ in contributor }
    }

    public func unapply(_ output: FileContent<ContributorDTO>) throws -> FileContent<Data> {
        try output.map { contributor in
            try Self.markdownData(for: contributor)
        }
    }

    public func unapply(
        _ output: FileContent<ContributorDTO>,
        in context: FileTreeWriteContext
    ) -> Conversions.Result<FileContent<Data>> {
        do {
            let rootedContext = context.rooted(at: output)
            return .value(
                try output.map { contributor in
                    try Self.markdownData(for: contributor, context: rootedContext)
                }
            )
        } catch {
            return .invalid(
                diagnostics: .init(
                    diagnostics: [
                        Diagnostic(
                            severity: .error,
                            code: "open-music-event.contributor-markdown.print.failed",
                            message: String(describing: error),
                            location: .init(path: output.path.rawValue)
                        )
                    ]
                )
            )
        }
    }

    private static func markdownData(
        for contributor: ContributorDTO,
        context: FileTreeWriteContext? = nil
    ) throws -> Data {
        try Data(markdownString(for: contributor, context: context).utf8)
    }

    private static func markdownString(
        for contributor: ContributorDTO,
        context: FileTreeWriteContext? = nil
    ) throws -> String {
        let conversion = MarkdownWithFrontMatterConversion<ContributorDTO>()
        let frontMatter = frontMatterContributor(for: contributor)

        if let existing = try context?.rootText(),
           let existingMarkdown = try? conversion.apply(existing),
           existingMarkdown.frontMatter == frontMatter
        {
            return try conversion.unapply(
                MarkdownWithFrontMatter(
                    frontMatter: existingMarkdown.frontMatter,
                    body: contributor.bio
                )
            )
        }

        return try conversion.unapply(
            MarkdownWithFrontMatter(
                frontMatter: frontMatter,
                body: contributor.bio
            )
        )
    }

    private static func frontMatterContributor(for contributor: ContributorDTO) -> ContributorDTO {
        var frontMatter = contributor
        frontMatter.bio = nil
        return frontMatter
    }
}

public struct CommunicationPostMarkdownConversion: Conversion {
    public typealias Input = FileContent<Data>
    public typealias Output = FileContent<CommunicationPostDTO>

    public init() {}

    public func apply(_ input: FileContent<Data>) throws -> FileContent<CommunicationPostDTO> {
        let markdown = try MarkdownWithFrontMatterConversion<CommunicationPostFrontMatter>()
            .apply(String(decoding: input.data, as: UTF8.self))
        guard let frontMatter = markdown.frontMatter else {
            throw MissingFrontMatterError(fileName: input.fileName)
        }

        return try input.map { _ in
            CommunicationPostDTO(
                title: frontMatter.title,
                contents: (markdown.body ?? "").removingLeadingNewlines,
                headerImageURL: frontMatter.headerImageURLValue,
                timestamp: frontMatter.timestamp,
                isPinned: frontMatter.isPinned ?? false
            )
        }
    }

    public func unapply(_ output: FileContent<CommunicationPostDTO>) throws -> FileContent<Data> {
        try output.map { post in
            let markdown = try MarkdownWithFrontMatterConversion<CommunicationPostFrontMatter>()
                .unapply(
                    MarkdownWithFrontMatter(
                        frontMatter: CommunicationPostFrontMatter(post),
                        body: post.contents
                    )
                )
            return Data(markdown.utf8)
        }
    }
}

private struct CommunicationPostFrontMatter: Codable, Equatable {
    var title: String
    var headerImageURL: String?
    var timestamp: Date?
    var isPinned: Bool?

    init(
        title: String,
        headerImageURL: String? = nil,
        timestamp: Date? = nil,
        isPinned: Bool? = nil
    ) {
        self.title = title
        self.headerImageURL = headerImageURL
        self.timestamp = timestamp
        self.isPinned = isPinned
    }

    init(_ post: CommunicationPostDTO) {
        self.init(
            title: post.title,
            headerImageURL: post.headerImageURL?.absoluteString,
            timestamp: post.timestamp,
            isPinned: post.isPinned ? true : nil
        )
    }

    var headerImageURLValue: URL? {
        guard let value = headerImageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }

        return URL(string: value)
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

    var removingLeadingNewlines: String {
        var result = self
        while result.hasPrefix("\r\n") {
            result.removeFirst(2)
        }
        while result.hasPrefix("\n") || result.hasPrefix("\r") {
            result.removeFirst()
        }
        return result
    }
}
