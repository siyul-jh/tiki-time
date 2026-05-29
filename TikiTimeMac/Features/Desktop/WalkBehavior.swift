import CoreGraphics
import Foundation

enum WalkDirection {
    case left, right
}

enum WalkState {
    case idle
    case walking(WalkDirection)
}

final class WalkBehavior {
    private(set) var state: WalkState = .idle
    private(set) var velocity: CGFloat = 0

    private let sceneBounds: CGRect
    private var speed: CGFloat

    private var stateTime: TimeInterval = 0
    private var stateDuration: TimeInterval = 0
    private var isPaused = false

    var hasLeftNeighbor = false
    var hasRightNeighbor = false

    var onStateChange: ((WalkState) -> Void)?
    var onTransfer: ((WalkDirection) -> Void)?
    var positionX: CGFloat

    private var isTestWalking = false
    private var testWalkCompletion: (() -> Void)?

    init(startX: CGFloat, sceneBounds: CGRect, speed: CGFloat = 80) {
        self.positionX = startX
        self.sceneBounds = sceneBounds
        self.speed = speed
        enterIdle()
    }

    func update(deltaTime: TimeInterval) {
        guard !isPaused else { return }

        stateTime += deltaTime

        if velocity != 0 {
            positionX += velocity * CGFloat(deltaTime)
            checkBoundary()
        }

        if stateTime >= stateDuration {
            transitionNext()
        }
    }

    func updateSpeed(_ newSpeed: CGFloat) {
        speed = newSpeed
        if case .walking(let direction) = state {
            velocity = direction == .right ? newSpeed : -newSpeed
        }
    }

    func pause() {
        isPaused = true
        velocity = 0
    }

    func resume() {
        isPaused = false
        enterIdle()
    }

    func enterFromEdge(traveling direction: WalkDirection) {
        isPaused = false
        positionX = direction == .right ? sceneBounds.minX + 10 : sceneBounds.maxX - 10
        enterWalk(direction: direction)
    }

    func beginForcedRoundTrip(from startX: CGFloat? = nil, completion: @escaping () -> Void) {
        isTestWalking = true
        testWalkCompletion = completion
        isPaused = false
        positionX = startX ?? sceneBounds.minX + 10
        stateTime = 0
        stateDuration = 9999
        state = .walking(.right)
        velocity = speed
        onStateChange?(.walking(.right))
    }

    private func checkBoundary() {
        if isTestWalking {
            if velocity > 0, positionX >= sceneBounds.maxX - 10 {
                positionX = sceneBounds.maxX - 10
                velocity = -speed
                state = .walking(.left)
                onStateChange?(.walking(.left))
            } else if velocity < 0, positionX <= sceneBounds.minX + 10 {
                positionX = sceneBounds.minX + 10
                isTestWalking = false
                let cb = testWalkCompletion
                testWalkCompletion = nil
                cb?()
                enterIdle()
            }
            return
        }

        if positionX <= sceneBounds.minX + 10, hasLeftNeighbor {
            onTransfer?(.left)
        } else if positionX >= sceneBounds.maxX - 10, hasRightNeighbor {
            onTransfer?(.right)
        } else if positionX <= sceneBounds.minX + 60, !hasLeftNeighbor {
            positionX = sceneBounds.minX + 60
            transitionNext()
        } else if positionX >= sceneBounds.maxX - 60, !hasRightNeighbor {
            positionX = sceneBounds.maxX - 60
            transitionNext()
        }
    }

    private func transitionNext() {
        if Double.random(in: 0...1) < 0.35 {
            enterIdle()
        } else {
            enterWalk(direction: Bool.random() ? .left : .right)
        }
    }

    private func enterIdle() {
        state = .idle
        velocity = 0
        stateTime = 0
        stateDuration = Double.random(in: 1.5...4.0)
        onStateChange?(.idle)
    }

    private func enterWalk(direction: WalkDirection) {
        state = .walking(direction)
        velocity = direction == .right ? speed : -speed
        stateTime = 0
        stateDuration = Double.random(in: 3.0...7.0)
        onStateChange?(.walking(direction))
    }
}
