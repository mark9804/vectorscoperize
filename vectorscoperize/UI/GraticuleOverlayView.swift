import Cocoa
import simd

final class GraticuleOverlayView: NSView {
    var displayMode: ScopeRenderer.DisplayMode = .vectorScope {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard displayMode == .vectorScope else { return }

        let radius = min(bounds.width, bounds.height) * 0.45
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.lightGray,
        ]
        let positions = ScopeConstants.defaultTargets + [ScopeConstants.skinPosition]
        let labels = ScopeConstants.targetLabels + ["SKIN"]

        for (label, position) in zip(labels, positions) {
            // Convert texture coordinates (Y down) to AppKit coordinates (Y up).
            let direction = simd_normalize(position)
            let x = center.x + CGFloat(position.x) * radius + CGFloat(direction.x) * 20
            let y = center.y - CGFloat(position.y) * radius - CGFloat(direction.y) * 20
            let text = NSAttributedString(string: label, attributes: attributes)
            let size = text.size()
            text.draw(at: CGPoint(x: x - size.width / 2, y: y - size.height / 2))
        }
    }
}
