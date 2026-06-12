import Foundation
import Parsing

public struct SourcePatchGitPatchCodec: Sendable {
    public init() {}

    public func format(_ patch: SourcePatch) throws -> Data {
        let text = try String(Self.parser.print(patch))
        return Data(text.utf8)
    }

    public func formatReviewPatch(_ patch: SourcePatch) throws -> Data {
        let text = try Self.parser.printReviewPatch(patch)
        return Data(text.utf8)
    }

    public func parse(_ data: Data) throws -> SourcePatch {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SourcePatchGitPatchCodecError.binaryPatch
        }

        var input = text[...]
        let patch = try Self.parser.parse(&input)
        guard input.isEmpty else {
            throw SourcePatchGitPatchCodecError.unsupportedPatch("Unexpected trailing input.")
        }
        return patch
    }

    private static let parser = CanonicalSourcePatchParser()
}

public enum SourcePatchGitPatchCodecError: Equatable, Error, Sendable {
    case binaryFile(String)
    case binaryPatch
    case missingContents(String)
    case unsupportedPatch(String)
}

private struct CanonicalSourcePatchParser: ParserPrinter {
    func parse(_ input: inout Substring) throws -> SourcePatch {
        var scanner = SourcePatchScanner(input)
        var fileChanges: [SourcePatchFileChange] = []

        while !scanner.isAtEnd {
            fileChanges.append(try scanner.parseFileChange())
        }

        input = scanner.remaining
        return SourcePatch(fileChanges: fileChanges)
    }

    func print(_ patch: SourcePatch, into input: inout Substring) throws {
        let text = try patch.fileChanges
            .map(Self.printFileChange)
            .joined()
        input.prepend(contentsOf: text)
    }

    func printReviewPatch(_ patch: SourcePatch) throws -> String {
        try patch.fileChanges
            .map(Self.printReviewFileChange)
            .joined()
    }

    private static func printReviewFileChange(_ change: SourcePatchFileChange) throws -> String {
        switch change.kind {
        case .added:
            guard let newContents = change.newContents else {
                throw SourcePatchGitPatchCodecError.missingContents(change.path)
            }
            guard isText(newContents) else {
                return printBinaryFileChange(change)
            }

        case .deleted:
            guard let oldContents = change.oldContents else {
                throw SourcePatchGitPatchCodecError.missingContents(change.path)
            }
            guard isText(oldContents) else {
                return printBinaryFileChange(change)
            }

        case .modified:
            guard let oldContents = change.oldContents,
                  let newContents = change.newContents
            else {
                throw SourcePatchGitPatchCodecError.missingContents(change.path)
            }
            guard isText(oldContents), isText(newContents) else {
                return printBinaryFileChange(change)
            }
        }

        return try printFileChange(change)
    }

    private static func printFileChange(_ change: SourcePatchFileChange) throws -> String {
        let oldText = try change.oldContents.map { try text($0, path: change.path) }
        let newText = try change.newContents.map { try text($0, path: change.path) }

        switch change.kind {
        case .added:
            guard let newText else {
                throw SourcePatchGitPatchCodecError.missingContents(change.path)
            }
            return """
            diff --git \(gitPath("a", change.path)) \(gitPath("b", change.path))
            new file mode 100644
            --- /dev/null
            +++ \(gitPath("b", change.path))
            """
            + "\n"
            + printHunk(old: "", new: newText)

        case .deleted:
            guard let oldText else {
                throw SourcePatchGitPatchCodecError.missingContents(change.path)
            }
            return """
            diff --git \(gitPath("a", change.path)) \(gitPath("b", change.path))
            deleted file mode 100644
            --- \(gitPath("a", change.path))
            +++ /dev/null
            """
            + "\n"
            + printHunk(old: oldText, new: "")

        case .modified:
            guard let oldText, let newText else {
                throw SourcePatchGitPatchCodecError.missingContents(change.path)
            }
            return """
            diff --git \(gitPath("a", change.path)) \(gitPath("b", change.path))
            --- \(gitPath("a", change.path))
            +++ \(gitPath("b", change.path))
            """
            + "\n"
            + printHunk(old: oldText, new: newText)
        }
    }

