import AppKit
import SwiftUI

struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var notchSize: CGSize
    var hasNotch: Bool

    static let fallback = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), notchSize: CGSize(width: 190, height: 32), hasNotch: false)

    static func make(for screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            return NotchGeometry(screenFrame: frame, notchSize: CGSize(width: width, height: screen.safeAreaInsets.top), hasNotch: true)
        }
        let menuBar = frame.maxY - screen.visibleFrame.maxY
        let height = menuBar > 10 ? min(menuBar, 32) : 28
        return NotchGeometry(screenFrame: frame, notchSize: CGSize(width: 190, height: height), hasNotch: false)
    }
}

enum LiveActivity: Equatable {
    case running(count: Int, startedAt: Date, title: String)
    case limited(until: Date, kind: String)
}

enum NotchStatus: Equatable {
    case idle
    case scheduled
    case queued
    case running
    case limited
    case failed

    static func resolve(tasks: [ClaudeTask], limit: LimitState, running: Int, acknowledgedAt: Date, now: Date = Date()) -> NotchStatus {
        if running > 0 { return .running }
        if limit.isBlocked(at: now) || tasks.contains(where: { $0.status == .rateLimited }) { return .limited }
        if tasks.contains(where: { $0.status == .failed && ($0.finishedAt ?? .distantPast) > acknowledgedAt }) { return .failed }
        if tasks.contains(where: { $0.status == .queued }) { return .queued }
        if tasks.contains(where: { $0.status == .scheduled }) { return .scheduled }
        return .idle
    }
}

struct NotchPeek: Equatable, Identifiable {
    let id = UUID()
    var symbol: String
    var tint: Color
    var title: String
    var subtitle: String
}

@MainActor
final class NotchViewModel: ObservableObject {
    enum Phase {
        case closed
        case open
    }

    enum Page {
        case tasks
        case compose
        case media
    }

    @Published var phase: Phase = .closed
    @Published var page: Page = .tasks
    @Published var geometry = NotchGeometry.fallback
    @Published var liveActivity: LiveActivity?
    @Published var peek: NotchPeek?
    @Published var isDraggingFiles = false
    @Published var isDropTargeted = false
    @Published var hovering = false
    @Published var status: NotchStatus = .idle
    @Published var showsStatus = false
    @Published var showsMusic = false

    static let openWidth: CGFloat = 700
    static let contentPadding: CGFloat = 15

    var isOpen: Bool { phase == .open }

    var topRadius: CGFloat { isOpen ? 14 : 6 }

    var bottomRadius: CGFloat {
        if isOpen { return 30 }
        return peek == nil ? 11 : 20
    }

    var wingWidth: CGFloat { geometry.notchSize.height + 10 }

    var hasWings: Bool { liveActivity != nil || peek != nil || showsStatus || showsMusic }

    func openHeight(for page: Page) -> CGFloat {
        switch page {
        case .tasks: return 318
        case .compose: return 418
        case .media: return 280
        }
    }

    var shapeSize: CGSize {
        let notch = geometry.notchSize
        if isOpen {
            return CGSize(width: Self.openWidth, height: openHeight(for: page))
        }
        var width = notch.width + topRadius * 2
        var height = notch.height
        if hasWings { width += wingWidth * 2 }
        if peek != nil {
            width = max(width + 40, 400)
            height += 40
        }
        if hovering && !geometry.hasNotch { height += 2 }
        return CGSize(width: width, height: height)
    }

    var isShapeVisible: Bool {
        isOpen || geometry.hasNotch || hasWings || hovering
    }
}
