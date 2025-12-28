import Foundation
import simd

struct ScopeConstants {
    // Polar Coordinate Helper
    struct Polar {
        var mag: Float
        var angleDeg: Float
        
        func toCartesian() -> SIMD2<Float> {
            let rad = angleDeg * .pi / 180.0
            return SIMD2<Float>(mag * cos(rad), mag * -sin(rad)) // Y is up-negative in our shader logic?
            // Wait, previous values: R(-0.147, -0.615).
            // Mag ~ 0.63. 
            // Angle? atan2(-0.615, -0.147) -> -103 deg (or 256 deg).
            // cos(256) = -0.24? No.
            // Let's verify standard math.
            // if we use standard cos, sin:
            // x = mag * cos(theta), y = mag * sin(theta).
            // R: x=-0.147, y=-0.615.
            // The shader logic for y was `norm_y = -(ry / 1.14)`.
            // In the overlay, we inverted Y again for Cocoa.
            // The User wants "Angle". Standard Angle usually 0 is Right (Blue axis roughly?), 90 is Up.
            // In our `clear_vector`: 
            // `float2 skin_dir = float2(cos(angle), -sin(angle))`
            // This implies: Positive Angle -> (cos, -sin).
            // x = cos, y = -sin.
            // If angle=90, x=0, y=-1. (Top in metal texture).
            // So this system means Angle increases Counter-Clockwise from Right.
            // 0 -> Right. 90 -> Up (Top). 180 -> Left. 270 -> Down.
            
            // Let's convert existing (x, y) to this system to preserve exact positions.
            // R: (-0.147, -0.615).
            // x = -0.147, y = -0.615.
            // y = -sin(angle) * mag => sin(angle) = 0.615/mag. Positive sin -> Upper half.
            // x = cos(angle) * mag => cos(angle) = -0.147/mag. Negative cos -> Left.
            // Quad II. (90..180).
            // Angle should be ~103 degrees.
            // Let's check: 
            // Mag = 0.632.
            // -0.632 * cos(103.5) = -0.632 * -0.233 = 0.147? (Wait cos(103) is negative).
            // 0.632 * cos(103.5) = 0.632 * -0.23 = -0.145. (Close).
            // -0.632 * sin(103.5) = -0.632 * 0.97 = -0.613. (Close).
            // So: x = mag * cos(angle), y = -mag * sin(angle).
            // This matches the shader logic `skin_dir = float2(cos, -sin)`.
            
            return SIMD2<Float>(mag * cos(rad), -mag * sin(rad))
        }
    }

    // Target Coordinates (Polar Format <Magnitude, AngleDegrees>)
    // Magnitudes based on Rec. 601 75% Color Bars (Ref: 0.474, 0.443, 0.336)
    // Angles calculated via atan2(-y, x) to map to our shader coordinate system
    static let polarTargets: [Polar] = [
        Polar(mag: 0.474, angleDeg: 103.5), // R
        Polar(mag: 0.443, angleDeg: 60.7),  // MG
        Polar(mag: 0.336, angleDeg: 347.1), // B
        Polar(mag: 0.474, angleDeg: 283.5), // CY
        Polar(mag: 0.443, angleDeg: 240.7), // G
        Polar(mag: 0.336, angleDeg: 167.1)  // YL
    ]
    
    static var defaultTargets: [SIMD2<Float>] {
        return polarTargets.map { $0.toCartesian() }
    }
    
    // Labels corresponding to above
    static let targetLabels = ["R", "MG", "B", "CY", "G", "YL"]

    // Skin Tone Settings
    static let skinAngle: Float = 123.0 // Degrees
    static let skinSaturation: Float = 0.25
    
    // Visual Settings
    static let boxSizeRatio: Float = 0.015 // Relative to scope width
    
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
