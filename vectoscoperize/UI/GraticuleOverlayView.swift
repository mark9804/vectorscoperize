import Cocoa

class GraticuleOverlayView: NSView {
    
    enum DisplayMode {
        case vectorScope
        case rgbParade
        case split
    }
    
    var displayMode: DisplayMode = .vectorScope {
        didSet {
            needsDisplay = true
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard displayMode == .vectorScope else { return }
        
        let width = bounds.width
        let height = bounds.height
        let radius = min(width, height) * 0.45
        let center = CGPoint(x: width / 2, y: height / 2)
        
        // Coordinates from ScopeConstants
        let targets = [
            (ScopeConstants.targetLabels[0], CGPoint(x: CGFloat(ScopeConstants.defaultTargets[0].x), y: -CGFloat(ScopeConstants.defaultTargets[0].y))), // R
            (ScopeConstants.targetLabels[1], CGPoint(x: CGFloat(ScopeConstants.defaultTargets[1].x), y: -CGFloat(ScopeConstants.defaultTargets[1].y))), // MG
            (ScopeConstants.targetLabels[2], CGPoint(x: CGFloat(ScopeConstants.defaultTargets[2].x), y: -CGFloat(ScopeConstants.defaultTargets[2].y))), // B
            (ScopeConstants.targetLabels[3], CGPoint(x: CGFloat(ScopeConstants.defaultTargets[3].x), y: -CGFloat(ScopeConstants.defaultTargets[3].y))), // CY
            (ScopeConstants.targetLabels[4], CGPoint(x: CGFloat(ScopeConstants.defaultTargets[4].x), y: -CGFloat(ScopeConstants.defaultTargets[4].y))), // G
            (ScopeConstants.targetLabels[5], CGPoint(x: CGFloat(ScopeConstants.defaultTargets[5].x), y: -CGFloat(ScopeConstants.defaultTargets[5].y)))  // YL
        ]
        
        // Note: Metal Y is Down (positive), but in our shader calculation we outputted normalized Y.
        // In shader: norm_y = -(ry / 1.14). 
        // Red Ry=0.7 -> norm_y = -0.615.
        // In Metal texture coords, negative norm_y means UP relative to center (because radius * norm_y added to center).
        // Wait: `pos = center + float2(norm_x, norm_y) * radius;`
        // If norm_y is negative, pos.y < center.y (Up). 
        // In Cocoa (flipped coordinates by default for NSView?), bounds.height is at bottom? 
        // Efficient: NSView is usually isFlipped = false (0,0 bottom-left).
        // center.y + (-0.6 * R). Decreases Y. Goes DOWN in Cocoa.
        // BUT Metal texture 0,0 is Top-Left. So negative Y goes UP in Metal visual. 
        // So they are inverted. 
        // If Metal Config says R.y = -0.615.
        // In Metal (Top-Left 0): Center + (-0.615 * R). Y becomes smaller -> Moves Up. Visual = Top.
        // In Cocoa (Bottom-Left 0): Center + (-0.615 * R). Y becomes smaller -> Moves Down. Visual = Bottom.
        // So we Must Negate Y for Cocoa to place Red at Top.
        // Correct.
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.lightGray
        ]
        
        for (label, normPos) in targets {
            // Targets are already at 75% mag in Constants
            let cx = center.x + normPos.x * radius
            let cy = center.y + normPos.y * radius
            
            // Offset label slightly outward
            let labelOffset: CGFloat = 20
            // Direction vector
            let len = sqrt(normPos.x*normPos.x + normPos.y*normPos.y)
            let dirX = normPos.x / len
            let dirY = normPos.y / len
            
            let textX = cx + dirX * labelOffset
            let textY = cy + dirY * labelOffset
            
            let str = NSAttributedString(string: label, attributes: attributes)
            let size = str.size()
            
            str.draw(at: CGPoint(x: textX - size.width/2, y: textY - size.height/2))
        }
        
        // Skin Tone Label
        let skinAngle = CGFloat(ScopeConstants.skinAngle) * CGFloat.pi / 180.0
        // Metal Skin Dir: cos, -sin. (Matches Y-up math interpreted in Y-down texture... wait).
        // Shader: `float2 skin_dir = float2(cos(skin_angle_rad), -sin(skin_angle_rad));`
        // skin_angle = 123 deg. sin(123) > 0. -sin < 0.
        // So Y component is negative. Center - |val|. Moves Up in Metal (Top-Left).
        // For Cocoa (Bottom-Left), to move Up we need Positive Y.
        // So we need sin(skinAngle).
        // Let's verify: 123 deg is Top-Left quadrant.
        // cos(123) < 0 (Left). sin(123) > 0 (Up).
        // Cocoa: x = center + cos * R. (Left). y = center + sin * R (Up).
        
        let skinDir = CGPoint(x: cos(skinAngle), y: sin(skinAngle))
        
        // Position label at saturation + offset
        let satSkin = CGFloat(ScopeConstants.skinSaturation)
        let skinPos = CGPoint(x: center.x + skinDir.x * radius * satSkin,
                              y: center.y + skinDir.y * radius * satSkin)
        
        let skinOffset: CGFloat = 20
        let skinTextX = skinPos.x + skinDir.x * skinOffset
        let skinTextY = skinPos.y + skinDir.y * skinOffset
        
        let skinStr = NSAttributedString(string: "SKIN", attributes: attributes)
        let skinSize = skinStr.size()
        skinStr.draw(at: CGPoint(x: skinTextX - skinSize.width/2, y: skinTextY - skinSize.height/2))
    }
}
