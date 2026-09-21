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
            guard await captureEngine.checkPermissions() else {
                showScreenRecordingPermissionAlert()
                return
            }
            await captureEngine.refreshContent()
            guard let display = captureEngine.availableDisplays.first else { return }
            await captureEngine.startCapture(display: display, rect: rect)
            if captureEngine.isCapturing {
                showScopes()
            }
        }
    }

    func showScreenRecordingPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Allow Vectorscoperize in System Settings → Privacy & Security → Screen & System Audio Recording, then choose Select Screen Region from the menu bar to try again. If macOS asks, quit and reopen Vectorscoperize."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Select Screen Region")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")!)
        case .alertSecondButtonReturn:
            startSelection()
        default:
            break
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
