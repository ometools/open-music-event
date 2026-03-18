import SwiftUI
import Sharing
import SkipFuse


/// Bridges @Shared to Compose recomposition on Android
///
/// The @Shared property wrapper from swift-sharing has its own observation system
/// via Combine publishers, which doesn't automatically trigger Compose recomposition.
/// This bridge wraps a @Shared value and uses SkipFuse's @Observable to ensure
/// that when the shared value changes, Android views are properly recomposed.
///
/// Example usage:
/// ```swift
/// @State private var meetingsBridge = SharedObservationBridge(
///     Shared(wrappedValue: [], .fileStorage(.meetings))
/// )
///
/// var body: some View {
///     List(meetingsBridge.wrappedValue) { meeting in
///         Text(meeting.title)
///     }
/// }
/// ```
@Observable
@MainActor // Not sure how to increment ID  in a sendable closure outside of marking this mainActor.
@dynamicMemberLookup
@propertyWrapper
final class SharedShim<Value> {

    // This property uses SkipFuse's Observation wrapper on Android.
    // Changes to it trigger Compose recomposition via JNI calls to MutableStateBacking.
    var id: Int = 0
    let shared: Shared<Value>
    var task: Task<Void, Never>? = nil

    init(_ shared: Shared<Value>) {
        self.shared = shared
        #if os(Android)
        self.task = Task {
            for await _ in Observations ({ shared.projectedValue }) {
                self.id += 1
            }
        }
        #endif
    }

    public convenience init(
        wrappedValue: @autoclosure () -> Value,
        _ key: some SharedKey<Value>
    ) {
        self.init(Shared(wrappedValue: wrappedValue(), key))
    }

    var wrappedValue: Value {
        // When accessing a wrappedValue, we must touch the id here so that the view triggers a recomp.
        _ = id
        return shared.wrappedValue
    }

    fileprivate var _wrappedValue: Value {
        get {
            self.wrappedValue
        }
        set { shared.withLock { $0 = newValue } }
    }

    public var projectedValue: SharedShim<Value> {
      self
    }
//
//    var projectedValue: Shared<Value> {
//        shared.projectedValue
//    }


    public subscript<Member>(
      dynamicMember keyPath: WritableKeyPath<Value, Member>
    ) -> Shared<Member> {
        shared[dynamicMember: keyPath]
    }

//
//    isolated deinit {
//        self.task?.cancel()
//    }
    
}



//extension Binding {
//    @MainActor
//    /*public*/ init(_ base: SharedShim<Value>) {
//
//    }
//}
extension Binding {
    /// Creates a binding from a shared reference.
    ///
    /// Useful for binding shared state to a SwiftUI control.
    ///
    /// ```swift
    /// @Shared var count: Int
    /// // ...
    /// Stepper("\(count)", value: Binding($count))
    /// ```
    ///
    /// - Parameter base: A shared reference to a value.
    @MainActor
    /*public*/ init(_ base: SharedShim<Value>) {
        @Bindable var reference = base
//        $reference._wrappedValue as! Binding<Value>


        self = $reference._wrappedValue
    }
}



extension SharedShim {
    /// Creates a shared reference to a value using a shared key.
    ///
    /// - Parameters:
    ///   - wrappedValue: A default value that is used when no value can be returned from the
    ///     shared key.
    ///   - key: A shared key associated with the shared reference. It is responsible for loading
    ///     and saving the shared reference's value from some external source.

}

  /// Creates a sh
/// Property wrapper that automatically bridges @Shared to Compose recomposition
///
/// This provides a cleaner API that works like @Shared but ensures Android
/// Compose views update properly when the value changes.
///
/// Example usage:
/// ```swift
/// struct MyView: View {
///     @AndroidShared(.fileStorage(.meetings)) var meetings: [Meeting]
///
///     var body: some View {
///         List(meetings) { meeting in
///             Text(meeting.title)
///         }
///         Button("Add") {
///             meetings.append(Meeting(title: "New"))
///         }
///     }
/// }
/// ```
//@propertyWrapper
//struct AndroidShared<Value>: DynamicProperty {
//    private var bridge: SharedObservationBridge<Value>
//
//
//    /// Initialize with a value and sharing strategy
//    init(wrappedValue: Value, _ strategy: some SharingStrategy<Value>) {
//        self.bridge = SharedObservationBridge(Shared(wrappedValue: wrappedValue, strategy))
//    }
//
//    /// Initialize with just a sharing strategy (requires Value to have a default)
//    init(_ strategy: some SharingStrategy<Value>) where Value: _DefaultInitializable {
//        self.bridge = SharedObservationBridge(Shared(strategy))
//    }
//
//    /// Initialize with an existing @Shared instance
//    init(_ shared: Shared<Value>) {
//        self.bridge = SharedObservationBridge(shared)
//    }
//
//    /// Access the current value
//    var wrappedValue: Value {
//        get { bridge.wrappedValue }
//        nonmutating set { bridge.wrappedValue = newValue }
//    }
//
//    /// Access the underlying @Shared for use with $ syntax
//    var projectedValue: Shared<Value> {
//        bridge.projectedValue
//    }
//}