    private static func printBinaryFileChange(_ change: SourcePatchFileChange) -> String {
        switch change.kind {
        case .added:
            return """
            diff --git \(gitPath("a", change.path)) \(gitPath("b", change.path))
            new file mode 100644
            Binary files /dev/null and \(gitPath("b", change.path)) differ
            """
            + "\n"

        case .deleted:
            return """
            diff --git \(gitPath("a", change.path)) \(gitPath("b", change.path))
            deleted file mode 100644
            Binary files \(gitPath("a", change.path)) and /dev/null differ
            """
            + "\n"

        case .modified:
            return """
            diff --git \(gitPath("a", change.path)) \(gitPath("b", change.path))
            Binary files \(gitPath("a", change.path)) and \(gitPath("b", change.path)) differ
            """
            + "\n"
        }
    }

    private static func isText(_ data: Data) -> Bool {
        String(data: data, encoding: .utf8) != nil
    }

    private static func text(_ data: Data, path: String) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SourcePatchGitPatchCodecError.binaryFile(path)
        }
        return text
    }

    private static func printHunk(old oldText: String, new newText: String) -> String {
        let oldLines = gitPatchLines(oldText)
        let newLines = gitPatchLines(newText)
        guard !oldLines.isEmpty || !newLines.isEmpty else { return "" }

        var output = "@@ -\(range(start: 1, count: oldLines.count, emptyStart: 0)) +\(range(start: 1, count: newLines.count, emptyStart: 0)) @@\n"
        output += oldLines.map { $0.printed(prefix: "-") }.joined()
        output += newLines.map { $0.printed(prefix: "+") }.joined()
        return output
    }

    private static func range(start: Int, count: Int, emptyStart: Int) -> String {
        if count == 0 { return "\(emptyStart),0" }
        if count == 1 { return "\(start)" }
        return "\(start),\(count)"
    }
}

private struct SourcePatchScanner {
    var remaining: Substring

    init(_ input: Substring) {
        self.remaining = input
    }

    var isAtEnd: Bool {
        remaining.isEmpty
    }

    mutating func parseFileChange() throws -> SourcePatchFileChange {
        let diffLine = try consumeLine(startingWith: "diff --git ")
        let (oldDiffPath, newDiffPath) = try parseDiffPaths(diffLine)

        let kind: SourcePatchFileChange.Kind
        if consumeLine(ifEqualTo: "new file mode 100644") {
            kind = .added
        } else if consumeLine(ifEqualTo: "deleted file mode 100644") {
            kind = .deleted
        } else {
            kind = .modified
        }

        let oldHeaderPath = try consumeFilePathLine(prefix: "--- ")
        let newHeaderPath = try consumeFilePathLine(prefix: "+++ ")

        let path: String
        switch kind {
        case .added:
            guard oldHeaderPath == nil,
                  let newPath = try canonicalPath(newHeaderPath, expectedPrefix: "b/"),
                  try canonicalPath(oldDiffPath, expectedPrefix: "a/") == newPath,
                  try canonicalPath(newDiffPath, expectedPrefix: "b/") == newPath
            else {
                throw SourcePatchGitPatchCodecError.unsupportedPatch("Added file headers do not match.")
            }
            path = newPath

        case .deleted:
            guard newHeaderPath == nil,
                  let oldPath = try canonicalPath(oldHeaderPath, expectedPrefix: "a/"),
                  try canonicalPath(oldDiffPath, expectedPrefix: "a/") == oldPath,
                  try canonicalPath(newDiffPath, expectedPrefix: "b/") == oldPath
            else {
                throw SourcePatchGitPatchCodecError.unsupportedPatch("Deleted file headers do not match.")
            }
            path = oldPath

        case .modified:
            guard let oldPath = try canonicalPath(oldHeaderPath, expectedPrefix: "a/"),
                  let newPath = try canonicalPath(newHeaderPath, expectedPrefix: "b/"),
                  oldPath == newPath,
                  try canonicalPath(oldDiffPath, expectedPrefix: "a/") == oldPath,
                  try canonicalPath(newDiffPath, expectedPrefix: "b/") == oldPath
            else {
                throw SourcePatchGitPatchCodecError.unsupportedPatch("Modified file headers do not match.")
            }
            path = oldPath
        }

        let hunk = try parseHunkIfPresent()
        switch kind {
        case .added:
            return SourcePatchFileChange(
                path: path,
                kind: kind,
                newContents: Data(hunk.newText.utf8)
            )

        case .deleted:
            return SourcePatchFileChange(
                path: path,
                kind: kind,
                oldContents: Data(hunk.oldText.utf8)
            )

        case .modified:
            return SourcePatchFileChange(
                path: path,
                kind: kind,
                oldContents: Data(hunk.oldText.utf8),
                newContents: Data(hunk.newText.utf8)
            )
        }
    }

