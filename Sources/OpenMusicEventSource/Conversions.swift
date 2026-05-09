import FileTree
import Foundation
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

struct ParticipantMarkdownConversion: Conversion {
    typealias Input = FileContent<Data>
    typealias Output = FileContent<ParticipantDTO>

    func apply(_ input: FileContent<Data>) throws -> FileContent<ParticipantDTO> {
        let markdown = try MarkdownWithFrontMatter<ParticipantDTO>(data: input.data)
        guard var participant = markdown.frontMatter else {
            throw MissingFrontMatterError(fileName: input.fileName)
        }

        if let body = markdown.body?.nonEmptyMarkdownBody {
            participant.bio = body
        }

        return try input.map { _ in participant }
    }

    func unapply(_ output: FileContent<ParticipantDTO>) throws -> FileContent<Data> {
        throw SourceWritingUnsupportedError()
    }
}

struct MarkdownWithFrontMatter<FrontMatter: Decodable> {
    var frontMatter: FrontMatter?
    var body: String?

    init(data: Data) throws {
        let string = String(decoding: data, as: UTF8.self)
        guard string.hasPrefix("---\n") || string.hasPrefix("---\r\n") else {
            self.frontMatter = nil
            self.body = string
            return
        }

        let normalized = string.replacingOccurrences(of: "\r\n", with: "\n")
        let content = normalized.dropFirst("---\n".count)
        guard let closingRange = content.range(of: "\n---") else {
            throw UnterminatedFrontMatterError()
        }

        let yaml = String(content[..<closingRange.lowerBound])
        var remaining = content[closingRange.upperBound...]
        if remaining.first == "\n" {
            remaining.removeFirst()
        }

        self.frontMatter = try YAMLDecoder().decode(FrontMatter.self, from: Data(yaml.utf8))
        self.body = String(remaining)
    }
}

struct MissingFrontMatterError: Error, Equatable {
    var fileName: String
}

struct UnterminatedFrontMatterError: Error, Equatable {}
struct SourceWritingUnsupportedError: Error, Equatable {}

private extension String {
    var nonEmptyMarkdownBody: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
