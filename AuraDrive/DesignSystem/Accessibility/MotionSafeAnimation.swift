import SwiftUI

extension View {
    /// Applies `animation` only when the user has not turned on Reduce Motion.
    func motionSafeAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(MotionSafeAnimation(animation: animation, value: value))
    }
}

private struct MotionSafeAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
