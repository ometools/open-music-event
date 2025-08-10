//
//  Icons.swift
//  open-music-event
//
//  Created by Woodrow Melling on 8/9/25.
//

import SwiftUI

extension Label where Title == Text, Icon == Image {
    init(_ title: String, image: Image) {
        self.init {
            Text(title)
        } icon: {
            image
        }
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    init(_ title: String, image: Image, action: @escaping () -> Void) {
        self.init(action: action) {
            Label(title, image: image)
        }
    }
}

enum Icons {
    // MARK: - Schedule & Time
    static var calendar: Image { Image(systemName: "calendar") }
    static var clock: Image { Image(systemName: "clock") }
    static var heart: Image { Image(systemName: "heart") }
    static var heartFill: Image { Image(systemName: "heart.fill") }

    // MARK: - People & Artists
    static var person: Image { Image(systemName: "person") }
    static var person3: Image {
        #if os(Android)
        Image("person.3", bundle: .module)
        #else
        Image(systemName: "person.3")
        #endif
    }

    // MARK: - Communication
    static var megaphone: Image {
        #if os(Android)
        Image("megaphone", bundle: .module)
        #else
        Image(systemName: "megaphone")
        #endif
    }
    static var bell: Image { Image(systemName: "bell") }
    static var bellFill: Image { Image(systemName: "bell.fill") }
    static var bellBadge: Image { Image(systemName: "bell.badge") }
    static var bellBadgeSlash: Image { Image(systemName: "bell.badge.slash") }
    static var pin: Image {
        #if os(Android)
        Image("pin", bundle: .module)
        #else
        Image(systemName: "pin")
        #endif
    }

    // MARK: - Location & Navigation
    static var mappin: Image { Image(systemName: "mappin") }
    static var mappinCircle: Image { Image(systemName: "mappin.circle") }
    static var chevronForward: Image { Image(systemName: "chevron.forward") }

    // MARK: - Actions & Controls
    static var ellipsis: Image { Image(systemName: "ellipsis") }
    static var plus: Image { Image(systemName: "plus") }
    static var arrowClockwise: Image { Image(systemName: "arrow.clockwise") }
    static var documentOnDocument: Image { Image(systemName: "document.on.document") }
    static var line3HorizontalDecreaseCircle: Image { Image(systemName: "line.3.horizontal.decrease.circle") }
    static var line3HorizontalDecreaseCircleFill: Image { Image(systemName: "line.3.horizontal.decrease.circle.fill") }

    // MARK: - Contact & Communication
    static var phone: Image { Image(systemName: "phone") }
    static var phoneFill: Image { Image(systemName: "phone.fill") }

    // MARK: - Information & Status
    static var infoCircle: Image { Image(systemName: "info.circle") }
    static var exclamationmarkCircleFill: Image { Image(systemName: "exclamationmark.circle.fill") }
    static var exclamationmarkBubble: Image { Image(systemName: "exclamationmark.bubble") }
    static var plusBubble: Image { Image(systemName: "plus.bubble") }
    static var warning: Image { Image(systemName: "warning") }

    // MARK: - Navigation & Exit
    static var doorLeftHandOpen: Image { Image(systemName: "door.left.hand.open") }

    // MARK: - Activities & Workshops
    static var selfImprovement: Image {
        #if os(Android)
        Image("self.improvement", bundle: Bundle.module)
        #else
        Image(systemName: "figure.mind.and.body")
        #endif
    }

    // MARK: - Custom Assets
    static var github: Image { Image("github", bundle: .module).resizable() }
}
extension Image {

}
