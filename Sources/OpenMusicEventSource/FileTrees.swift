import FileTree
import Foundation

public struct OpenMusicEventSourceRepositoryFileTree: FileTreeWriter {
    public init() {}

    public var body: some FileTreeWriter<OpenMusicEventSourceRepository> {
        FileTree {
            File.Optional("calendar", "yml")
                .convert(YamlConversion<CalendarDTO>())

            Directory("events") {
                Directory.Many {
                    OpenMusicEventSourceEventFileTree()
                }
            }
        }
        .convert(RepositoryConversion())
    }
}

public struct OpenMusicEventSourceEventFileTree: FileTreeWriter {
    public typealias Body = Never

    public init() {}

    public func read(from url: URL) throws -> FileTreeResult<OpenMusicEventSourceEvent> {
        let eventResult = try eventFile.read(from: url)
        let stagesResult = try readOptionalSourceDirectory(
            "stages",
            component: stagesFiles,
            from: url
        )
        let contributorsResult = try readOptionalSourceDirectory(
            "contributors",
            component: contributorsFiles,
            from: url
        )
        let postersResult = try readOptionalSourceDirectory(
            "posters",
            component: postersFiles,
            from: url
        )
        let schedulesResult = try readOptionalSourceDirectory(
            "schedules",
            component: schedulesFiles,
            from: url
        )
        let channelsResult = try readOptionalSourceDirectory(
            "channels",
            component: channelsFiles,
            from: url
        )

        debugSourceFileTreeRead(
            "event-read components url=\(url.path) event=\(debugFileTreeOutput(eventResult.output)) stages=\(debugOptionalFileCount(stagesResult.output)) contributors=\(debugOptionalFileCount(contributorsResult.output)) posters=\(debugOptionalFileCount(postersResult.output)) schedules=\(debugOptionalFileCount(schedulesResult.output)) channels=\(debugOptionalFileCount(channelsResult.output))"
        )

        var diagnostics = DiagnosticReport<FileTreeLocation>()
        diagnostics.append(contentsOf: eventResult.diagnostics)
        diagnostics.append(contentsOf: stagesResult.diagnostics)
        diagnostics.append(contentsOf: contributorsResult.diagnostics)
        diagnostics.append(contentsOf: postersResult.diagnostics)
        diagnostics.append(contentsOf: schedulesResult.diagnostics)
        diagnostics.append(contentsOf: channelsResult.diagnostics)

        var graph = SourceGraph()
        graph.append(eventResult.graph)
        graph.append(stagesResult.graph)
        graph.append(contributorsResult.graph)
        graph.append(postersResult.graph)
        graph.append(schedulesResult.graph)
        graph.append(channelsResult.graph)

        do {
            let event = try eventResult.output.requiredValue
            let stages = try stagesResult.output.requiredValue
            let contributors = try contributorsResult.output.requiredValue
            let posters = try postersResult.output.requiredValue
            let schedules = try schedulesResult.output.requiredValue
            let channels = try channelsResult.output.requiredValue
            guard !diagnostics.hasErrors else {
                return .invalid(graph: graph, diagnostics: diagnostics)
            }
            return .value(
                OpenMusicEventSourceEvent(
                    event: event,
                    stages: stages,
                    contributors: contributors,
                    posters: posters,
                    schedules: schedules,
                    channels: channels
                ),
                graph: graph,
                diagnostics: diagnostics
            )
        } catch {
            return .invalid(graph: graph, diagnostics: diagnostics)
        }
    }

    public func write(
        _ content: OpenMusicEventSourceEvent,
        to url: URL
    ) throws -> FileTreeResult<OpenMusicEventSourceEvent> {
        try write(content, to: url, context: FileTreeWriteContext(graph: .init()))
    }

    public func write(
        _ content: OpenMusicEventSourceEvent,
        to url: URL,
        context: FileTreeWriteContext
    ) throws -> FileTreeResult<OpenMusicEventSourceEvent> {
        let eventResult = try eventFile.write(content.event, to: url, context: context)
        let stagesResult = try writeOptionalSourceDirectory(
            content.stages,
            to: url,
            directoryName: "stages",
            component: stagesFiles,
            context: context
        )
        let contributorsResult = try writeOptionalSourceDirectory(
            content.contributors,
            to: url,
            directoryName: "contributors",
            component: contributorsFiles,
            context: context
        )
        let postersResult = try writeOptionalSourceDirectory(
            content.posters,
            to: url,
            directoryName: "posters",
            component: postersFiles,
            context: context
        )
        let schedulesResult = try writeOptionalSourceDirectory(
            content.schedules,
            to: url,
            directoryName: "schedules",
            component: schedulesFiles,
            context: context
        )
        let channelsResult = try writeOptionalSourceDirectory(
            content.channels,
            to: url,
            directoryName: "channels",
            component: channelsFiles,
            context: context
        )

        var diagnostics = DiagnosticReport<FileTreeLocation>()
        diagnostics.append(contentsOf: eventResult.diagnostics)
        diagnostics.append(contentsOf: stagesResult.diagnostics)
        diagnostics.append(contentsOf: contributorsResult.diagnostics)
        diagnostics.append(contentsOf: postersResult.diagnostics)
        diagnostics.append(contentsOf: schedulesResult.diagnostics)
        diagnostics.append(contentsOf: channelsResult.diagnostics)

        var graph = SourceGraph()
        graph.append(eventResult.graph)
        graph.append(stagesResult.graph)
        graph.append(contributorsResult.graph)
        graph.append(postersResult.graph)
        graph.append(schedulesResult.graph)
        graph.append(channelsResult.graph)

        do {
            _ = try eventResult.output.requiredValue
            _ = try stagesResult.output.requiredValue
            _ = try contributorsResult.output.requiredValue
            _ = try postersResult.output.requiredValue
            _ = try schedulesResult.output.requiredValue
            _ = try channelsResult.output.requiredValue
            guard !diagnostics.hasErrors else {
                return .invalid(graph: graph, diagnostics: diagnostics)
            }
            return .value(content, graph: graph, diagnostics: diagnostics)
        } catch {
            return .invalid(graph: graph, diagnostics: diagnostics)
        }
    }

