//
//  Testival.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/3/25.
//
import Foundation

public extension Organizer {
    static let wickedWoods = Organizer(
        id: "wicked-woods",
        url: URL(string: "https://github.com/wicked-woods/wicked-woods-ome/archive/refs/heads/main.zip")!,
        name: "Wicked Woods",
        imageURL: URL(string: "https://images.squarespace-cdn.com/content/v1/66eb917b86dbd460ad209478/5be5a6e6-c5ca-4271-acc3-55767c498061/WW-off_white.png?format=1500w")
    )

    static let shambhala = Organizer(
        id: "shambhala",
        url: URL(string: "https://github.com/woodymelling/shambhala-ome/archive/refs/heads/main.zip")!,
        name: "Shambhala Music Festival",
        iconImageURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/festivl.appspot.com/o/userContent%2Flogo_small.png?alt=media&token=7766fa90-6591-4e25-92b4-2ff354cb970d")
    )

    static let omeTools = Organizer(
        id: "ometools",
        url: URL(string: "https://github.com/ometools/test-ome-config/archive/refs/heads/main.zip")!,
        name: "Open Music Event",
        iconImageURL: nil
    )
}

public extension MusicEvent {
    static let placeholder = MusicEvent(
        id: "placeholder",
        organizerID: .init(""),
        name: "",
        timeZone: .current,
        startTime: nil,
        endTime: nil,
        imageURL: nil,
        iconImageURL: nil,
        siteMapImageURL: nil,
        location: nil,
        contactNumbers: []
    )
}

public extension MusicEvent {
    static let testival = MusicEvent(
        id: "testival-1",
        organizerID: Organizer.omeTools.id,
        name: "Testival",
        timeZone: .current,
        imageURL: nil,
        iconImageURL: nil,
        siteMapImageURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/festivl.appspot.com/o/userContent%2FSite%20Map.webp?alt=media&token=48272d3c-ace0-4d5b-96a9-a5142f1c744a"),
        location: Location(
            address: "3901 Kootenay Hwy, Fairmont Hot Springs, BC V0B 1L1, Canada",
            directions: "Get back on San Vincente, take it to the 10, then switch over to the 405 north, and let it dump you onto Mullholland where you belong!",
            coordinates: .init(latitude: 50.366265, longitude: -115.871286)
            ),
        contactNumbers: [
            .init(
                phoneNumber: "5555551234",
                title: "Emergency Services",
                description: "This will connect you directly with our switchboard, and alert the appropriate services."
            ),
            .init(
                phoneNumber: "5555554321",
                title: "General Information Line",
                description: "For general information, questions or concerns, or to report any sanitation issues within the WW grounds, please contact this number."
            )
        ]
    )
}

