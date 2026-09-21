import Foundation
import simd

struct ScopeConstants {
    // BT.709 chroma on encoded RGB: x = 2 Cb, y = -2 Cr (texture Y points down).
    // Cb = (B - Y') / 1.8556; Cr = (R - Y') / 1.5748.
    static let kr: Float = 0.2126
    static let kg: Float = 0.7152
    static let kb: Float = 0.0722
    static let chromaX = SIMD4<Float>(-kr / (1 - kb), -kg / (1 - kb), 1, 0)
    static let chromaY = SIMD4<Float>(-1, kg / (1 - kr), kb / (1 - kr), 0)

    static func position(for rgb: SIMD3<Float>) -> SIMD2<Float> {
        let color = SIMD4<Float>(rgb, 1)
        return SIMD2(simd_dot(chromaX, color), simd_dot(chromaY, color))
    }

    static let targetLabels = ["R", "MG", "B", "CY", "G", "YL"]
    static let targetColors: [SIMD3<Float>] = [
        SIMD3(1, 0, 0), SIMD3(1, 0, 1), SIMD3(0, 0, 1),
        SIMD3(0, 1, 1), SIMD3(0, 1, 0), SIMD3(1, 1, 0),
    ]
    static let defaultTargets = targetColors.map { position(for: $0 * 0.75) }

    // Illustrative skin reference from reference/vector_scope.py, not a universal target.
    static let skinReference = SIMD3<Float>(0.25, 0.07, 0)
    static let skinPosition = position(for: skinReference)
    static let boxSizeRatio: Float = 0.015

    // Field order and alignment must match GraticuleConfig in ScopeShaders.metal.
    struct MetalConfig {
        var chromaX: SIMD4<Float>
        var chromaY: SIMD4<Float>
        var targetR: SIMD2<Float>
        var targetMG: SIMD2<Float>
        var targetB: SIMD2<Float>
        var targetCY: SIMD2<Float>
        var targetG: SIMD2<Float>
        var targetYL: SIMD2<Float>
        var skinPosition: SIMD2<Float>
        var boxSizeRatio: Float
        var padding: Float = 0
    }

    static func makeMetalConfig() -> MetalConfig {
        let targets = defaultTargets
        return MetalConfig(
            chromaX: chromaX, chromaY: chromaY,
            targetR: targets[0], targetMG: targets[1], targetB: targets[2],
            targetCY: targets[3], targetG: targets[4], targetYL: targets[5],
            skinPosition: skinPosition, boxSizeRatio: boxSizeRatio
        )
    }
}
