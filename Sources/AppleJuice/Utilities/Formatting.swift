import Foundation

/// Pad a string to a fixed width, left-aligned or right-aligned.
func pad(_ s: String, _ width: Int, left: Bool = false) -> String {
    left ? s.padding(toLength: width, withPad: " ", startingAt: 0)
         : String(repeating: " ", count: max(0, width - s.count)) + s
}
