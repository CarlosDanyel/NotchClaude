import AppKit
import SwiftUI

@MainActor
final class WindowRouter: NSObject, NSWindowDelegate {
    private unowned let container: AppContainer
    private var monitors: [UUID: NSWindow] = [:]
    private var settingsWindow: NSWindow?

    init(container: AppContainer) {
        self.container = container
    }

    func showMonitor(_ taskId: UUID) {
        if let window = monitors[taskId] {
            present(window)
            return
        }
        guard let task = container.store.task(taskId) else { return }
        let view = MonitorView(taskId: taskId)
            .environmentObject(container)
            .environmentObject(container.store)
            .environmentObject(container.runs)
            .environmentObject(container.settings)
        let window = makeWindow(size: NSSize(width: 820, height: 720), title: task.title, content: view)
        window.minSize = NSSize(width: 560, height: 420)
        window.setFrameAutosaveName("monitor")
        let offset = CGFloat(monitors.count) * 24
        window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX + offset, y: window.frame.maxY - offset))
        monitors[taskId] = window
        present(window)
    }

    func closeMonitor(_ taskId: UUID) {
        monitors[taskId]?.close()
        monitors[taskId] = nil
    }

    func showSettings() {
        if let settingsWindow {
            present(settingsWindow)
            return
        }
        let view = SettingsView()
            .environmentObject(container)
            .environmentObject(container.settings)
            .environmentObject(container.spotify)
        let window = makeWindow(size: NSSize(width: 560, height: 640), title: "Ajustes do NotchClaude", content: view)
        window.styleMask.remove(.resizable)
        settingsWindow = window
        present(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow { settingsWindow = nil }
        if let key = monitors.first(where: { $0.value === window })?.key { monitors[key] = nil }
        DispatchQueue.main.async {
            let hasWindows = self.settingsWindow != nil || !self.monitors.isEmpty
            if !hasWindows { NSApp.setActivationPolicy(.accessory) }
        }
    }

    private func makeWindow<Content: View>(size: NSSize, title: String, content: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.07, alpha: 1)
        window.contentView = NSHostingView(rootView: content.environment(\.colorScheme, .dark))
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
