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
    var selectionEventMonitor: Any?
    
    @Published var isScopeVisible = false
    
    init() {
        // Connect Capture to Renderer
        renderer.setInput(publisher: captureEngine.frameSubject)
        
        // Auto-trigger selection on first launch
        DispatchQueue.main.async {
            self.startSelection()
        }
    }
    
    func startSelection() {
        // Prevent multiple selection windows
        if selectionWindow != nil { return }
        
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
        // Allow becoming key despite borderless
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Cover all screens or main screen
        if let screen = NSScreen.main {
            window.setFrame(screen.frame, display: true)
        }
        
        window.makeKeyAndOrderFront(nil)
        selectionWindow = window
        
        // Monitor ESC key to cancel
        selectionEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.cancelSelection()
                return nil
            }
            return event
        }
    }
    
    func cancelSelection() {
        if let window = selectionWindow {
            window.close()
            selectionWindow = nil
        }
        if let monitor = selectionEventMonitor {
            NSEvent.removeMonitor(monitor)
            selectionEventMonitor = nil
        }
    }
    
    func startCapture(rect: CGRect) {
        // Cleanup selection UI
        cancelSelection()
        
        Task {
            // Check permissions first
            if await captureEngine.checkPermissions() {
                await captureEngine.refreshContent()
                // Find display. For now assume Main Display.
                if let display = captureEngine.availableDisplays.first {
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
            let controller = ScopeWindowController(renderer: renderer)
            controller.onReselect = { [weak self] in
                self?.startSelection()
            }
            scopeWindowController = controller
            
            // Sync Window Close with State
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: scopeWindowController?.window, queue: nil) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isScopeVisible = false
                    self?.scopeWindowController = nil
                }
            }
        }
        scopeWindowController?.showWindow(nil)
        isScopeVisible = true
    }
    
    func hideScopes() {
        scopeWindowController?.close()
        // cleanup handled by observer
    }
}
