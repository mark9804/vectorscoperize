import Cocoa
import SwiftUI
import MetalKit

import Combine

class ScopeWindowController: NSWindowController {
    
    private var overlayView: GraticuleOverlayView?
    private var renderer: ScopeRenderer?
    private var cancellables = Set<AnyCancellable>()
    
    var onReselect: (() -> Void)?
    private var eventMonitor: Any?
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    convenience init(renderer: ScopeRenderer) {
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 512, height: 512),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered, defer: false
        )
        panel.level = .floating // Always on top
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "Vectoscoperize"
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        
        // Metal View
        let metalView = MTKView()
        metalView.device = renderer.device
        metalView.delegate = renderer
        metalView.framebufferOnly = false
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalView.enableSetNeedsDisplay = true 
        metalView.isPaused = false
        
        // Overlay View
        let overlay = GraticuleOverlayView()
        
        // Container
        let container = NSView()
        container.addSubview(metalView)
        container.addSubview(overlay)
        
        metalView.translatesAutoresizingMaskIntoConstraints = false
        overlay.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            metalView.topAnchor.constraint(equalTo: container.topAnchor),
            metalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        // Initial Mode
        switch renderer.displayMode {
        case .vectorScope: overlay.displayMode = .vectorScope
        case .rgbParade: overlay.displayMode = .rgbParade
        case .split: overlay.displayMode = .split
        }
        
        panel.contentView = container
        
        self.init(window: panel)
        self.renderer = renderer
        self.overlayView = overlay
        
        renderer.$displayMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                switch mode {
                case .vectorScope: self?.overlayView?.displayMode = .vectorScope
                case .rgbParade: self?.overlayView?.displayMode = .rgbParade
                case .split: self?.overlayView?.displayMode = .split
                }
            }
            .store(in: &cancellables)
            
        // Setup Keyboard Shortcuts
        self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
             guard let self = self, self.window?.isKeyWindow == true else { return event }
             
             if event.modifierFlags.contains(.command) {
                 switch event.charactersIgnoringModifiers {
                 case "s", "S":
                     self.onReselect?()
                     return nil
                 case "1":
                     self.renderer?.displayMode = .vectorScope
                     return nil
                 case "2":
                     self.renderer?.displayMode = .rgbParade
                     return nil
                 case "v", "V":
                     self.close()
                     return nil
                 default:
                     break
                 }
             }
             return event
        }
    }
}

// SwiftUI Wrapper (Optional, if we want to use WindowGroup, but we are using NSWindowController for specific NSPanel behaviors)
struct ScopeWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            // Find window and configure
            if let window = view.window {
                window.level = .floating
                window.styleMask.insert(.hudWindow)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