    mutating func parseHunkIfPresent() throws -> (oldText: String, newText: String) {
        guard remaining.hasPrefix("@@ ") else {
            return ("", "")
        }

        let header = try consumeLine(startingWith: "@@ ")
        let ranges = try parseHunkRanges(header)
        var oldLines: [GitPatchLine] = []
        var newLines: [GitPatchLine] = []
        var side = HunkSide.old
        var lastSide: HunkSide?

        while !isAtEnd, !remaining.hasPrefix("diff --git ") {
            let line = try consumeLine()
            if line.hasPrefix("-") {
                guard side == .old else {
                    throw SourcePatchGitPatchCodecError.unsupportedPatch("Old hunk lines must precede new hunk lines.")
                }
                oldLines.append(GitPatchLine(text: String(line.dropFirst()), hasTerminator: true))
                lastSide = .old
            } else if line.hasPrefix("+") {
                side = .new
                newLines.append(GitPatchLine(text: String(line.dropFirst()), hasTerminator: true))
                lastSide = .new
            } else if line == "\\ No newline at end of file" {
                try markNoNewline(side: lastSide, oldLines: &oldLines, newLines: &newLines)
            } else {
                throw SourcePatchGitPatchCodecError.unsupportedPatch("Only full-file hunks are supported.")
            }
        }

        guard oldLines.count == ranges.oldCount,
              newLines.count == ranges.newCount
        else {
            throw SourcePatchGitPatchCodecError.unsupportedPatch("Hunk line count does not match header.")
        }

        return (text(from: oldLines), text(from: newLines))
    }

    private mutating func consumeLine(ifEqualTo expected: String) -> Bool {
        guard let line = peekLine(), line == expected else { return false }
        _ = try? consumeLine()
        return true
    }

    private mutating func consumeLine(startingWith prefix: String) throws -> String {
        let line = try consumeLine()
        guard line.hasPrefix(prefix) else {
            throw SourcePatchGitPatchCodecError.unsupportedPatch("Expected line starting with \(prefix).")
        }
        return line
    }

    private mutating func consumeLine() throws -> String {
        guard let newlineIndex = remaining.firstIndex(of: "\n") else {
            let line = String(remaining)
            remaining.removeAll()
            return line
        }

        let line = String(remaining[..<newlineIndex])
        remaining.removeSubrange(...newlineIndex)
        return line
    }

    private func peekLine() -> String? {
        guard !remaining.isEmpty else { return nil }
        guard let newlineIndex = remaining.firstIndex(of: "\n") else {
            return String(remaining)
        }
        return String(remaining[..<newlineIndex])
    }

    private mutating func consumeFilePathLine(prefix: String) throws -> String? {
        let line = try consumeLine(startingWith: prefix)
        let rawPath = String(line.dropFirst(prefix.count))
        return rawPath == "/dev/null" ? nil : try parseGitPathToken(rawPath).path
    }
}

private enum HunkSide {
    case old
    case new
}

private struct GitPatchLine: Equatable {
    var text: String
    var hasTerminator: Bool

    func printed(prefix: Character) -> String {
        var output = "\(prefix)\(text)\n"
        if !hasTerminator {
            output += "\\ No newline at end of file\n"
        }
        return output
    }
}

private func gitPatchLines(_ text: String) -> [GitPatchLine] {
    guard !text.isEmpty else { return [] }

    var lines: [GitPatchLine] = []
    var current = ""

    for character in text {
        if character == "\n" {
            lines.append(GitPatchLine(text: current, hasTerminator: true))
            current = ""
        } else {
            current.append(character)
        }
    }

    if !current.isEmpty || !text.hasSuffix("\n") {
        lines.append(GitPatchLine(text: current, hasTerminator: false))
    }

    return lines
}

