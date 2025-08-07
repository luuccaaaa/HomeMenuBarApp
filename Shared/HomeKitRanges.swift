import Foundation
import CoreGraphics

public enum HomeKitRanges {
    public static let brightness: ClosedRange<CGFloat> = 1.0...100.0       // percentage
    public static let temperature: ClosedRange<CGFloat> = 50.0...400.0      // mireds
    public static let hueDegrees: ClosedRange<CGFloat> = 0.0...360.0        // degrees
    public static let saturation: ClosedRange<CGFloat> = 0.0...100.0        // percentage

    @inlinable public static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
