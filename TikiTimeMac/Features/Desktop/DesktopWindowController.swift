import AppKit
import SpriteKit
import CoreGraphics

// 포커스 탈취 방지: 이 윈도우는 절대 key/main이 되지 않음
private final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DesktopSKView: SKView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let scene = scene as? CharacterSpriteScene else { return nil }
        // 드래그 중에는 커서 위치 무관하게 이벤트 수신
        if scene.isDragging { return super.hitTest(point) }
        // 캐릭터 위에 있을 때만 이벤트 수신, 그 외는 pass-through
        guard scene.isCharacterHit(at: CGPoint(x: point.x, y: point.y)) else { return nil }
        return super.hitTest(point)
    }
}

final class DesktopWindowController: NSWindowController {
    private var skView: DesktopSKView!
    private var mouseMoveMonitor: Any?

    private static let desktopLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
    )

    init(screen: NSScreen, screenIndex: Int, hasLeftNeighbor: Bool, hasRightNeighbor: Bool, isActive: Bool) {
        let frame = screen.frame
        let window = DesktopWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        configure(screen: screen, screenIndex: screenIndex, hasLeftNeighbor: hasLeftNeighbor, hasRightNeighbor: hasRightNeighbor, isActive: isActive)
    }

    required init?(coder: NSCoder) { nil }

    private func configure(screen: NSScreen, screenIndex: Int, hasLeftNeighbor: Bool, hasRightNeighbor: Bool, isActive: Bool) {
        guard let window else { return }

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = Self.desktopLevel
        window.ignoresMouseEvents = true  // 기본값: 이벤트 통과, 캐릭터 위에서만 false로 전환
        window.isMovable = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.setFrame(screen.frame, display: false)

        let size = screen.frame.size
        skView = DesktopSKView(frame: CGRect(origin: .zero, size: size))
        skView.allowsTransparency = true
        skView.showsFPS = false
        skView.showsNodeCount = false

        let scene = CharacterSpriteScene(size: size)
        scene.floorY = 4
        scene.screen = screen
        scene.dockInfo = DockDetector.detect(on: screen)
        scene.screenIndex = screenIndex
        scene.isInitiallyActive = isActive
        scene.hasLeftNeighbor = hasLeftNeighbor
        scene.hasRightNeighbor = hasRightNeighbor
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)

        window.contentView = skView
        startCursorTracking()
    }

    private func startCursorTracking() {
        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.updateIgnoresMouseEvents()
        }
    }

    private func updateIgnoresMouseEvents() {
        guard let window, let scene = skView?.scene as? CharacterSpriteScene else { return }
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let viewPoint = skView.convert(windowPoint, from: nil)
        let isOver = scene.isDragging || scene.isCharacterHit(at: CGPoint(x: viewPoint.x, y: viewPoint.y))
        window.ignoresMouseEvents = !isOver
    }

    deinit {
        if let monitor = mouseMoveMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func showWindow(_ sender: Any?) {
        window?.orderFront(nil)
    }
}
