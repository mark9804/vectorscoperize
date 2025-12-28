import SwiftUI

struct OverlaySelectionView: View {
    @Binding var isPresented: Bool
    var onSelectionComplete: (CGRect) -> Void
    
    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    @State private var selectionRect: CGRect = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed background
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if startPoint == nil {
                                    startPoint = value.location
                                }
                                currentPoint = value.location
                                updateRect()
                            }
                            .onEnded { value in
                                if let rect = normalizedRect() {
                                    // Convert to global screen coordinates
                                    // This requires knowledge of the window's position, but this view is full screen.
                                    // We'll assume the window matches the screen 1:1.
                                    onSelectionComplete(rect)
                                }
                                isPresented = false
                                startPoint = nil
                                currentPoint = nil
                                selectionRect = .zero
                            }
                    )
                
                // Selection Box
                if startPoint != nil {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 2)
                        .background(Color.white.opacity(0.1))
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                }
                
                Text("Click and Drag to select a region")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .position(x: geometry.size.width / 2, y: 50)
            }
        }
    }
    
    private func updateRect() {
        guard let start = startPoint, let current = currentPoint else { return }
        selectionRect = CGRect(x: min(start.x, current.x),
                               y: min(start.y, current.y),
                               width: abs(current.x - start.x),
                               height: abs(current.y - start.y))
    }
    
    private func normalizedRect() -> CGRect? {
        if selectionRect.width < 10 || selectionRect.height < 10 { return nil }
        // Ensure we map coordinates correctly to ScreenCaptureKit expected coordinates.
        // CGWindow/Screen coordinates usually have origin at top-left for SCKit (or bottom-left for CoreGraphics).
        // SwiftUI is top-left. ScreenCaptureKit is also top-left usually (pixel space).
        // We will pass the rect as is, assuming the OverlayWindow is covering the relevant screen.
        // Multi-monitor support would require more complex mapping.
        
        // For macOS "Tahoe" (haha) / Sequoia, we assume main monitor for now or cover all screens.
        // Convert to screen coordinates.
        if let window = NSApp.windows.first(where: { $0.contentView?.frame.contains(startPoint ?? .zero) ?? false }) {
             let screenRect = window.convertToScreen(selectionRect)
             // CoreGraphics origin is Bottom-Left, but SCContentFilter might expect Top-Left depending on usage?
             // Actually SCContentFilter uses CGRect. It matches CGWindowList.
             // We'll rely on global coordinates.
             
             // Simplification: Return the rect in the window's coordinate system, which matches main screen if full screen.
             // We will handle the flip in the caller if needed.
             // Let's assume Main Screen for MVP.
             if let _ = NSScreen.main {
                  // Cocoa (Bottom-Left) -> standard Top-Left for image processing usually
                  // But SCStreamConfiguration expects coordinates in display space?
                  // Let's stick to standard CG rects.
                  // We need to return rect in GLOBAL SCREEN COORDINATES (Bottom-Left origin usually for macOS Window Server).
                  return screenRect
             }
        }
        return selectionRect
    }
}
