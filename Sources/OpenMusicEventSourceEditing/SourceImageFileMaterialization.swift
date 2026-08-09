import FileTree
import Foundation
import OpenMusicEventSource

enum SourceImageFileMaterializationError: Equatable, Error, Sendable {
    case missingLocalImageFile(URL)
}

extension OpenMusicEventSourceRepository {
    func materializingLocalImageFiles(at repositoryURL: URL) throws -> Self {
        var repository = self

        if var calendar = repository.calendar {
            var usedPaths = Self.sourceImageFilePaths(in: calendar.images)
            calendar.images = try Self.materialize(
                calendar.images,
                at: repositoryURL,
                parentFileName: "calendar",
                usedPaths: &usedPaths
            )
            repository.calendar = calendar
        }

        repository.events = try repository.events.map { directory in
            try directory.map { event in
                try event.materializingLocalImageFiles(
                    at: repositoryURL
                        .appending(path: "events")
                        .appending(path: directory.directoryName)
                )
            }
        }

        return repository
    }
}

extension OpenMusicEventSourceEvent {
    func materializingLocalImageFiles(at eventURL: URL) throws -> Self {
        var event = self
        var usedPaths = Set<String>()
        Self.collectSourceImageFilePaths(in: event, into: &usedPaths)

        event.event.images = try Self.materialize(
            event.event.images,
            at: eventURL,
            parentFileName: "event",
            usedPaths: &usedPaths
        )
        event.stages = try event.stages?.map { file in
            try file.map { stage in
                var stage = stage
                stage.images = try Self.materialize(
                    stage.images,
                    at: eventURL,
                    parentFileName: file.fileName,
                    usedPaths: &usedPaths
                )
                return stage
            }
        }
        event.contributors = try event.contributors?.map { file in
            try file.map { contributor in
                var contributor = contributor
                contributor.images = try Self.materialize(
                    contributor.images,
                    at: eventURL,
                    parentFileName: file.fileName,
                    usedPaths: &usedPaths
                )
                return contributor
            }
        }
        event.posters = try event.posters?.map { file in
            try file.map { poster in
                var poster = poster
                poster.image = try Self.materialize(
                    poster.image,
                    at: eventURL,
                    parentFileName: file.fileName,
                    usedPaths: &usedPaths
                )
                return poster
            }
        }
        event.communicationPosts = try event.communicationPosts?.map { directory in
            try directory.map { posts in
                try posts.map { file in
                    try file.map { post in
                        var post = post
                        post.images = try Self.materialize(
                            post.images,
                            at: eventURL,
                            parentFileName: "\(directory.directoryName)-\(file.fileName)",
                            usedPaths: &usedPaths
                        )
                        return post
                    }
                }
            }
        }

        return event
    }
}

private extension OpenMusicEventSourceRepository {
    static func materialize(
        _ images: [SourceImageAsset]?,
        at sourceDirectoryURL: URL,
        parentFileName: String,
        usedPaths: inout Set<String>
    ) throws -> [SourceImageAsset]? {
        guard var images else { return nil }
        for index in images.indices {
            images[index] = try materialize(
                images[index],
                at: sourceDirectoryURL,
                parentFileName: parentFileName,
                usedPaths: &usedPaths
            )
        }
        return images.isEmpty ? nil : images
    }

    static func materialize(
        _ image: SourceImageAsset,
        at sourceDirectoryURL: URL,
        parentFileName: String,
        usedPaths: inout Set<String>
    ) throws -> SourceImageAsset {
        try image.mapPayloads { payload, appearance in
            guard case let .url(url) = payload.source, url.isFileURL else {
                if case let .file(path) = payload.source {
                    usedPaths.insert(path)
                }
                return payload
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                throw SourceImageFileMaterializationError.missingLocalImageFile(url)
            }

            let sourcePath = materializedImagePath(
                for: image,
                appearance: appearance,
                parentFileName: parentFileName,
                sourceURL: url,
                usedPaths: &usedPaths
            )
            let destinationURL = sourceDirectoryURL.appending(path: sourcePath)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contentsOf: url).write(to: destinationURL, options: .atomic)

            var payload = payload
            payload.assetKey = nil
            payload.source = .file(sourcePath)
            return payload
        }
    }

    static func sourceImageFilePaths(in images: [SourceImageAsset]?) -> Set<String> {
        var paths = Set<String>()
        for image in images ?? [] {
            for variant in image.payloads {
                if case let .file(path) = variant.payload.source {
                    paths.insert(path)
                }
            }
        }
        return paths
    }

    static func materializedImagePath(
        for image: SourceImageAsset,
        appearance: OMERecord.ImageAsset.Appearance?,
        parentFileName: String,
        sourceURL: URL,
        usedPaths: inout Set<String>
    ) -> String {
        let base = [
            parentFileName.fileSafeSourceImagePathComponent,
            image.role.rawValue.fileSafeSourceImagePathComponent,
            appearance?.rawValue.fileSafeSourceImagePathComponent,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "-")
        let fileExtension = sourceURL.pathExtension.isEmpty
            ? "bin"
            : sourceURL.pathExtension.lowercased()
        var candidate = "images/\(base).\(fileExtension)"
        var suffix = 2
        while usedPaths.contains(candidate) {
            candidate = "images/\(base)-\(suffix).\(fileExtension)"
            suffix += 1
        }
        usedPaths.insert(candidate)
        return candidate
    }
}

private extension OpenMusicEventSourceEvent {
    static func materialize(
        _ images: [SourceImageAsset]?,
        at sourceDirectoryURL: URL,
        parentFileName: String,
        usedPaths: inout Set<String>
    ) throws -> [SourceImageAsset]? {
        try OpenMusicEventSourceRepository.materialize(
            images,
            at: sourceDirectoryURL,
            parentFileName: parentFileName,
            usedPaths: &usedPaths
        )
    }

    static func materialize(
        _ image: SourceImageAsset,
        at sourceDirectoryURL: URL,
        parentFileName: String,
        usedPaths: inout Set<String>
    ) throws -> SourceImageAsset {
        try OpenMusicEventSourceRepository.materialize(
            image,
            at: sourceDirectoryURL,
            parentFileName: parentFileName,
            usedPaths: &usedPaths
        )
    }

    static func collectSourceImageFilePaths(
        in event: OpenMusicEventSourceEvent,
        into paths: inout Set<String>
    ) {
        paths.formUnion(OpenMusicEventSourceRepository.sourceImageFilePaths(in: event.event.images))
        for stage in event.stages ?? [] {
            paths.formUnion(OpenMusicEventSourceRepository.sourceImageFilePaths(in: stage.data.images))
        }
        for contributor in event.contributors ?? [] {
            paths.formUnion(OpenMusicEventSourceRepository.sourceImageFilePaths(in: contributor.data.images))
        }
        for poster in event.posters ?? [] {
            for variant in poster.data.image.payloads {
                if case let .file(path) = variant.payload.source {
                    paths.insert(path)
                }
            }
        }
        for directory in event.communicationPosts ?? [] {
            for post in directory.components {
                paths.formUnion(
                    OpenMusicEventSourceRepository.sourceImageFilePaths(in: post.data.images)
                )
            }
        }
    }
}

private extension String {
    var fileSafeSourceImagePathComponent: String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
