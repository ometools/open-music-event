#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI

public typealias ScheduleCGFloat = SkipSwiftUI.CGFloat
public typealias ScheduleCGPoint = SkipSwiftUI.CGPoint
public typealias ScheduleCGSize = SkipSwiftUI.CGSize
public typealias ScheduleCGRect = SkipSwiftUI.CGRect
#else
import CoreGraphics

public typealias ScheduleCGFloat = CoreGraphics.CGFloat
public typealias ScheduleCGPoint = CoreGraphics.CGPoint
public typealias ScheduleCGSize = CoreGraphics.CGSize
public typealias ScheduleCGRect = CoreGraphics.CGRect
#endif
