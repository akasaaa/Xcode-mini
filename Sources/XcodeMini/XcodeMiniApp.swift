import SwiftUI
import AppKit

@main
struct XcodeMiniApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var controller = XcodeController()

    var body: some Scene {
        MenuBarExtra("XcodeMini", systemImage: "hammer.fill") {
            MenuContentView()
                .environment(controller)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon (also enforced via LSUIElement in Info.plist).
        NSApp.setActivationPolicy(.accessory)
    }
}
