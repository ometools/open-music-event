//
//  PreviewLoadTimeDependencyKey.swift
//  Core
//
//  Created by Woodrow Melling on 10/7/25.
//


//
//  File.swift
//  
//
//  Created by Woodrow Melling on 11/8/23.
//

import Foundation
import Dependencies

struct PreviewLoadTimeDependencyKey: DependencyKey {
    static let liveValue: Duration = .seconds(0)
}

extension DependencyValues {
    public var previewLoadTime: Duration {
        get { self[PreviewLoadTimeDependencyKey.self] }
        set { self[PreviewLoadTimeDependencyKey.self] = newValue }
    }
}

//public extension Reducer {
//    func previewLoadingTime(duration: Duration = .seconds(1)) -> some ReducerOf<Self> {
//        self.dependency(\.previewLoadTime, duration)
//    }
//}

public func previewLoadingTime() async {
    @Dependency(\.previewLoadTime) var previewLoadTime
    try? await Task.sleep(for: previewLoadTime)
}
