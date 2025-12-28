import Foundation
import simd

struct ScopeConstants {
    // Polar Coordinate Helper
    struct Polar {
        var mag: Float
        var angleDeg: Float

        func toCartesian() -> SIMD2<Float> {
            let rad = angleDeg * .pi / 180.0
            return SIMD2<Float>(mag * cos(rad), -mag * sin(rad))
        }
    }

    // Target Coordinates (Polar Format <Magnitude, AngleDegrees>)
    // Magnitudes based on Rec. 601 75% Color Bars (Ref: 0.474, 0.443, 0.336)
    // Angles calculated via atan2(-y, x) to map to our shader coordinate system
    static let polarTargets: [Polar] = [
        Polar(mag: 0.474, angleDeg: 103.5),  // R
        Polar(mag: 0.443, angleDeg: 60.7),  // MG
        Polar(mag: 0.336, angleDeg: 347.1),  // B
        Polar(mag: 0.474, angleDeg: 283.5),  // CY
        Polar(mag: 0.443, angleDeg: 240.7),  // G
        Polar(mag: 0.336, angleDeg: 167.1),  // YL
    ]

    static var defaultTargets: [SIMD2<Float>] {
        return polarTargets.map { $0.toCartesian() }
    }

    // Labels corresponding to above
    static let targetLabels = ["R", "MG", "B", "CY", "G", "YL"]

    // Skin Tone Settings
    static let skinAngle: Float = 123.0  // Degrees
    static let skinSaturation: Float = 0.25

    // Visual Settings
    static let boxSizeRatio: Float = 0.015  // Relative to scope width

    // Metal Buffer Struct Representation
    struct MetalConfig {
        var targetR: SIMD2<Float>
        var targetMG: SIMD2<Float>
        var targetB: SIMD2<Float>
        var targetCY: SIMD2<Float>
        var targetG: SIMD2<Float>
        var targetYL: SIMD2<Float>

        var skinAngle: Float
        var skinSat: Float
        var boxSizeRatio: Float
        var padding: Float = 0
    }

    static func makeMetalConfig() -> MetalConfig {
        let t = defaultTargets
        return MetalConfig(
            targetR: t[0],
            targetMG: t[1],
            targetB: t[2],
            targetCY: t[3],
            targetG: t[4],
            targetYL: t[5],
            skinAngle: skinAngle,
            skinSat: skinSaturation,
            boxSizeRatio: boxSizeRatio
        )
    }
}
