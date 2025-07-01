//
//
//
//import Foundation
//import Dependencies
//import Combine
//#if canImport(UIKit)
//import UIKit
//#endif
//// import Sharing
//
//
//import  SwiftUI; import SkipFuse
//#if os(iOS) || os(Android)
//extension InterfaceOrientation {
//    init?(_ orientation: UIInterfaceOrientation) {
//        switch orientation {
//        case .portrait: self = .portrait
//        case .landscapeLeft: self = .landscapeLeft
//        case .landscapeRight: self = .landscapeRight
//        case .portraitUpsideDown: self = .portraitUpsideDown
//        case .unknown: return nil
//        @unknown default: return nil
//        }
//    }
//
//    init?(_ orientation: UIDeviceOrientation) {
//        switch orientation {
//        case .portrait: self = .portrait
//        case .landscapeLeft: self = .landscapeLeft
//        case .landscapeRight: self = .landscapeRight
//        case .portraitUpsideDown: self = .portraitUpsideDown
//        case .unknown: return nil
//        case .faceUp:
//            return nil
//
//        case .faceDown:
//            return nil
//        @unknown default: return nil
//        }
//    }
//
//    var isPortrait: Bool {
//        switch self {
//        case .landscapeLeft, .landscapeRight: return false
//        case .portrait, .portraitUpsideDown: return true
//        default:
//            return false
//        }
//    }
//}
//
//// TODO: Replace with proper orientation tracking implementation
//// struct InterfaceOrientationReaderKey: SharedReaderKey, Hashable {
////     typealias Value = InterfaceOrientation
////
////     public let id = UUID()
////     func load(context: LoadContext<InterfaceOrientation>, continuation: LoadContinuation<InterfaceOrientation>) {
////         Task { @MainActor in
////             continuation.resume(with: .success(InterfaceOrientation(UIDevice.current.orientation)))
////         }
////     }
////
////
////     func subscribe(
////         context: LoadContext<InterfaceOrientation>,
////         subscriber: SharedSubscriber<InterfaceOrientation>
////     ) -> SharedSubscription {
////         let publisher = NotificationCenter
////             .default
////             .publisher(for: UIDevice.orientationDidChangeNotification)
////             .map { _ in Void() }
////
////         Task {
////             for await _ in publisher.values {
////                 // Documentation says that UIDevice.current.orientation is the best way to get this,
////                 // The NotificationCenter notification doesn't have the value
////                 if let value = await InterfaceOrientation(UIDevice.current.orientation) {
////                     subscriber.yield(value)
////                 }
////             }
////         }
////
////         return .init {}
////     }
////
//// }
//
//
//// TODO: Replace with proper orientation tracking implementation
//// extension SharedReaderKey where Self == InterfaceOrientationReaderKey.Default {
////     static var interfaceOrientation: Self {
////         Self[InterfaceOrientationReaderKey(), default: .portrait]
////     }
//// }
//#endif
