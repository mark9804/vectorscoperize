import Cocoa
import Combine
import MetalKit

private final class ScopeMetalView: MTKView {
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
}

class ScopeWindowController: NSWindowController, NSWindowDelegate {

    private var overlayView: GraticuleOverlayView?
    private var renderer: ScopeRenderer?
    private var cancellables = Set<AnyCancellable>()

    var onReselect: (() -> Void)?
    var onClose: (() -> Void)?
    private var eventMonitor: Any?

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        renderer?.mtkView?.draw()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    convenience init(renderer: ScopeRenderer) {
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 512, height: 512),
            styleMask: [
                .titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow, .hudWindow,
            ],
            backing: .buffered, defer: false
        )
        panel.level = .floating  // Always on top
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "Vectorscoperize"
        panel.isFloatingPanel = true
        // Keep scopes visible while the user edits a photo in another application.
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false

        // Enforce 1:1 Aspect Ratio
        panel.contentAspectRatio = NSSize(width: 1, height: 1)

        // Metal View
        let metalView = ScopeMetalView()
        metalView.device = renderer.device
        metalView.delegate = renderer
        metalView.framebufferOnly = false
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalView.enableSetNeedsDisplay = true
        metalView.isPaused = true

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
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Initial Mode
        overlay.displayMode = renderer.displayMode

        panel.contentView = container

        self.init(window: panel)
        panel.delegate = self
        self.renderer = renderer
        self.overlayView = overlay

        // Link view for event-driven rendering
        renderer.mtkView = metalView

        renderer.$displayMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.overlayView?.displayMode = mode
            }
            .store(in: &cancellables)

        // Setup Keyboard Shortcuts
        self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
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
                case "q", "Q":
                    NSApp.terminate(nil)
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }
}