    private var eventFile: some FileTreeWriter<EventDTO> {
        File("event", "yml")
            .convert(YamlConversion<EventDTO>())
    }

    private var stagesFiles: some FileTreeWriter<[FileContent<StageDTO>]> {
        File.Many(withExtension: "yml")
            .map(FileContentConversion(YamlConversion<StageDTO>()))
    }

    private var contributorsFiles: some FileTreeWriter<[FileContent<ContributorDTO>]> {
        File.Many(withExtension: "md")
            .map(ContributorMarkdownConversion())
    }

    private var postersFiles: some FileTreeWriter<[FileContent<PosterDTO>]> {
        File.Many(withExtension: "yml")
            .map(FileContentConversion(YamlConversion<PosterDTO>()))
    }

    private var schedulesFiles: some FileTreeWriter<[FileContent<ScheduleDTO>]> {
        File.Many(withExtension: "yml")
            .map(FileContentConversion(YamlConversion<ScheduleDTO>()))
    }

    private var channelsFiles: some FileTreeWriter<[FileContent<ChannelDTO>]> {
        File.Many(withExtension: "yml")
            .map(FileContentConversion(YamlConversion<ChannelDTO>()))
    }
}

private func readOptionalSourceDirectory<Component: FileTreeWriter>(
    _ directoryName: String,
    component: Component,
    from url: URL
) throws -> FileTreeResult<Component.Content?> {
    let directoryURL = url.appending(path: directoryName, directoryHint: .isDirectory)
    var isDirectory = ObjCBool(false)
    let exists = FileManager.default.fileExists(
        atPath: directoryURL.path,
        isDirectory: &isDirectory
    )
    guard exists, isDirectory.boolValue else {
        return .value(nil)
    }

    let result = try component.read(from: directoryURL)
    return optionalSourceDirectoryResult(result, directoryName: directoryName)
}

private func writeOptionalSourceDirectory<Component: FileTreeWriter>(
    _ content: Component.Content?,
    to url: URL,
    directoryName: String,
    component: Component,
    context: FileTreeWriteContext
) throws -> FileTreeResult<Component.Content?> {
    let directoryURL = url.appending(path: directoryName, directoryHint: .isDirectory)
    guard let content else {
        if deletingNilOptionalWrites,
           FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }
        return .value(nil)
    }

    if !FileManager.default.fileExists(atPath: directoryURL.path) {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
    }

    let result = try component.write(
        content,
        to: directoryURL,
        context: sourceFileTreeWriteContext(context, descendingInto: directoryName)
    )
    return optionalSourceDirectoryResult(result, directoryName: directoryName)
}

private func optionalSourceDirectoryResult<Value>(
    _ result: FileTreeResult<Value>,
    directoryName: String
) -> FileTreeResult<Value?> {
    let prefix = SourceGraph.Path(rawValue: directoryName)
    let directoryIdentity = SourceGraph.Node.Identity.directory(prefix)
    var graph = result.graph.prefixingPaths(with: prefix)
    let directoryID = graph.insert(directoryIdentity)

    for childID in graph.rootNodeIDs where childID != directoryID {
        graph.connect(directoryID, to: childID, kind: .contains)
    }
    graph.root = directoryID

    return FileTreeResult(
        output: result.output.map { Swift.Optional.some($0) },
        graph: graph,
        diagnostics: result.diagnostics.prefixingPaths(with: prefix)
    )
}

private func sourceFileTreeWriteContext(
    _ context: FileTreeWriteContext,
    descendingInto directoryName: String
) -> FileTreeWriteContext {
    var copy = context
    copy.sourceURL = context.sourceURL?.appending(
        path: directoryName,
        directoryHint: .isDirectory
    )
    copy.rootPath = nil
    return copy
}

private struct RepositoryConversion: Conversion {
    typealias Input = (
        CalendarDTO?,
        [DirectoryContent<OpenMusicEventSourceEvent>]
    )
    typealias Output = OpenMusicEventSourceRepository

    func apply(_ input: Input) throws -> Output {
        OpenMusicEventSourceRepository(
            calendar: input.0,
            events: input.1
        )
    }

    func unapply(_ output: Output) throws -> Input {
        (
            output.calendar,
            output.events
        )
    }
}

#if DEBUG
private func debugSourceFileTreeRead(_ message: @autoclosure () -> String) {
    print("[OME SourceFileTree] \(message())")
}
#else
private func debugSourceFileTreeRead(_ message: @autoclosure () -> String) {}
#endif

private func debugFileTreeOutput<Value>(
    _ output: FileTreeResult<Value>.Output
) -> String {
    switch output {
    case .value:
        return "value"
    case .invalid:
        return "invalid"
    }
}

private func debugOptionalFileCount<Value>(
    _ output: FileTreeResult<[FileContent<Value>]?>.Output
) -> String {
    switch output {
    case let .value(.some(files)):
        return "\(files.count)"
    case .value(nil):
        return "nil"
    case .invalid:
        return "invalid"
    }
}
