//
//  Navigation+Bindings.swift
//  open-music-event
//
//  Created by Woodrow Melling on 11/28/25.
//

import IssueReporting
import SwiftUI
import SkipFuse

extension View {
    public func navigationDestination<D, C: View>(
        item: Binding<D?>,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> some View {
        navigationDestination(isPresented: Binding(item)) {
            if let item = item.wrappedValue {
                destination(item)
            }
        }
    }
}

extension Binding {
    /// Creates a binding by projecting the base optional value to a Boolean value.
    ///
    /// Writing `false` to the binding will `nil` out the base value. Writing `true` produces a
    /// runtime warning.
    ///
    /// - Parameter base: A value to project to a Boolean value.
    public init<V>(
        _ base: Binding<V?>,
    ) where Value == Bool {
        self =
        base[]
    }
}

extension Optional {
    fileprivate subscript() -> Bool {
        get { self != nil }
        set {
            if newValue {
                reportIssue(
            """
            Boolean presentation binding attempted to write 'true' to a generic 'Binding<Item?>' \
            (i.e., 'Binding<\(Wrapped.self)?>').
            
            This is not a valid thing to do, as there is no way to convert 'true' to a new \
            instance of '\(Wrapped.self)'.
            """
                )
            } else {
                self = nil
            }
        }
    }
}


import CasePaths

extension Binding where Value: Sendable {
    public subscript<Case>(dynamicMember keyPath: CaseKeyPath<Value, Case>) -> Binding<Case>?
    where Value: CasePathable {
        #if os(Android)
        Binding<Case>(
            Binding<Case?>(
                get: { self.wrappedValue[case: keyPath] },
                set: { newValue in
                    guard let newValue else { return }
                    self.wrappedValue[case: keyPath] = newValue
                }
            )
        )
        #else
        Binding<Case>(
            Binding<Case?>(
                get: { self.wrappedValue[case: keyPath] },
                set: { newValue, transaction in
                    guard let newValue else { return }
                    self.transaction(transaction).wrappedValue[case: keyPath] = newValue
                }
            )
        )
        #endif
    }
}



/**
 https://github.com/pointfreeco/swiftui-navigation/blob/main/Sources/SwiftUINavigation/Binding.swift

 Grabbed from here to enable enum Destination Navigation
 */

#if canImport(SwiftUI)
import CasePaths
import SwiftUI

extension Binding {
#if swift(>=5.9)
    /// Returns a binding to the associated value of a given case key path.
    ///
    /// Useful for producing bindings to values held in enum state.
    ///
    /// - Parameter keyPath: A case key path to a specific associated value.
    /// - Returns: A new binding.
    public subscript<Member>(
        dynamicMember keyPath: KeyPath<Value.AllCasePaths, AnyCasePath<Value, Member>>
    ) -> Binding<Member>?
    where Value: CasePathable {
        Binding<Member>(unwrapping: self[keyPath])
    }

    /// Returns a binding to the associated value of a given case key path.
    ///
    /// Useful for driving navigation off an optional enumeration of destinations.
    ///
    /// - Parameter keyPath: A case key path to a specific associated value.
    /// - Returns: A new binding.
    public subscript<Enum: CasePathable, Member>(
        dynamicMember keyPath: KeyPath<Enum.AllCasePaths, AnyCasePath<Enum, Member>>
    ) -> Binding<Member?>
    where Value == Enum? {
        self[keyPath]
    }
#endif

    /// Creates a binding by projecting the base value to an unwrapped value.
    ///
    /// Useful for producing non-optional bindings from optional ones.
    ///
    /// See ``IfLet`` for a view builder-friendly version of this initializer.
    ///
    /// > Note: SwiftUI comes with an equivalent failable initializer, `Binding.init(_:)`, but using
    /// > it can lead to crashes at runtime. [Feedback][FB8367784] has been filed, but in the meantime
    /// > this initializer exists as a workaround.
    ///
    /// [FB8367784]: https://gist.github.com/stephencelis/3a232a1b718bab0ae1127ebd5fcf6f97
    ///
    /// - Parameter base: A value to project to an unwrapped value.
    /// - Returns: A new binding or `nil` when `base` is `nil`.
    public init?(unwrapping base: Binding<Value?>) {
        guard let value = base.wrappedValue else { return nil }
        self.init(unwrapping: base, default: value)
    }

    public init(unwrapping base: Binding<Value?>, default value: Value) {
        self = base[default: DefaultSubscript(value)]
    }

}

extension Optional {
    fileprivate subscript(default defaultSubscript: DefaultSubscript<Wrapped>) -> Wrapped {
        get {
            defaultSubscript.value = self ?? defaultSubscript.value
            return defaultSubscript.value
        }
        set {
            defaultSubscript.value = newValue
            if self != nil { self = newValue }
        }
    }
}

private final class DefaultSubscript<Value>: Hashable {
    var value: Value
    init(_ value: Value) {
        self.value = value
    }
    static func == (lhs: DefaultSubscript, rhs: DefaultSubscript) -> Bool {
        lhs === rhs
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

extension CasePathable {
    fileprivate subscript<Member>(
        keyPath: KeyPath<Self.AllCasePaths, AnyCasePath<Self, Member>>
    ) -> Member? {
        get {
            Self.allCasePaths[keyPath: keyPath].extract(from: self)
        }
        set {
            guard let newValue else { return }
            self = Self.allCasePaths[keyPath: keyPath].embed(newValue)
        }
    }
}

extension Optional where Wrapped: CasePathable {
    fileprivate subscript<Member>(
        keyPath: KeyPath<Wrapped.AllCasePaths, AnyCasePath<Wrapped, Member>>
    ) -> Member? {
        get {
            self.flatMap(Wrapped.allCasePaths[keyPath: keyPath].extract(from:))
        }
        set {
            let casePath = Wrapped.allCasePaths[keyPath: keyPath]
            guard self.flatMap(casePath.extract(from:)) != nil
            else { return }
            self = newValue.map(casePath.embed)
        }
    }
}
#endif  // canImport(SwiftUI)
