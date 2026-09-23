import ScreenCaptureKit
import SwiftUI

@MainActor
final class AppState {
    let captureEngine: CaptureEngine
    let renderer = ScopeRenderer()
    private(set) var scopeWindowController: ScopeWindowController?
    private var selectionWindow: NSWindow?
    private var selectionEventMonitor: Any?
    private var selectedRegion: (displayID: CGDirectDisplayID, rect: CGRect)?
    private var captureTask: Task<Void, Never>?

    var isScopeVisible: Bool { scopeWindowController?.window?.isVisible == true }

    convenience init() {
        self.init(captureEngine: CaptureEngine())
    }

    init(captureEngine: CaptureEngine) {
        self.captureEngine = captureEngine
        renderer.setInput(publisher: captureEngine.frameSubject)
    }

    func reopen() {
        if isScopeVisible {
            scopeWindowController?.showWindow(nil)
        } else {
            showScopes()
        }
    }

    func startSelection() {
        if let window = selectionWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        guard let screen = NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID else { return }

        let overlay = OverlaySelectionView(
            isPresented: .constant(true),
            onSelectionComplete: { [weak self] rect in
                self?.selectRegion(displayID: displayID, rect: rect)
            })
        let window = NSWindow(contentViewController: NSHostingController(rootView: overlay))
        window.styleMask = [.borderless, .fullSizeContentView]
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrame(screen.frame, display: true)
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

    func selectRegion(displayID: CGDirectDisplayID, rect: CGRect) {
        cancelSelection()
        selectedRegion = (displayID, rect)
        showScopes()
    }

    private func updateCapture() {
        // Finish an in-flight start/stop before applying the latest window state.
        let previousTask = captureTask
        previousTask?.cancel()
        captureTask = Task {
            await previousTask?.value
            guard !Task.isCancelled else { return }
            await captureEngine.stopCapture()
            guard !Task.isCancelled, isScopeVisible, let region = selectedRegion else { return }
            let permitted = await captureEngine.checkPermissions()
            guard !Task.isCancelled, isScopeVisible else { return }
            guard permitted else {
                hideScopes()
                showScreenRecordingPermissionAlert()
                return
            }
            await captureEngine.startCapture(displayID: region.displayID, rect: region.rect)
            if Task.isCancelled || !isScopeVisible {
                await captureEngine.stopCapture()
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
        guard selectedRegion != nil else {
            startSelection()
            return
        }
        cancelSelection()
        if scopeWindowController == nil {
            let controller = ScopeWindowController(renderer: renderer)
            controller.onReselect = { [weak self] in self?.startSelection() }
            controller.onClose = { [weak self] in self?.updateCapture() }
            scopeWindowController = controller
        }
        scopeWindowController?.showWindow(nil)
        updateCapture()
    }

    func hideScopes() {
        scopeWindowController?.close()
    }
}