public extension Artist {
    static let previewValues: [Artist] = [
        Artist(
            id: Artist.ID("cantos"),
            musicEventID: .init("testival-1"),
            name: "Cantos",
            bio: "**Cantos** is an electronic music producer and DJ who fuses a sense of otherworldly mysticism with cutting-edge sonic craft. Exploring everything from deep and funky house to techno, drum & bass, and garage, Cantos delivers powerful, underground sets rooted in soundsystem culture. High production quality and immersive, dancefloor-focused energy define each performance, creating unforgettable experiences that meld the ancient and the futuristic into a single, pulsing groove.",
            imageURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/festivl.appspot.com/o/userContent%2FIMG_9907_Original.png?alt=media&token=3c2c0140-a28a-40bc-9f50-f77954b2294d"),
            logoURL: nil,
            kind: "DJ",
            links: [
                Artist.Link(url: URL(string: "https://soundcloud.com/cantos_music")!),
                Artist.Link(url: URL(string: "https://www.instagram.com/cantos/")!)
            ]
        ),
        Artist(
            id: Artist.ID("boids"),
            musicEventID: .init("testival-1"),
            name: "Boids",
            bio: "**Boids** is an experimental electronic music project blending elements of technology, nature, math, and art. Drawing inspiration from the complex patterns of flocking behavior, boids creates immersive soundscapes that evolve through algorithmic structures and organic, flowing rhythms. With a foundation in house music, the project explores new auditory dimensions while maintaining a connection to the dance floor, inviting listeners to explore both the natural world and the mathematical systems that underpin it.",
            imageURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/festivl.appspot.com/o/userContent%2FSubsonic.webp?alt=media&token=8b732938-f9c7-4216-8fb5-3ff4acad9384"),
            logoURL: nil,
            kind: "Live Act",
            links: []
        ),
        Artist(
            id: Artist.ID("phantom-groove"),
            musicEventID: .init("testival-1"),
            name: "Phantom Groove",
            bio: nil,
            imageURL: nil,
            logoURL: nil,
            kind: "DJ",
            links: []
        ),
        Artist(
            id: Artist.ID("sunspear"),
            musicEventID: .init("testival-1"),
            name: "Sunspear",
            bio: nil,
            imageURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/festivl.appspot.com/o/userContent%2FSunspear-image.webp?alt=media&token=be30f499-8356-41a9-9425-7e19e36e2ea9")!,
            logoURL: nil,
            kind: "Band",
            links: []
        ),
        Artist(
            id: Artist.ID("rhythmbox"),
            musicEventID: .init("testival-1"),
            name: "Rhythmbox",
            bio: nil,
            imageURL: nil,
            logoURL: nil,
            kind: "DJ",
            links: []
        ),
        Artist(
            id: Artist.ID("prism-sound"),
            musicEventID: .init("testival-1"),
            name: "Prism Sound",
            bio: nil,
            imageURL: nil,
            logoURL: nil,
            kind: "Live Act",
            links: []
        ),
        Artist(
            id: Artist.ID("oaktrail"),
            musicEventID: .init("testival-1"),
            name: "Oaktrail",
            bio: nil,
            imageURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/festivl.appspot.com/o/userContent%2FOaktrail.webp?alt=media&token=db962b24-e144-476c-ac4c-71ffa7f7f32d"),
            logoURL: nil,
            kind: "DJ",
            links: []
        ),
        Artist(
            id: Artist.ID("space-chunk"),
            musicEventID: .init("testival-1"),
            name: "Space Chunk",
            bio: nil,
            imageURL: URL(string: "https://i1.sndcdn.com/avatars-oI73KB5SpEOGCmFq-5ezWjw-t500x500.jpg")!,
            logoURL: nil,
            kind: "Producer",
            links: [
                .init(url: URL(string: "https://soundcloud.com/spacechunk")!, type: .soundcloud)
            ]
        ),
        Artist(
            id: Artist.ID("the-sleepies"),
            musicEventID: .init("testival-1"),
            name: "The Sleepies",
            bio: nil,
            imageURL: nil,
            logoURL: nil,
            kind: "Band",
            links: []
        ),
        Artist(
            id: Artist.ID("sylvan-beats"),
            musicEventID: .init("testival-1"),
            name: "Sylvan Beats",
            bio: nil,
            imageURL: nil,
            logoURL: nil,
            kind: "DJ",
            links: []
        ),
        Artist(
            id: Artist.ID("overgrowth"),
            musicEventID: .init("testival-1"),
            name: "Overgrowth",
            bio: nil,
            imageURL: URL(string: "https://firebasestorage.googleapis.com/v0/b/festivl.appspot.com/o/userContent%2FOvergrowth%20DJ%20Profile.webp?alt=media&token=f0856acd-ab9c-47bf-b1d8-d7e385048beb"),
            logoURL: nil,
            kind: "DJ",
            links: [
                .init(url: URL(string: "https://soundcloud.com/overgrowthmusic")!, type: .soundcloud)
            ]
        ),
    ]
}

