//
//  CircularAngle.swift
//  SwiftUIPanoramaViewer
//
//  Created by Patrick Kladek on 03.06.25.
//

import Foundation

public struct CircularAngle: Equatable, Comparable, Hashable {

    private var radiansValue: Double

    // MARK: - Properties

    public var degrees: Double {
        get {
            Self.clipDegrees(radiansValue * 180 / .pi)
        }
        set {
            radiansValue = Self.clipDegrees(newValue) * .pi / 180
        }
    }

    public var radians: Double {
        get {
            Self.clipRadians(radiansValue)
        }
        set {
            radiansValue = Self.clipRadians(newValue)
        }
    }

    // MARK: - Lifecycle

    public init(degrees: Double) {
        self.radiansValue = Self.clipDegrees(degrees) * .pi / 180
    }

    public init(radians: Double) {
        self.radiansValue = Self.clipRadians(radians)
    }

    public static func degrees(_ degrees: Double) -> Self {
        .init(degrees: degrees)
    }

    public static func radians(_ radians: Double) -> Self {
        .init(radians: radians)
    }

    public static var zero: Self {
        .init(radians: 0)
    }

    public static var pi: Self {
        .init(radians: .pi)
    }

    public func adding(_ other: Self) -> Self {
        Self(radians: self.radians + other.radians)
    }

    public  func subtracting(_ other: Self) -> Self {
        Self(radians: self.radians - other.radians)
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        lhs.adding(rhs)
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        lhs.subtracting(rhs)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.radiansValue < rhs.radiansValue
    }
}

// MARK: - CustomStringConvertible

extension CircularAngle: CustomStringConvertible {

    public var description: String {
        "\(String(format: "%6.1f°", self.degrees)) (\(String(format: "%5.3f rad", self.radians)))"
    }
}

public extension CircularAngle {

    static func delta(between a: CircularAngle, and b: CircularAngle) -> CircularAngle {
        let diff = abs(a.radians - b.radians)
        let minimal = min(diff, 2 * .pi - diff)
        return CircularAngle(radians: minimal)
    }
}

private extension CircularAngle {
    static func clipDegrees(_ degrees: Double) -> Double {
        let result = degrees.truncatingRemainder(dividingBy: 360)
        return result >= 0 ? result : result + 360
    }

    static func clipRadians(_ radians: Double) -> Double {
        let result = radians.truncatingRemainder(dividingBy: 2 * .pi)
        return result >= 0 ? result : result + 2 * .pi
    }
}
