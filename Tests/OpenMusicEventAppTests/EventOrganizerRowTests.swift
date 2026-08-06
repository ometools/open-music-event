#if canImport(AppKit) && canImport(ImageIO)
import AppKit
import ATProto
import BlueskyActorCache
import ComposableCalendarEvents
import Dependencies
import DependenciesTestSupport
import Foundation
import ImageIO
@testable import OpenMusicEventApp
import OpenMusicEventLexicon
import SQLiteData
import SwiftUI
import Testing

private func eventOrganizerRowDatabase() throws -> any DatabaseWriter {
    let database = try DatabaseQueue()
    var migrator = DatabaseMigrator()
    OME.DatabaseMigrations.register(into: &migrator)
    try migrator.migrate(database)
    return database
}

private func eventOrganizerRowActorProfileCache() -> BlueskyActorProfileCacheClient {
    BlueskyActorProfileCacheClient(
        cachedProfile: { _ in nil },
        refreshProfile: { _ in throw BlueskyActorProfileCacheClientError.unimplemented },
        refreshProfileIfNeeded: { _, _, _ in nil }
    )
}

@Suite(
    .dependency(\.defaultDatabase, try eventOrganizerRowDatabase()),
    .dependency(\.blueskyActorProfileCache, eventOrganizerRowActorProfileCache())
)
@MainActor
struct EventOrganizerRowTests {
    @Test
    func `opaque organizer avatars keep their original colors`() async throws {
        let avatarURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("opaque-organizer-avatar-\(UUID().uuidString).jpg")
        try opaqueJPEGData().write(to: avatarURL)
        defer { try? FileManager.default.removeItem(at: avatarURL) }

        let organizerID = try #require(DID("did:plc:wickedwoods"))
        let row = EventOrganizerRow(
            organizer: CalendarEvent.Organizer(
                id: organizerID,
                displayName: "Wicked Woods Music & Arts Festival",
                avatarURL: avatarURL
            )
        )
        .frame(width: 360, height: 60, alignment: .leading)

        let hostingView = NSHostingView(rootView: row)
        hostingView.frame = CGRect(x: 0, y: 0, width: 360, height: 60)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView

        var avatarColor: NSColor?
        for _ in 0..<100 {
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            avatarColor = color(at: CGPoint(x: 30, y: 30), in: hostingView)
            if let avatarColor,
               avatarColor.blueComponent > 0.6,
               avatarColor.redComponent < 0.3 {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let sampledAvatarColor = try #require(avatarColor?.usingColorSpace(.deviceRGB))
        #expect(sampledAvatarColor.blueComponent > 0.6)
        #expect(sampledAvatarColor.redComponent < 0.3)
    }

    func opaqueJPEGData() throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: 60,
                height: 60,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(
                data,
                "public.jpeg" as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func color(at point: CGPoint, in view: NSView) -> NSColor? {
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds),
              view.bounds.width > 0,
              view.bounds.height > 0 else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        let x = Int(point.x / view.bounds.width * CGFloat(representation.pixelsWide))
        let y = Int(point.y / view.bounds.height * CGFloat(representation.pixelsHigh))
        return representation.colorAt(x: x, y: y)
    }
}
#endif