public extension Stage {
    static let previewValues: [Stage] = [
//        Stage(
//            id: 0,
//            musicEventID: 0,
//            sortIndex: 0,
//            name: "Unicorn Lounge",
//            iconImageURL: URL(string: "https://firebasestorage.googleapis.com:443/v0/b/festivl.appspot.com/o/userContent%2FF0BC110C-D42E-4CC9-BED3-59E2700938FF.png?alt=media&token=472a66e1-c45a-4a67-895a-5ec7e0ad95c0"), color: .red
//
//        ),
//
//        Stage(
//            id: 1,
//            musicEventID: 0,
//            sortIndex: 1,
//            name: "The Hallow",
//            iconImageURL: URL(string: "https://firebasestorage.googleapis.com:443/v0/b/festivl.appspot.com/o/userContent%2FB36D3658-2659-447C-9ECA-21D07C952A88.png?alt=media&token=d328c04d-6c4d-4be7-8368-786ab5262c9a"), color: .green
//        ),
//        Stage(
//            id: 2,
//            musicEventID: 0,
//            sortIndex: 2,
//            name: "Ursus",
//            iconImageURL: URL(string: "https://firebasestorage.googleapis.com:443/v0/b/festivl.appspot.com/o/userContent%2F274838AC-2BDA-40A0-8FD4-78E9FFC86D6B.png?alt=media&token=b28cc74f-b60d-4472-a31b-900a4f5bfbd8"), color: .blue
//        ),
//        Stage(
//            id: 3,
//            musicEventID: 0,
//            sortIndex: 3,
//            name: "The Portal",
//            iconImageURL: URL(string: "https://firebasestorage.googleapis.com:443/v0/b/festivl.appspot.com/o/userContent%2F8BD98000-C41A-4360-8106-9AD98BF1AD71.png?alt=media&token=a0df8893-0cc7-4442-8921-d6c4e066569c"), color: .purple
//        )
    ]
}
//public extension Stage {
//    static let previewValues: [Stage] = [
//        Stage(
//            id: 0,
//            musicEventID: 0,
//            name: "Unicorn Lounge",
//            iconImageURL: URL(string: "https://firebasestorage.googleapis.com:443/v0/b/festivl.appspot.com/o/userContent%2FF0BC110C-D42E-4CC9-BED3-59E2700938FF.png?alt=media&token=472a66e1-c45a-4a67-895a-5ec7e0ad95c0"), color: .red
//        ),
//
//        Stage(
//            id: 1,
//            musicEventID: 0,
//            name: "The Hallow",
//            iconImageURL: URL(string: "https://firebasestorage.googleapis.com:443/v0/b/festivl.appspot.com/o/userContent%2FB36D3658-2659-447C-9ECA-21D07C952A88.png?alt=media&token=d328c04d-6c4d-4be7-8368-786ab5262c9a"), color: .green
//        ),
//        Stage(
//            id: 2,
//            musicEventID: 0,
//            name: "Ursus",
//            iconImageURL: URL(string: "https://firebasestorage.googleapis.com:443/v0/b/festivl.appspot.com/o/userContent%2F274838AC-2BDA-40A0-8FD4-78E9FFC86D6B.png?alt=media&token=b28cc74f-b60d-4472-a31b-900a4f5bfbd8"), color: .blue
//        ),
//        Stage(
//            id: 3,
//            musicEventID: 0,
//            name: "The Portal",
//            iconImageURL: URL(string: "https://firebasestorage.googleapis.com:443/v0/b/festivl.appspot.com/o/userContent%2F8BD98000-C41A-4360-8106-9AD98BF1AD71.png?alt=media&token=a0df8893-0cc7-4442-8921-d6c4e066569c"), color: .purple
//        )
//    ]
//}

