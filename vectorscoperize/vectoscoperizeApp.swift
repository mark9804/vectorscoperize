import AppKit

@main
enum VectorscoperizeApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let appState = AppState()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "scope", accessibilityDescription: "Vectorscoperize")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "Vectorscoperize"

        let menu = NSMenu()
        menu.addItem(withTitle: "Select Screen Region", action: #selector(selectRegion), keyEquivalent: "s")
        menu.addItem(withTitle: "Vector Scope", action: #selector(showVectorScope), keyEquivalent: "1")
        menu.addItem(withTitle: "RGB Parade", action: #selector(showRGBParade), keyEquivalent: "2")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show Scopes", action: #selector(toggleScopes), keyEquivalent: "v")
        menu.addItem(.separator())
        for menuItem in menu.items where !menuItem.isSeparatorItem {
            menuItem.target = self
        }
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            .target = NSApp
        item.menu = menu
        statusItem = item

        appState.reopen()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appState.reopen()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleScopes):
            menuItem.title = appState.isScopeVisible ? "Hide Scopes" : "Show Scopes"
        case #selector(showVectorScope):
            menuItem.state = appState.renderer.displayMode == .vectorScope ? .on : .off
        case #selector(showRGBParade):
            menuItem.state = appState.renderer.displayMode == .rgbParade ? .on : .off
        default:
            break
        }
        return true
    }

    @objc private func selectRegion() { appState.startSelection() }
    @objc private func showVectorScope() { appState.renderer.displayMode = .vectorScope }
    @objc private func showRGBParade() { appState.renderer.displayMode = .rgbParade }
    @objc private func toggleScopes() { appState.toggleScopes() }
}
