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
    }

    @Published var phase: Phase = .closed
    @Published var page: Page = .tasks
    @Published var geometry = NotchGeometry.fallback
    @Published var liveActivity: LiveActivity?
    @Published var peek: NotchPeek?
    @Published var isDraggingFiles = false
    @Published var isDropTargeted = false
    @Published var hovering = false

    static let openWidth: CGFloat = 700
    static let contentPadding: CGFloat = 15

    var isOpen: Bool { phase == .open }

    var topRadius: CGFloat { isOpen ? 14 : 6 }

    var bottomRadius: CGFloat {
        if isOpen { return 30 }
        return peek == nil ? 11 : 20
    }

    var wingWidth: CGFloat { geometry.notchSize.height + 6 }

    func openHeight(for page: Page) -> CGFloat {
        page == .compose ? 418 : 318
    }

    var shapeSize: CGSize {
        let notch = geometry.notchSize
        if isOpen {
            return CGSize(width: Self.openWidth, height: openHeight(for: page))
        }
        var width = notch.width + topRadius * 2
        var height = notch.height
        if liveActivity != nil || peek != nil { width += wingWidth * 2 }
        if peek != nil {
            width = max(width + 40, 400)
            height += 40
        }
        if hovering && !geometry.hasNotch { height += 2 }
        return CGSize(width: width, height: height)
    }

    var isShapeVisible: Bool {
        isOpen || geometry.hasNotch || liveActivity != nil || peek != nil || hovering
    }
}