public extension CommunicationChannel {
    static let previewData: [CommunicationChannel.Draft] = [
        .init(
            id: CommunicationChannel.ID("general"),
            musicEventID: MusicEvent.ID("testival-1"),
            name: "General",
            description: "General festival announcements and updates",
            sortIndex: 1
        ),
        .init(
            id: CommunicationChannel.ID("activities"),
            musicEventID: MusicEvent.ID("testival-1"),
            name: "Activities",
            description: "Special activities, workshops, and experiences",
            sortIndex: 2
        ),
        .init(
            id: CommunicationChannel.ID("harm-reduction"),
            musicEventID: MusicEvent.ID("testival-1"),
            name: "Harm Reduction",
            description: "Safety information and harm reduction resources",
            sortIndex: 3
        ),
        .init(
            id: CommunicationChannel.ID("food-vendors"),
            musicEventID: MusicEvent.ID("testival-1"),
            name: "Food & Vendors",
            description: "Information about food options and marketplace vendors",
            sortIndex: 4
        ),
        .init(
            id: CommunicationChannel.ID("transportation"),
            musicEventID: MusicEvent.ID("testival-1"),
            name: "Transportation",
            description: "Parking, shuttles, and transportation updates",
            sortIndex: 5
        ),
        .init(
            id: CommunicationChannel.ID("sustainability"),
            musicEventID: MusicEvent.ID("testival-1"),
            name: "Sustainability",
            description: "Environmental initiatives and green practices",
            sortIndex: 6
        )
    ]
}

