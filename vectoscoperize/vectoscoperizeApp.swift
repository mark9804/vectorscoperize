import SwiftUI
import ScreenCaptureKit

@main
struct VectoscoperizeApp: App {
    @StateObject var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra("Vectoscoperize", systemImage: "scope") {
            Button("Select Screen Region") {
                appState.startSelection()
            }
            .keyboardShortcut("S")
            
            Button("Vector Scope") {
                appState.renderer.displayMode = .vectorScope
            }
            .keyboardShortcut("1")
            
            Button("RGB Parade") {
                appState.renderer.displayMode = .rgbParade
            }
            .keyboardShortcut("2")
            
            Divider()
            
            Button(appState.isScopeVisible ? "Hide Scopes" : "Show Scopes") {
                appState.toggleScopes()
            }
            .keyboardShortcut("V")
            
            Divider()
            
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("Q")
        }
    }
}

@MainActor
class AppState: ObservableObject {
    var captureEngine = CaptureEngine()
    var renderer = ScopeRenderer()
    var scopeWindowController: ScopeWindowController?
    var selectionWindow: NSWindow?
    
    @Published var isScopeVisible = false
    
    init() {
        // Connect Capture to Renderer
        renderer.setInput(publisher: captureEngine.frameSubject)
    }
    
    func startSelection() {
        // Create full screen overlay
        let overlayView = OverlaySelectionView(isPresented: .constant(true), onSelectionComplete: { rect in
            self.startCapture(rect: rect)
        })
        
        let hostingController = NSHostingController(rootView: overlayView)
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.borderless, .fullSizeContentView]
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        
        // Cover all screens or main screen
        if let screen = NSScreen.main {
            window.setFrame(screen.frame, display: true)
        }
        
        window.makeKeyAndOrderFront(nil)
        selectionWindow = window
    }
    
    func startCapture(rect: CGRect) {
        selectionWindow?.close()
        selectionWindow = nil
        
        Task {
            // Check permissions first
            if await captureEngine.checkPermissions() {
                await captureEngine.refreshContent()
                // Find display. For now assume Main Display.
                // We need to map the rect to the correct display if multiple are present.
                // SCDisplay has 'frame'.
                
                if let display = captureEngine.availableDisplays.first {
                     // Adjust rect relative to display if needed? 
                     // SCStream expects rect in display coordinates usually.
                     // On macOS, specific display coordinate handling is tricky.
                     // We will use the main display for MVP.
                     
                    await captureEngine.startCapture(display: display, rect: rect)
                    
                    DispatchQueue.main.async {
                        self.showScopes()
                    }
                }
            }
        }
    }
    
    func toggleScopes() {
        if isScopeVisible {
            hideScopes()
        } else {
            showScopes()
        }
    }
    
    func showScopes() {
        if scopeWindowController == nil {
            scopeWindowController = ScopeWindowController(renderer: renderer)
        }
        scopeWindowController?.showWindow(nil)
        isScopeVisible = true
    }
    
    func hideScopes() {
        scopeWindowController?.close()
        isScopeVisible = false
    }
}
