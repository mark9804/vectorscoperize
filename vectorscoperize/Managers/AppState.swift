import ScreenCaptureKit
import SwiftUI

@MainActor
final class AppState {
    let captureEngine = CaptureEngine()
    let renderer = ScopeRenderer()
    private(set) var scopeWindowController: ScopeWindowController?
    private var selectionWindow: NSWindow?
    private var selectionEventMonitor: Any?

    var isScopeVisible: Bool { scopeWindowController?.window?.isVisible == true }

    init() {
        renderer.setInput(publisher: captureEngine.frameSubject)
    }

    func reopen() {
        if captureEngine.isCapturing {
            showScopes()
        } else {
            startSelection()
        }
    }

    func startSelection() {
        if let window = selectionWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let overlay = OverlaySelectionView(
            isPresented: .constant(true),
            onSelectionComplete: { [weak self] rect in self?.startCapture(rect: rect) })
        let window = NSWindow(contentViewController: NSHostingController(rootView: overlay))
        window.styleMask = [.borderless, .fullSizeContentView]
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if let screen = NSScreen.main {
            window.setFrame(screen.frame, display: true)
        }
        window.makeKeyAndOrderFront(nil)
        selectionWindow = window

        selectionEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelSelection()
                return nil
            }
            return event
        }
    }

    func cancelSelection() {
        selectionWindow?.close()
        selectionWindow = nil
        if let monitor = selectionEventMonitor {
            NSEvent.removeMonitor(monitor)
            selectionEventMonitor = nil
        }
    }

    private func startCapture(rect: CGRect) {
        cancelSelection()
        Task {
            guard await captureEngine.checkPermissions() else { return }
            await captureEngine.refreshContent()
            guard let display = captureEngine.availableDisplays.first else { return }
            await captureEngine.startCapture(display: display, rect: rect)
            if captureEngine.isCapturing {
                showScopes()
            }
        }
    }

    func toggleScopes() {
        if isScopeVisible {
            hideScopes()
        } else {
            reopen()
        }
    }

    func showScopes() {
        if scopeWindowController == nil {
            let controller = ScopeWindowController(renderer: renderer)
            controller.onReselect = { [weak self] in self?.startSelection() }
            scopeWindowController = controller
        }
        scopeWindowController?.showWindow(nil)
    }

    func hideScopes() {
        scopeWindowController?.close()
    }
}