public extension CommunicationChannel.Post {
    static let previewData: [CommunicationChannel.Post.Draft] = [
        // General Channel Posts
        .init(
            id: CommunicationChannel.Post.ID("welcome-post"),
            channelID: CommunicationChannel.ID("general"),
            title: "Welcome to Festival 2025!",
            contents: "We're excited to have you join us for an incredible weekend of music, art, and community. Check your schedule, stay hydrated, and have an amazing time!",
            timestamp: Date().addingTimeInterval(-3600),
            isPinned: true
        ),
        .init(
            id: CommunicationChannel.Post.ID("weather-update"),
            channelID: CommunicationChannel.ID("general"),
            title: "Weather Update",
            contents: "Sunny skies expected all weekend with temperatures reaching 75°F. Perfect festival weather! Don't forget sunscreen and bring a light jacket for evening shows.",
            timestamp: Date().addingTimeInterval(-1800),
            isPinned: false
        ),
        .init(
            id: CommunicationChannel.Post.ID("lost-found"),
            channelID: CommunicationChannel.ID("general"),
            title: "Lost & Found Location",
            contents: "Lost something? Our Lost & Found is located at the Information Tent near the main entrance. Open daily 10AM-2AM.",
            timestamp: Date().addingTimeInterval(-900),
            isPinned: false
        ),
        
        // Activities Channel Posts
        .init(
            id: CommunicationChannel.Post.ID("silent-disco"),
            channelID: CommunicationChannel.ID("activities"),
            title: "Silent Disco Tonight!",
            contents: "Join us at the Silent Disco tent from 11PM-3AM. Three different DJs on three different channels. Headphones provided at the entrance!",
            timestamp: Date().addingTimeInterval(-2700),
            isPinned: true
        ),
        .init(
            id: CommunicationChannel.Post.ID("yoga-sunrise"),
            channelID: CommunicationChannel.ID("activities"),
            title: "Yoga at Sunrise",
            contents: "Start your day with community yoga every morning at 7AM in the Wellness Area. Bring your own mat or rent one for $5. All skill levels welcome!",
            timestamp: Date().addingTimeInterval(-7200),
            isPinned: false
        ),
        .init(
            id: CommunicationChannel.Post.ID("art-tour"),
            channelID: CommunicationChannel.ID("activities"),
            title: "Art Installation Tour",
            contents: "Meet local artists behind our featured installations! Tours start at the main stage every 2 hours from 12PM-6PM. Learn about the stories behind the art.",
            timestamp: Date().addingTimeInterval(-5400),
            isPinned: false
        ),
        
        // Harm Reduction Channel Posts
        .init(
            id: CommunicationChannel.Post.ID("know-limits"),
            channelID: CommunicationChannel.ID("harm-reduction"),
            title: "Know Your Limits",
            contents: "Pace yourself, stay hydrated, and look out for your friends. If you or someone you know needs help, don't hesitate to find security or medical staff.",
            timestamp: Date().addingTimeInterval(-14400),
            isPinned: true
        ),
        .init(
            id: CommunicationChannel.Post.ID("free-testing"),
            channelID: CommunicationChannel.ID("harm-reduction"),
            title: "Free Testing Available",
            contents: "Anonymous substance testing available at the Harm Reduction tent. No questions asked, no judgment. Knowledge is power - stay safe out there.",
            timestamp: Date().addingTimeInterval(-18000),
            isPinned: false
        ),
        .init(
            id: CommunicationChannel.Post.ID("medical-tents"),
            channelID: CommunicationChannel.ID("harm-reduction"),
            title: "Medical Tent Locations",
            contents: "Medical stations located at: Main Stage (left side), Food Court (north end), Camping Area (center). Trained EMTs on site 24/7. Emergency: call 911 or find security.",
            timestamp: Date().addingTimeInterval(-21600),
            isPinned: true
        ),
        
        // Food & Vendors Channel Posts
        .init(
            id: CommunicationChannel.Post.ID("vendor-hours"),
            channelID: CommunicationChannel.ID("food-vendors"),
            title: "Vendor Marketplace Hours",
            contents: "Explore unique art, clothing, and crafts at our vendor marketplace. Open Friday 4PM-11PM, Saturday & Sunday 10AM-11PM. Support local artists and makers!",
            timestamp: Date().addingTimeInterval(-28800),
            isPinned: false
        ),
        .init(
            id: CommunicationChannel.Post.ID("late-night-food"),
            channelID: CommunicationChannel.ID("food-vendors"),
            title: "Late Night Food Options",
            contents: "Hungry after midnight? Check out Night Owl Tacos and Sunrise Coffee near the camping area. Open until 3AM to keep you fueled for the late shows!",
            timestamp: Date().addingTimeInterval(-32400),
            isPinned: false
        ),
        
        // Transportation Channel Posts
        .init(
            id: CommunicationChannel.Post.ID("shuttle-schedule"),
            channelID: CommunicationChannel.ID("transportation"),
            title: "Shuttle Schedule Update",
            contents: "Free shuttles running every 15 minutes between parking lots and main entrance. First shuttle 9AM, last shuttle 1 hour after final act. Track real-time arrivals on the festival app!",
            timestamp: Date().addingTimeInterval(-39600),
            isPinned: false
        ),
        .init(
            id: CommunicationChannel.Post.ID("parking-lot-c"),
            channelID: CommunicationChannel.ID("transportation"),
            title: "Parking Lot C Now Open",
            contents: "Additional parking available in Lot C (overflow). Free shuttle service included. Lot A and B are full. Follow the yellow signs from the main road.",
            timestamp: Date().addingTimeInterval(-46800),
            isPinned: true
        ),
        
        // Sustainability Channel Posts
        .init(
            id: CommunicationChannel.Post.ID("zero-waste"),
            channelID: CommunicationChannel.ID("sustainability"),
            title: "Zero Waste Challenge",
            contents: "Help us divert 90% of waste from landfills! Use the clearly marked recycling and compost bins throughout the grounds. Reusable cups available for $5 with $2 refill discount.",
            timestamp: Date().addingTimeInterval(-50400),
            isPinned: false
        ),
        .init(
            id: CommunicationChannel.Post.ID("water-refill"),
            channelID: CommunicationChannel.ID("sustainability"),
            title: "Water Refill Stations",
            contents: "Free filtered water refill stations located throughout the festival. Bring a reusable bottle to stay hydrated and reduce plastic waste. Map available at info tents.",
            timestamp: Date().addingTimeInterval(-54000),
            isPinned: false
        )
    ]
}
