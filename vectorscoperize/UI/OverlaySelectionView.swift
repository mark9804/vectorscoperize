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
        // The overlay fills the selected display. Both coordinates use points from its top left.
        return selectionRect
    }
}
