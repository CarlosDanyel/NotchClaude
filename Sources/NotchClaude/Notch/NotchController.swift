import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class NotchController {
    let model = NotchViewModel()

    private unowned let container: AppContainer
    private var panel: NotchPanel?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var peekWork: DispatchWorkItem?
    private var trackingTimer: Timer?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var modalDepth = 0
    private var sticky = false

    private static let panelSize = CGSize(width: 780, height: 480)

    init(container: AppContainer) {
        self.container = container
    }

    func install() {
        let panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize))
        panel.onPaste = { [weak self] in self?.pasteAttachments() ?? false }
        let root = NotchRootView(model: model, controller: self)
            .environmentObject(container)
            .environmentObject(container.store)
            .environmentObject(container.runs)
            .environmentObject(container.settings)
            .environmentObject(container.composer)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.ignoresMouseEvents = true
        self.panel = panel

        layout()
        installMonitors()
        observeState()
        startTracking()
    }

    func open(page: NotchViewModel.Page? = nil, sticky: Bool = true) {
        cancelPending()
        if sticky { self.sticky = true }
        if model.isOpen {
            if let page, page != model.page { withAnimation(Theme.openSpring) { model.page = page } }
            return
        }
        if container.settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        peekWork?.cancel()
        withAnimation(Theme.openSpring) {
            model.peek = nil
            if let page { model.page = page }
            model.phase = .open
        }
        panel?.ignoresMouseEvents = false
    }

    func close() {
        cancelPending()
        sticky = false
        guard model.isOpen else { return }
        withAnimation(Theme.closeSpring) {
            model.phase = .closed
            model.isDraggingFiles = false
            model.isDropTargeted = false
            model.hovering = false
        }
        if let panel, panel.isKeyWindow {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        updateMouseState()
    }

    func toggle() {
        model.isOpen ? close() : open()
    }

    func showPeek(_ peek: NotchPeek) {
        guard !model.isOpen else { return }
        peekWork?.cancel()
        withAnimation(Theme.openSpring) { model.peek = peek }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(Theme.closeSpring) { self.model.peek = nil }
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: work)
    }

    func showMonitor(_ taskId: UUID) {
        close()
        container.router.showMonitor(taskId)
    }

    func showSettings() {
        close()
        container.router.showSettings()
    }

    func runModal<T>(_ body: () -> T) -> T {
        modalDepth += 1
        NSApp.activate(ignoringOtherApps: true)
        let result = body()
        modalDepth -= 1
        panel?.makeKey()
        return result
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Usar esta pasta"
        panel.message = "Escolha a pasta onde o Claude vai trabalhar"
        panel.directoryURL = URL(fileURLWithPath: container.composer.directory)
        let response = runModal { panel.runModal() }
        if response == .OK, let url = panel.url {
            container.composer.setDirectory(url.path)
        }
    }

    func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Anexar"
        panel.message = "Imagens vão direto para o Claude; outros arquivos são enviados pelo caminho"
        let response = runModal { panel.runModal() }
        if response == .OK {
            container.composer.add(AttachmentImporter.importFiles(panel.urls))
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        var images: [Data] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url {
                        lock.lock()
                        urls.append(url)
                        lock.unlock()
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data {
                        lock.lock()
                        images.append(data)
                        lock.unlock()
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            var attachments = AttachmentImporter.importFiles(urls)
            attachments += images.compactMap { AttachmentImporter.importImageData($0, name: "Imagem.png") }
            if let directory = urls.first(where: { $0.hasDirectoryPath }) {
                attachments.removeAll { $0.originalName == directory.lastPathComponent && !$0.isImage }
                self.container.composer.setDirectory(directory.path)
            }
            self.container.composer.add(attachments)
            self.model.isDraggingFiles = false
            self.open(page: .compose)
        }
        return !providers.isEmpty
    }

    private func pasteAttachments() -> Bool {
        guard model.isOpen, model.page == .compose, AttachmentImporter.pasteboardHasAttachments() else { return false }
        let attachments = AttachmentImporter.importFromPasteboard()
        guard !attachments.isEmpty else { return false }
        container.composer.add(attachments)
        return true
    }

    private func layout() {
        guard let panel else { return }
        let screens = NSScreen.screens
        let notched = screens.first { $0.safeAreaInsets.top > 0 }
        guard let screen = notched ?? (container.settings.showOnNonNotchScreens ? (NSScreen.main ?? screens.first) : nil) else {
            panel.orderOut(nil)
            return
        }
        model.geometry = NotchGeometry.make(for: screen)
        let frame = NSRect(
            x: screen.frame.midX - Self.panelSize.width / 2,
            y: screen.frame.maxY - Self.panelSize.height,
            width: Self.panelSize.width,
            height: Self.panelSize.height
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func installMonitors() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, local: false) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                if event.type == .keyDown, event.keyCode == 53, event.window === self.panel, self.model.isOpen {
                    self.close()
                    return true
                }
                if event.type != .keyDown { self.handle(event, local: true) }
                return false
            }
            return consumed ? nil : event
        }
        monitors = [global, local].compactMap { $0 }

        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.orderFrontRegardless() }
        })
    }

    private func observeState() {
        let store = container.store
        let runs = container.runs
        Publishers.CombineLatest3(store.$tasks, store.$limit, runs.$sessions)
            .receive(on: RunLoop.main)
            .sink { [weak self] tasks, limit, sessions in
                self?.updateLiveActivity(tasks: tasks, limit: limit, sessions: sessions)
            }
            .store(in: &cancellables)

        container.settings.$showOnNonNotchScreens
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.layout() }
            .store(in: &cancellables)
    }

    private func updateLiveActivity(tasks: [ClaudeTask], limit: LimitState, sessions: [UUID: RunSession]) {
        let activity: LiveActivity?
        if let session = sessions.values.min(by: { $0.startedAt < $1.startedAt }) {
            let title = tasks.first { $0.id == session.taskId }?.title ?? "Claude"
            activity = .running(count: sessions.count, startedAt: session.startedAt, title: title)
        } else if let until = limit.blockedUntil, limit.isBlocked() {
            activity = .limited(until: until, kind: limit.kindLabel)
        } else {
            activity = nil
        }
        guard activity != model.liveActivity else { return }
        withAnimation(Theme.openSpring) { model.liveActivity = activity }
    }

    private func startTracking() {
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouseState() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func handle(_ event: NSEvent, local: Bool) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            dragChangeCount = NSPasteboard(name: .drag).changeCount
            if !local, model.isOpen, modalDepth == 0, !visibleRect.contains(NSEvent.mouseLocation) {
                close()
            }
        case .leftMouseDragged:
            let pasteboard = NSPasteboard(name: .drag)
            if pasteboard.changeCount != dragChangeCount, dropZone.contains(NSEvent.mouseLocation), !model.isDraggingFiles {
                model.isDraggingFiles = true
                open(page: .compose)
            }
            updateMouseState()
        case .leftMouseUp:
            if model.isDraggingFiles {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.model.isDraggingFiles = false
                }
            }
        default:
            updateMouseState()
        }
    }

    private var visibleRect: CGRect {
        let size = model.shapeSize
        let screen = model.geometry.screenFrame
        return CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height, width: size.width, height: size.height)
    }

    private var closedHotRect: CGRect {
        let rect = visibleRect
        return CGRect(x: rect.minX - 6, y: rect.minY - 4, width: rect.width + 12, height: rect.height + 6)
    }

    private var dropZone: CGRect {
        let screen = model.geometry.screenFrame
        let width = model.isOpen ? model.shapeSize.width + 40 : model.geometry.notchSize.width + 260
        let height = model.isOpen ? model.shapeSize.height + 30 : model.geometry.notchSize.height + 70
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height + 2)
    }

    private var shouldStayOpen: Bool {
        if modalDepth > 0 || model.isDraggingFiles { return true }
        if container.settings.preventCloseWhileTyping, model.page == .compose, panel?.isKeyWindow == true { return true }
        return false
    }

    private func updateMouseState() {
        guard let panel else { return }
        let point = NSEvent.mouseLocation
        if model.isOpen {
            panel.ignoresMouseEvents = !visibleRect.insetBy(dx: -2, dy: -2).contains(point)
            let inside = visibleRect.insetBy(dx: -8, dy: -8).contains(point)
            if inside { sticky = false }
            if inside || sticky || shouldStayOpen {
                closeWork?.cancel()
                closeWork = nil
            } else if closeWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.closeWork = nil
                    if !self.shouldStayOpen { self.close() }
                }
                closeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
            }
            return
        }

        let inside = closedHotRect.contains(point)
        panel.ignoresMouseEvents = !inside
        if inside != model.hovering {
            withAnimation(.easeOut(duration: 0.15)) { model.hovering = inside }
        }
        guard container.settings.openOnHover else { return }
        if inside, openWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.openWork = nil
                if self.closedHotRect.contains(NSEvent.mouseLocation) { self.open(sticky: false) }
            }
            openWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: work)
        } else if !inside {
            openWork?.cancel()
            openWork = nil
        }
    }

    private func cancelPending() {
        openWork?.cancel()
        openWork = nil
        closeWork?.cancel()
        closeWork = nil
    }
}
