//
//  File.swift
//
//
//  Created by Woody on 2/10/22.
//

import Foundation

public extension TimeInterval {
    var seconds: TimeInterval {
        self
    }

    var minutes: TimeInterval {
        seconds * 60
    }

    var hours: TimeInterval {
        minutes * 60
    }

    var days: TimeInterval {
        hours * 24
    }

    var years: TimeInterval {
        days * 365
    }
}

public extension Int {
    var seconds: TimeInterval {
        TimeInterval(self)
    }

    var minutes: TimeInterval {
        seconds * 60
    }

    var hours: TimeInterval {
        minutes * 60
    }

    var days: TimeInterval {
        hours * 24
    }

    var years: TimeInterval {
        days * 365
    }
}