private func text(from lines: [GitPatchLine]) -> String {
    lines.reduce(into: "") { text, line in
        text += line.text
        if line.hasTerminator {
            text += "\n"
        }
    }
}

private func gitPath(_ prefix: String, _ path: String) -> String {
    let prefixedPath = "\(prefix)/\(path)"
    guard prefixedPath.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
        return prefixedPath
    }

    let escaped = prefixedPath
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

private func parseDiffPaths(_ line: String) throws -> (old: String, new: String) {
    let prefix = "diff --git "
    guard line.hasPrefix(prefix) else {
        throw SourcePatchGitPatchCodecError.unsupportedPatch("Expected diff header.")
    }

    let firstToken = try parseGitPathToken(String(line.dropFirst(prefix.count)))
    let remainder = firstToken.remainder.trimmingPrefix(" ")
    let secondToken = try parseGitPathToken(remainder)
    guard secondToken.remainder.isEmpty else {
        throw SourcePatchGitPatchCodecError.unsupportedPatch("Unexpected diff header suffix.")
    }
    return (firstToken.path, secondToken.path)
}

private func parseGitPathToken(_ input: String) throws -> (path: String, remainder: String) {
    guard !input.isEmpty else {
        throw SourcePatchGitPatchCodecError.unsupportedPatch("Missing path.")
    }

    if input.first == "\"" {
        var path = ""
        var isEscaped = false
        var index = input.index(after: input.startIndex)
        while index < input.endIndex {
            let character = input[index]
            if isEscaped {
                path.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                return (path, String(input[input.index(after: index)...]))
            } else {
                path.append(character)
            }
            index = input.index(after: index)
        }
        throw SourcePatchGitPatchCodecError.unsupportedPatch("Unterminated quoted path.")
    }

    if let spaceIndex = input.firstIndex(of: " ") {
        return (
            String(input[..<spaceIndex]),
            String(input[input.index(after: spaceIndex)...])
        )
    }

    return (input, "")
}

private func canonicalPath(_ path: String?, expectedPrefix: String) throws -> String? {
    guard let path else { return nil }
    guard path.hasPrefix(expectedPrefix) else {
        throw SourcePatchGitPatchCodecError.unsupportedPatch("Path is missing \(expectedPrefix) prefix.")
    }
    let canonicalPath = String(path.dropFirst(expectedPrefix.count))
    guard !canonicalPath.isEmpty else {
        throw SourcePatchGitPatchCodecError.unsupportedPatch("Path cannot be empty.")
    }
    return canonicalPath
}

private func parseHunkRanges(_ line: String) throws -> (oldCount: Int, newCount: Int) {
    let pattern = #"^@@ -([0-9]+)(?:,([0-9]+))? \+([0-9]+)(?:,([0-9]+))? @@$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(
            in: line,
            range: NSRange(line.startIndex..., in: line)
          ),
          match.numberOfRanges == 5
    else {
        throw SourcePatchGitPatchCodecError.unsupportedPatch("Unsupported hunk header.")
    }

    func integer(at rangeIndex: Int, default defaultValue: Int) throws -> Int {
        let range = match.range(at: rangeIndex)
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: line)
        else { return defaultValue }
        guard let value = Int(line[swiftRange]) else {
            throw SourcePatchGitPatchCodecError.unsupportedPatch("Invalid hunk range.")
        }
        return value
    }

    return (
        oldCount: try integer(at: 2, default: 1),
        newCount: try integer(at: 4, default: 1)
    )
}

private func markNoNewline(
    side: HunkSide?,
    oldLines: inout [GitPatchLine],
    newLines: inout [GitPatchLine]
) throws {
    switch side {
    case .old:
        guard !oldLines.isEmpty else {
            throw SourcePatchGitPatchCodecError.unsupportedPatch("No old line for no-newline marker.")
        }
        oldLines[oldLines.count - 1].hasTerminator = false

    case .new:
        guard !newLines.isEmpty else {
            throw SourcePatchGitPatchCodecError.unsupportedPatch("No new line for no-newline marker.")
        }
        newLines[newLines.count - 1].hasTerminator = false

    case nil:
        throw SourcePatchGitPatchCodecError.unsupportedPatch("No line for no-newline marker.")
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
