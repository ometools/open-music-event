//
//  CommunicationsFeature.swift
//  open-music-event
//
//  Created by Woodrow Melling on 7/31/25.
//
import SwiftUI
import Foundation
import CoreModels

struct CommunicationsFeature: View {

    @Observable
    @MainActor
    class Store {
        var channels: [Channel] = []

        func task() async {
            channels = Channel.previewData
        }
    }

    @State var store = Store()

    var body: some View {
        List {
            Section {
                ForEach(store.channels) { channel in
                    NavigationLink {
                        CommunicationChannelView(store: .init(channel))
                    } label: {
                        Row(channel: channel)
                    }
                }
            } header: {
                Text("Channels")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Communication")
        .task { await store.task() }
    }

    struct Row: View {
        var channel: Channel

        var body: some View {
            HStack(spacing: 12) {
                CachedAsyncImage(url: channel.iconImageURL)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.quaternary)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    Text(channel.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

public struct CommunicationChannelView: View {
    @MainActor
    @Observable
    class Store {
        init(_ channel: Channel) {
            self.channel = channel
        }

        var channel: Channel
        var pinnedPosts: [Post] = []
        var regularPosts: [Post] = []

        func task() async {
            let posts = Post.previewData.filter {
                $0.channelID == channel.id
            }
            pinnedPosts = posts.filter { $0.isPinned }
            regularPosts = posts.filter { $0.isPinned == false }
        }
    }

    let store: Store

    public var body: some View {
        List {
            if !store.pinnedPosts.isEmpty {
                Section {
                    ForEach(store.pinnedPosts) { post in
                        NavigationLink {
                            PostDetailView(post: post)
                        } label: {
                            Row(post: post)
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(Color.accentColor)

                        Text("Pinned")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
            }
            
            // Show regular posts
            if !store.regularPosts.isEmpty {
                Section {
                    ForEach(store.regularPosts) { post in
                        NavigationLink {
                            PostDetailView(post: post)
                        } label: {
                            Row(post: post)
                        }
                    }
                } header: {
                    Text("Recent Posts")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .task { await store.task() }
        .navigationTitle(store.channel.name)
    }

    struct Row: View {
        var post: Post

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if post.isPinned {
                                Image(systemName: "pin.fill")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                            }
                            
                            Text(post.title)
                                .font(.headline)
                                .fontWeight(.medium)
                        }
                        
                        Text(post.timestamp, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if let imageURL = post.headerImageURL {
                        CachedAsyncImage(url: imageURL)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                
                Text(post.contents)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PostDetailView: View {
    let post: Post
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let imageURL = post.headerImageURL {
                    CachedAsyncImage(url: imageURL)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if post.isPinned {
                            Image(systemName: "pin.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        
                        Text(post.title)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    Text(post.timestamp, format: .relative(presentation: .named))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Text(post.contents)
                    .font(.body)
                    .lineSpacing(4)
                
                Spacer()
            }
            .padding(.horizontal)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

public struct Channel: Equatable, Identifiable, Sendable, Codable {
    public typealias ID = OmeID<Channel>
    public var id: ID
    public var musicEventID: MusicEvent.ID?
    public var name: String
    public var description: String
    public var iconImageURL: URL?
    public var headerImageURL: URL?
    public var sortIndex: Int?
    
    public init(
        id: ID,
        musicEventID: MusicEvent.ID?,
        name: String,
        description: String,
        iconImageURL: URL? = nil,
        sortIndex: Int? = nil
    ) {
        self.id = id
        self.musicEventID = musicEventID
        self.name = name
        self.description = description
        self.iconImageURL = iconImageURL
        self.sortIndex = sortIndex
    }
}

public struct Post: Equatable, Identifiable, Sendable, Codable {
    public typealias ID = OmeID<Post>
    public var id: ID
    public var channelID: Channel.ID
    public var title: String
    public var contents: String
    public var headerImageURL: URL?
    public var timestamp: Date
    public var isPinned: Bool
    
    public init(
        id: ID,
        channelID: Channel.ID,
        title: String,
        contents: String,
        headerImageURL: URL? = nil,
        timestamp: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.channelID = channelID
        self.title = title
        self.contents = contents
        self.headerImageURL = headerImageURL
        self.timestamp = timestamp
        self.isPinned = isPinned
    }
}

extension Channel {
    public static let previewData: [Channel] = [
        Channel(
            id: Channel.ID(1),
            musicEventID: MusicEvent.ID(1),
            name: "General",
            description: "General festival announcements and updates",
            sortIndex: 1
        ),
        Channel(
            id: Channel.ID(2),
            musicEventID: MusicEvent.ID(1),
            name: "Activities",
            description: "Special activities, workshops, and experiences",
            sortIndex: 2
        ),
        Channel(
            id: Channel.ID(3),
            musicEventID: MusicEvent.ID(1),
            name: "Harm Reduction",
            description: "Safety information and harm reduction resources",
            sortIndex: 3
        ),
        Channel(
            id: Channel.ID(4),
            musicEventID: MusicEvent.ID(1),
            name: "Food & Vendors",
            description: "Information about food options and marketplace vendors",
            sortIndex: 4
        ),
        Channel(
            id: Channel.ID(5),
            musicEventID: MusicEvent.ID(1),
            name: "Transportation",
            description: "Parking, shuttles, and transportation updates",
            sortIndex: 5
        ),
        Channel(
            id: Channel.ID(6),
            musicEventID: MusicEvent.ID(1),
            name: "Sustainability",
            description: "Environmental initiatives and green practices",
            sortIndex: 6
        )
    ]
}

extension Post {
    public static let previewData: [Post] = [
        // General Channel Posts
        Post(
            id: Post.ID(1),
            channelID: Channel.ID(1),
            title: "Welcome to Festival 2025!",
            contents: "We're excited to have you join us for an incredible weekend of music, art, and community. Check your schedule, stay hydrated, and have an amazing time!",
            timestamp: Date().addingTimeInterval(-3600),
            isPinned: true
        ),
        Post(
            id: Post.ID(2),
            channelID: Channel.ID(1),
            title: "Weather Update",
            contents: "Sunny skies expected all weekend with temperatures reaching 75°F. Perfect festival weather! Don't forget sunscreen and bring a light jacket for evening shows.",
            timestamp: Date().addingTimeInterval(-1800),
            isPinned: false
        ),
        Post(
            id: Post.ID(3),
            channelID: Channel.ID(1),
            title: "Lost & Found Location",
            contents: "Lost something? Our Lost & Found is located at the Information Tent near the main entrance. Open daily 10AM-2AM.",
            timestamp: Date().addingTimeInterval(-900),
            isPinned: false
        ),
        
        // Activities Channel Posts
        Post(
            id: Post.ID(4),
            channelID: Channel.ID(2),
            title: "Silent Disco Tonight!",
            contents: "Join us at the Silent Disco tent from 11PM-3AM. Three different DJs on three different channels. Headphones provided at the entrance!",
            timestamp: Date().addingTimeInterval(-2700),
            isPinned: true
        ),
        Post(
            id: Post.ID(5),
            channelID: Channel.ID(2),
            title: "Yoga at Sunrise",
            contents: "Start your day with community yoga every morning at 7AM in the Wellness Area. Bring your own mat or rent one for $5. All skill levels welcome!",
            timestamp: Date().addingTimeInterval(-7200),
            isPinned: false
        ),
        Post(
            id: Post.ID(6),
            channelID: Channel.ID(2),
            title: "Art Installation Tour",
            contents: "Meet local artists behind our featured installations! Tours start at the main stage every 2 hours from 12PM-6PM. Learn about the stories behind the art.",
            timestamp: Date().addingTimeInterval(-5400),
            isPinned: false
        ),
        
        // Harm Reduction Channel Posts
        Post(
            id: Post.ID(7),
            channelID: Channel.ID(3),
            title: "Know Your Limits",
            contents: "Pace yourself, stay hydrated, and look out for your friends. If you or someone you know needs help, don't hesitate to find security or medical staff.",
            timestamp: Date().addingTimeInterval(-14400),
            isPinned: true
        ),
        Post(
            id: Post.ID(8),
            channelID: Channel.ID(3),
            title: "Free Testing Available",
            contents: "Anonymous substance testing available at the Harm Reduction tent. No questions asked, no judgment. Knowledge is power - stay safe out there.",
            timestamp: Date().addingTimeInterval(-18000),
            isPinned: false
        ),
        Post(
            id: Post.ID(9),
            channelID: Channel.ID(3),
            title: "Medical Tent Locations",
            contents: "Medical stations located at: Main Stage (left side), Food Court (north end), Camping Area (center). Trained EMTs on site 24/7. Emergency: call 911 or find security.",
            timestamp: Date().addingTimeInterval(-21600),
            isPinned: true
        ),
        
        // Food & Vendors Channel Posts
        Post(
            id: Post.ID(10),
            channelID: Channel.ID(4),
            title: "Vendor Marketplace Hours",
            contents: "Explore unique art, clothing, and crafts at our vendor marketplace. Open Friday 4PM-11PM, Saturday & Sunday 10AM-11PM. Support local artists and makers!",
            timestamp: Date().addingTimeInterval(-28800),
            isPinned: false
        ),
        Post(
            id: Post.ID(11),
            channelID: Channel.ID(4),
            title: "Late Night Food Options",
            contents: "Hungry after midnight? Check out Night Owl Tacos and Sunrise Coffee near the camping area. Open until 3AM to keep you fueled for the late shows!",
            timestamp: Date().addingTimeInterval(-32400),
            isPinned: false
        ),
        
        // Transportation Channel Posts
        Post(
            id: Post.ID(12),
            channelID: Channel.ID(5),
            title: "Shuttle Schedule Update",
            contents: "Free shuttles running every 15 minutes between parking lots and main entrance. First shuttle 9AM, last shuttle 1 hour after final act. Track real-time arrivals on the festival app!",
            timestamp: Date().addingTimeInterval(-39600),
            isPinned: false
        ),
        Post(
            id: Post.ID(13),
            channelID: Channel.ID(5),
            title: "Parking Lot C Now Open",
            contents: "Additional parking available in Lot C (overflow). Free shuttle service included. Lot A and B are full. Follow the yellow signs from the main road.",
            timestamp: Date().addingTimeInterval(-46800),
            isPinned: true
        ),
        
        // Sustainability Channel Posts
        Post(
            id: Post.ID(14),
            channelID: Channel.ID(6),
            title: "Zero Waste Challenge",
            contents: "Help us divert 90% of waste from landfills! Use the clearly marked recycling and compost bins throughout the grounds. Reusable cups available for $5 with $2 refill discount.",
            timestamp: Date().addingTimeInterval(-50400),
            isPinned: false
        ),
        Post(
            id: Post.ID(15),
            channelID: Channel.ID(6),
            title: "Water Refill Stations",
            contents: "Free filtered water refill stations located throughout the festival. Bring a reusable bottle to stay hydrated and reduce plastic waste. Map available at info tents.",
            timestamp: Date().addingTimeInterval(-54000),
            isPinned: false
        )
    ]
}


#Preview {
    NavigationStack {
        CommunicationsFeature()
    }
}
