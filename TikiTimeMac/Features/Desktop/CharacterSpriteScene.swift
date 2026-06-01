import SpriteKit
import TikiTimeCore

final class CharacterSpriteScene: SKScene {
    // MARK: - Main character
    private var characterNode: CharacterNode!
    private var walkBehavior: WalkBehavior!
    private var manifest: CharacterManifest = CharacterSpriteScene.loadManifest(id: UserSettings.load().mainCharacterId)
    private var emotionTextureCache: [String: SKTexture] = [:]
    private var emotionFrameCache: [String: [SKTexture]] = [:]
    private var lastIdleMessageTime: TimeInterval = -60
    private var nextWalkMessageTime: TimeInterval = 25
    private var currentFloorY: CGFloat = 0

    // MARK: - Secondary characters
    private struct SecondaryCharacter {
        let node: CharacterNode
        let behavior: WalkBehavior
        let manifest: CharacterManifest
        var emotionTextureCache: [String: SKTexture] = [:]
        var emotionFrameCache: [String: [SKTexture]] = [:]
        var currentFloorY: CGFloat = 0
        var dockVelocityY: CGFloat = 0
        var isDockPhysics: Bool = false
        var isDropping: Bool = false
        var dropVelocity: CGFloat = 0
        var lastIdleMessageTime: TimeInterval = -60
        var nextWalkMessageTime: TimeInterval = 0
    }
    private var secondaryCharacters: [SecondaryCharacter] = []

    // MARK: - Drag / Drop physics
    private(set) var isDragging = false
    private var hasDragged = false
    private var dragStartLocation: CGPoint = .zero
    private var dragStartCharacterPos: CGPoint = .zero
    private let dragThreshold: CGFloat = 5
    private var draggingSecondaryIndex: Int? = nil

    private var isDropping = false
    private var dropVelocity: CGFloat = 0
    private let dropGravity: CGFloat = -1500
    private let dropBounce: CGFloat = 0.25

    private var isDragOwner = false
    private var crossScreenTargetIndex: Int? = nil
    private var isReceivingCrossDrag = false
    private var isReceivingSecondaryDragIndex: Int? = nil

    // MARK: - Scene config
    private var dockVelocityY: CGFloat = 0
    private var isDockPhysics: Bool = false
    private var lastUpdateTime: TimeInterval = 0
    private var hourlyTimer: Timer?
    private var globalMouseMonitor: Any?
    var floorY: CGFloat = 80
    var dockInfo: DockInfo?
    var screen: NSScreen?
    var screenIndex: Int = 0
    var isInitiallyActive: Bool = false
    var hasLeftNeighbor: Bool = false
    var hasRightNeighbor: Bool = false

    // MARK: - Manifest loading

    private static func loadManifest(id: String) -> CharacterManifest {
        if let manifest = CharacterStorageService.loadManifest(id: id) {
            return manifest
        }
        return CharacterManifest(id: "default", displayName: "아롬", version: "1.0.0", emoji: "🐈‍⬛")
    }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        anchorPoint = .zero
        let settings = UserSettings.load()
        setupMainCharacter(settings: settings)
        setupSecondaryCharacters(settings: settings)
        scheduleHourlyAnimation()

        NotificationCenter.default.addObserver(self, selector: #selector(handleTestAlert), name: .tikiTimeHourlyAlert, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSettingsChanged), name: .tikiTimeSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCharacterTransfer(_:)), name: .tikiTimeCharacterTransfer, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCrossDragUpdate(_:)), name: .tikiTimeDragUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCrossDragEnd(_:)), name: .tikiTimeDragEnd, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSecondaryDragUpdate(_:)), name: .tikiTimeSecondaryDragUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSecondaryDragEnd(_:)), name: .tikiTimeSecondaryDragEnd, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleTestEmotion), name: .tikiTimeTestEmotion, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleTestDockStairs), name: .tikiTimeTestDockStairs, object: nil)

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.handleGlobalClick()
        }
    }

    override func willMove(from view: SKView) {
        hourlyTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
    }

    // MARK: - Setup

    private func setupMainCharacter(settings: UserSettings) {
        characterNode = makeCharacterNode(manifest: manifest, scale: settings.characterScale, isFlipped: settings.flippedCharacterIds.contains(manifest.id), cache: &emotionTextureCache)
        characterNode.position = CGPoint(x: size.width / 2, y: floorY)
        characterNode.isHidden = !isInitiallyActive
        addChild(characterNode)

        currentFloorY = floorY

        walkBehavior = makeWalkBehavior(startX: characterNode.position.x, speed: manifest.walkSpeed)
        walkBehavior.hasLeftNeighbor = hasLeftNeighbor
        walkBehavior.hasRightNeighbor = hasRightNeighbor
        walkBehavior.onStateChange = { [weak self] state in self?.applyMainState(state) }
        walkBehavior.onTransfer = { [weak self] direction in self?.handleTransferOut(direction: direction) }
    }

    private func setupSecondaryCharacters(settings: UserSettings) {
        let spacing = size.width / CGFloat(settings.secondaryCharacterIds.count + 2)
        for (index, id) in settings.secondaryCharacterIds.enumerated() {
            let m = CharacterSpriteScene.loadManifest(id: id)
            var secCache: [String: SKTexture] = [:]
            let node = makeCharacterNode(manifest: m, scale: settings.characterScale, isFlipped: settings.flippedCharacterIds.contains(m.id), cache: &secCache)
            let startX = spacing * CGFloat(index + 1)
            node.position = CGPoint(x: startX, y: floorY)
            node.isHidden = !isInitiallyActive
            addChild(node)

            let behavior = makeWalkBehavior(startX: startX, speed: m.walkSpeed)
            let capturedIndex = secondaryCharacters.count
            behavior.onStateChange = { [weak self] state in
                guard let self else { return }
                switch state {
                case .idle:
                    self.secondaryCharacters[capturedIndex].node.stopWalk()
                    self.maybeShowSecondaryIdleMessage(index: capturedIndex)
                case .walking(let dir):
                    self.secondaryCharacters[capturedIndex].node.playWalk(direction: dir)
                }
            }

            var sec = SecondaryCharacter(node: node, behavior: behavior, manifest: m, emotionTextureCache: secCache, currentFloorY: floorY)
            sec.nextWalkMessageTime = Double.random(in: 15...35)
            secondaryCharacters.append(sec)
        }
    }

    private func makeCharacterNode(manifest: CharacterManifest, scale: Double, isFlipped: Bool = false, cache: inout [String: SKTexture]) -> CharacterNode {
        let node = CharacterNode()
        if let emoji = manifest.emoji { node.emoji = emoji }
        node.setScale(scale)
        node.isFlipped = isFlipped
        node.footOffsetY = CGFloat(manifest.footOffsetY)
        node.footOffsetX = CGFloat(manifest.footOffsetX)
        if manifest.isImageBased {
            if let texture = loadAnimationFrames(animation: "idle", manifest: manifest).first {
                node.setIdleTexture(texture)
            }
            let walkFrames = loadAnimationFrames(animation: "walk", manifest: manifest)
            if !walkFrames.isEmpty { node.setWalkFrames(walkFrames) }
        }
        return node
    }

    private func loadAnimationFrames(animation: String, manifest: CharacterManifest) -> [SKTexture] {
        guard let paths = manifest.animations[animation] else { return [] }
        return paths.compactMap { path in
            let url = CharacterStorageService.imageURL(characterId: manifest.id, relativePath: path)
            guard let image = NSImage(contentsOf: url) else { return nil }
            return SKTexture(image: image)
        }
    }

    private func makeWalkBehavior(startX: CGFloat, speed: Double) -> WalkBehavior {
        WalkBehavior(startX: startX, sceneBounds: frame, speed: speed)
    }

    // MARK: - Dock jump physics

    private func snappedFloorY(forX x: CGFloat) -> CGFloat {
        guard let dock = dockInfo else { return floorY }
        // 진입 시 15px 선행 마진: 도크 경계에 도달하기 전에 점프 시작
        let entryMargin: CGFloat = 15
        if x >= dock.xRange.lowerBound - entryMargin && x <= dock.xRange.upperBound {
            return floorY + dock.height
        }
        return floorY
    }

    private func applyDockJump(
        targetY: CGFloat,
        currentFloorY: inout CGFloat,
        velocityY: inout CGFloat,
        isPhysics: inout Bool,
        delta: TimeInterval,
        node: CharacterNode
    ) {
        let gravity: CGFloat = -1500
        if isPhysics {
            velocityY += gravity * CGFloat(delta)
            currentFloorY += velocityY * CGFloat(delta)
            if velocityY < 0, currentFloorY <= targetY {
                let speed = abs(velocityY)
                currentFloorY = targetY
                let bounce = speed * 0.22
                if bounce > 25 {
                    velocityY = bounce
                } else {
                    velocityY = 0
                    isPhysics = false
                    if speed > 100 { node.playLand(intensity: speed / 1000) }
                }
            } else if velocityY > 0, currentFloorY >= targetY {
                currentFloorY = targetY
                velocityY = 0
                isPhysics = false
            }
        } else if abs(targetY - currentFloorY) > 2 {
            velocityY = targetY > currentFloorY
                ? sqrt(2.0 * abs(gravity) * (targetY - currentFloorY))
                : 0
            isPhysics = true
        } else {
            currentFloorY = targetY
        }
    }

    // MARK: - Texture helpers

    private func loadTexture(emotion: String, manifest: CharacterManifest, cache: inout [String: SKTexture]) -> SKTexture? {
        if let cached = cache[emotion] { return cached }
        guard manifest.isImageBased, let relativePath = manifest.animations[emotion]?.first else { return nil }
        let url = CharacterStorageService.imageURL(characterId: manifest.id, relativePath: relativePath)
        guard let image = NSImage(contentsOf: url) else { return nil }
        let texture = SKTexture(image: image)
        cache[emotion] = texture
        return texture
    }

    private func loadEmotionFrames(emotion: String) -> [SKTexture] {
        if let cached = emotionFrameCache[emotion] { return cached }
        guard manifest.isImageBased,
              let paths = manifest.animations[emotion], !paths.isEmpty else { return [] }
        let textures = paths.compactMap { path -> SKTexture? in
            let url = CharacterStorageService.imageURL(characterId: manifest.id, relativePath: path)
            guard let image = NSImage(contentsOf: url) else { return nil }
            return SKTexture(image: image)
        }
        if !textures.isEmpty { emotionFrameCache[emotion] = textures }
        return textures
    }

    private func applyEmotion(_ emotion: String) {
        let frames = loadEmotionFrames(emotion: emotion)
        if !frames.isEmpty {
            characterNode.playEmotion(frames)
        }
        if let messages = manifest.stateMessages[emotion], !messages.isEmpty,
           let message = messages.randomElement() {
            characterNode.playIdleMessage(message)
        }
    }

    private func restoreDefaultAppearance() {
        characterNode.stopEmotion()
        if manifest.animations["walk"] != nil,
           let texture = loadTexture(emotion: "walk", manifest: manifest, cache: &emotionTextureCache) {
            characterNode.setEmotionTexture(texture)
        } else {
            applyEmotion("idle")
        }
    }

    private func applyEmotionWithRestore(_ emotion: String) {
        walkBehavior.pause()
        characterNode.stopWalk()
        applyEmotion(emotion)
        let restore = SKAction.run { [weak self] in
            self?.restoreDefaultAppearance()
            self?.walkBehavior.resume()
        }
        characterNode.run(.sequence([.wait(forDuration: 6.0), restore]), withKey: "restoreEmotion")
    }

    // MARK: - Rule-based Emotion

    private func emotionForCurrentContext() -> String {
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let weekday = cal.component(.weekday, from: now) // 1=Sun, 2=Mon, 6=Fri, 7=Sat

        if hour < 3 { return "fearful" }
        if weekday == 2 && hour < 9 { return "sad" }
        if (weekday == 6 && hour >= 18) || weekday == 7 || weekday == 1 { return "happy" }

        return ["happy", "happy", "surprised", "surprised", "sad", "disgusted"].randomElement()!
    }

    // MARK: - State

    private func applyMainState(_ state: WalkState) {
        switch state {
        case .idle:
            characterNode.stopWalk()
            maybeShowIdleMessage()
        case .walking(let direction):
            characterNode.playWalk(direction: direction)
        }
    }

    private func maybeShowIdleMessage() {
        guard !characterNode.isHidden else { return }
        let now = CACurrentMediaTime()
        guard now - lastIdleMessageTime > 30,
              Double.random(in: 0...1) < 0.3
        else { return }
        lastIdleMessageTime = now

        if manifest.isImageBased, Double.random(in: 0...1) < 0.5 {
            applyEmotionWithRestore(emotionForCurrentContext())
        } else {
            let pool = manifest.idleMessages.isEmpty
                ? (manifest.stateMessages["idle"] ?? [])
                : manifest.idleMessages
            if let message = pool.randomElement() {
                characterNode.playIdleMessage(message)
            }
        }
    }

    private func maybeShowWalkMessage(at currentTime: TimeInterval) {
        guard currentTime >= nextWalkMessageTime else { return }
        nextWalkMessageTime = currentTime + Double.random(in: 20...40)
        guard !characterNode.isHidden else { return }
        let pool = manifest.idleMessages.isEmpty
            ? (manifest.stateMessages["idle"] ?? [])
            : manifest.idleMessages
        if let message = pool.randomElement() {
            characterNode.playIdleMessage(message)
        }
    }

    // MARK: - Update Loop

    override func update(_ currentTime: TimeInterval) {
        let delta = lastUpdateTime == 0 ? 0 : min(currentTime - lastUpdateTime, 1.0 / 30.0)
        lastUpdateTime = currentTime

        let mainIsDragging = isDragging && draggingSecondaryIndex == nil
        if !characterNode.isHidden && !mainIsDragging && !isReceivingCrossDrag {
            if isDropping {
                updateDrop(delta: delta)
            } else {
                walkBehavior.update(deltaTime: delta)
                characterNode.position.x = walkBehavior.positionX
                let targetY = snappedFloorY(forX: walkBehavior.positionX)
                applyDockJump(targetY: targetY, currentFloorY: &currentFloorY, velocityY: &dockVelocityY, isPhysics: &isDockPhysics, delta: delta, node: characterNode)
                characterNode.position.y = currentFloorY
                if case .walking = walkBehavior.state {
                    maybeShowWalkMessage(at: currentTime)
                }
            }
        }

        for index in secondaryCharacters.indices where !secondaryCharacters[index].node.isHidden {
            let secIsDragging = isDragging && draggingSecondaryIndex == index
            let secIsReceiving = isReceivingSecondaryDragIndex == index
            guard !secIsDragging && !secIsReceiving else { continue }
            if secondaryCharacters[index].isDropping {
                updateSecondaryDrop(index: index, delta: delta)
            } else {
                secondaryCharacters[index].behavior.update(deltaTime: delta)
                let posX = secondaryCharacters[index].behavior.positionX
                secondaryCharacters[index].node.position.x = posX
                let sTargetY = snappedFloorY(forX: posX)
                var secFloorY = secondaryCharacters[index].currentFloorY
                var secVelocityY = secondaryCharacters[index].dockVelocityY
                var secIsPhysics = secondaryCharacters[index].isDockPhysics
                applyDockJump(targetY: sTargetY, currentFloorY: &secFloorY, velocityY: &secVelocityY, isPhysics: &secIsPhysics, delta: delta, node: secondaryCharacters[index].node)
                secondaryCharacters[index].currentFloorY = secFloorY
                secondaryCharacters[index].dockVelocityY = secVelocityY
                secondaryCharacters[index].isDockPhysics = secIsPhysics
                secondaryCharacters[index].node.position.y = secondaryCharacters[index].currentFloorY
                if case .walking = secondaryCharacters[index].behavior.state {
                    maybeShowSecondaryWalkMessage(index: index, at: currentTime)
                }
            }
        }
    }

    // MARK: - Mouse

    private func characterHitTest(_ pos: CGPoint, at point: CGPoint) -> Bool {
        return point.x >= pos.x - 55 && point.x <= pos.x + 55
            && point.y >= pos.y - 10 && point.y <= pos.y + 200
    }

    func isCharacterHit(at scenePoint: CGPoint) -> Bool {
        if !characterNode.isHidden, characterHitTest(characterNode.position, at: scenePoint) { return true }
        for secondary in secondaryCharacters where !secondary.node.isHidden {
            if characterHitTest(secondary.node.position, at: scenePoint) { return true }
        }
        return false
    }

    override func mouseDown(with event: NSEvent) {
        let loc = event.location(in: self)

        // 보조 캐릭터 우선 검사
        for (index, secondary) in secondaryCharacters.enumerated() {
            guard !secondary.node.isHidden, characterHitTest(secondary.node.position, at: loc) else { continue }
            draggingSecondaryIndex = index
            isDragging = true
            isDragOwner = true
            hasDragged = false
            dragStartLocation = loc
            dragStartCharacterPos = secondary.node.position
            secondaryCharacters[index].isDockPhysics = false
            secondaryCharacters[index].dockVelocityY = 0
            secondaryCharacters[index].isDropping = false
            secondaryCharacters[index].dropVelocity = 0
            return
        }

        guard !characterNode.isHidden, characterHitTest(characterNode.position, at: loc) else { return }
        draggingSecondaryIndex = nil
        isDropping = false
        dropVelocity = 0
        isDockPhysics = false
        dockVelocityY = 0
        isDragging = true
        isDragOwner = true
        crossScreenTargetIndex = nil
        hasDragged = false
        dragStartLocation = loc
        dragStartCharacterPos = characterNode.position
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let loc = event.location(in: self)
        let dx = loc.x - dragStartLocation.x
        let dy = loc.y - dragStartLocation.y

        if let secIdx = draggingSecondaryIndex {
            if !hasDragged, hypot(dx, dy) > dragThreshold {
                hasDragged = true
                secondaryCharacters[secIdx].behavior.pause()
                secondaryCharacters[secIdx].node.stopWalk()
            }
            guard hasDragged else { return }
            let rawX = dragStartCharacterPos.x + dx
            let newY = max(0, min(size.height, dragStartCharacterPos.y + dy))
            if rawX < 0, hasLeftNeighbor {
                secondaryCharacters[secIdx].node.isHidden = true
                crossScreenTargetIndex = screenIndex - 1
                NotificationCenter.default.post(name: .tikiTimeSecondaryDragUpdate, object: nil, userInfo: [
                    "activeScreenIndex": screenIndex - 1,
                    "secondaryIndex": secIdx,
                    "x": size.width + rawX,
                    "y": newY
                ])
            } else if rawX > size.width, hasRightNeighbor {
                secondaryCharacters[secIdx].node.isHidden = true
                crossScreenTargetIndex = screenIndex + 1
                NotificationCenter.default.post(name: .tikiTimeSecondaryDragUpdate, object: nil, userInfo: [
                    "activeScreenIndex": screenIndex + 1,
                    "secondaryIndex": secIdx,
                    "x": rawX - size.width,
                    "y": newY
                ])
            } else {
                let newX = max(0, min(size.width, rawX))
                secondaryCharacters[secIdx].node.isHidden = false
                if crossScreenTargetIndex != nil {
                    crossScreenTargetIndex = nil
                    NotificationCenter.default.post(name: .tikiTimeSecondaryDragUpdate, object: nil, userInfo: [
                        "activeScreenIndex": screenIndex,
                        "secondaryIndex": secIdx,
                        "x": newX,
                        "y": newY
                    ])
                }
                secondaryCharacters[secIdx].node.position = CGPoint(x: newX, y: newY)
                secondaryCharacters[secIdx].behavior.positionX = newX
                secondaryCharacters[secIdx].currentFloorY = newY
            }
            return
        }

        if !hasDragged, hypot(dx, dy) > dragThreshold {
            hasDragged = true
            walkBehavior.pause()
            characterNode.stopWalk()
        }
        guard hasDragged else { return }
        let rawX = dragStartCharacterPos.x + dx
        let newY = max(0, min(size.height, dragStartCharacterPos.y + dy))

        if rawX < 0, hasLeftNeighbor {
            characterNode.isHidden = true
            crossScreenTargetIndex = screenIndex - 1
            NotificationCenter.default.post(name: .tikiTimeDragUpdate, object: nil, userInfo: [
                "activeScreenIndex": screenIndex - 1,
                "x": size.width + rawX,
                "y": newY
            ])
        } else if rawX > size.width, hasRightNeighbor {
            characterNode.isHidden = true
            crossScreenTargetIndex = screenIndex + 1
            NotificationCenter.default.post(name: .tikiTimeDragUpdate, object: nil, userInfo: [
                "activeScreenIndex": screenIndex + 1,
                "x": rawX - size.width,
                "y": newY
            ])
        } else {
            let newX = max(0, min(size.width, rawX))
            characterNode.isHidden = false
            if crossScreenTargetIndex != nil {
                crossScreenTargetIndex = nil
                NotificationCenter.default.post(name: .tikiTimeDragUpdate, object: nil, userInfo: [
                    "activeScreenIndex": screenIndex,
                    "x": newX,
                    "y": newY
                ])
            }
            characterNode.position = CGPoint(x: newX, y: newY)
            walkBehavior.positionX = newX
            currentFloorY = newY
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        isDragOwner = false

        if let secIdx = draggingSecondaryIndex {
            draggingSecondaryIndex = nil
            if hasDragged {
                if let targetIndex = crossScreenTargetIndex {
                    crossScreenTargetIndex = nil
                    NotificationCenter.default.post(name: .tikiTimeSecondaryDragEnd, object: nil, userInfo: [
                        "targetIndex": targetIndex,
                        "secondaryIndex": secIdx
                    ])
                } else {
                    let finalX = secondaryCharacters[secIdx].node.position.x
                    secondaryCharacters[secIdx].behavior.positionX = finalX
                    let floorTarget = snappedFloorY(forX: finalX)
                    if secondaryCharacters[secIdx].node.position.y > floorTarget + 2 {
                        secondaryCharacters[secIdx].isDropping = true
                        secondaryCharacters[secIdx].dropVelocity = 0
                        secondaryCharacters[secIdx].currentFloorY = secondaryCharacters[secIdx].node.position.y
                    } else {
                        secondaryCharacters[secIdx].currentFloorY = floorTarget
                        secondaryCharacters[secIdx].node.position = CGPoint(x: finalX, y: floorTarget)
                        secondaryCharacters[secIdx].behavior.resume()
                    }
                }
            } else {
                triggerSecondaryInteraction(index: secIdx)
            }
            return
        }

        if hasDragged {
            if let targetIndex = crossScreenTargetIndex {
                crossScreenTargetIndex = nil
                NotificationCenter.default.post(name: .tikiTimeDragEnd, object: nil, userInfo: [
                    "targetIndex": targetIndex
                ])
            } else {
                let finalX = characterNode.position.x
                walkBehavior.positionX = finalX
                let floorTarget = snappedFloorY(forX: finalX)
                if characterNode.position.y > floorTarget + 2 {
                    isDropping = true
                    dropVelocity = 0
                    currentFloorY = characterNode.position.y
                } else {
                    currentFloorY = floorTarget
                    characterNode.position = CGPoint(x: finalX, y: currentFloorY)
                    walkBehavior.resume()
                }
            }
        } else {
            triggerAIInteraction()
        }
    }

    // MARK: - Drop Physics

    private func updateDrop(delta: TimeInterval) {
        dropVelocity += dropGravity * CGFloat(delta)
        currentFloorY += dropVelocity * CGFloat(delta)
        let floorTarget = snappedFloorY(forX: walkBehavior.positionX)

        if currentFloorY <= floorTarget {
            let impactSpeed = abs(dropVelocity)
            currentFloorY = floorTarget
            let bounce = impactSpeed * weightedBounce()
            characterNode.playLand(intensity: impactSpeed / 900)
            if bounce > 25 {
                dropVelocity = bounce
            } else {
                isDropping = false
                dropVelocity = 0
                walkBehavior.resume()
            }
        }
        characterNode.position = CGPoint(x: walkBehavior.positionX, y: currentFloorY)
    }

    private func weightedBounce(node: CharacterNode? = nil) -> CGFloat {
        let area = (node ?? characterNode).physicsSize.width * (node ?? characterNode).physicsSize.height
        let normalized = min(area / 32400, 1.0) // 180×180 = 1.0
        return dropBounce * (1 - normalized * 0.6)
    }

    private func updateSecondaryDrop(index: Int, delta: TimeInterval) {
        secondaryCharacters[index].dropVelocity += dropGravity * CGFloat(delta)
        secondaryCharacters[index].currentFloorY += secondaryCharacters[index].dropVelocity * CGFloat(delta)
        let posX = secondaryCharacters[index].behavior.positionX
        let floorTarget = snappedFloorY(forX: posX)
        if secondaryCharacters[index].currentFloorY <= floorTarget {
            let impactSpeed = abs(secondaryCharacters[index].dropVelocity)
            secondaryCharacters[index].currentFloorY = floorTarget
            let bounce = impactSpeed * weightedBounce(node: secondaryCharacters[index].node)
            secondaryCharacters[index].node.playLand(intensity: impactSpeed / 900)
            if bounce > 25 {
                secondaryCharacters[index].dropVelocity = bounce
            } else {
                secondaryCharacters[index].isDropping = false
                secondaryCharacters[index].dropVelocity = 0
                secondaryCharacters[index].behavior.resume()
            }
        }
        secondaryCharacters[index].node.position = CGPoint(x: posX, y: secondaryCharacters[index].currentFloorY)
    }

    private func handleGlobalClick() {
        guard let view else { return }
        let screenPoint = NSEvent.mouseLocation
        guard let windowPoint = view.window?.convertPoint(fromScreen: screenPoint) else { return }
        let viewPoint = view.convert(windowPoint, from: nil)
        let scenePoint = convertPoint(fromView: viewPoint)

        if !characterNode.isHidden {
            let hit = nodes(at: scenePoint).contains { $0.name == "character" || $0.name == "speechBubble" }
            if hit { triggerAIInteraction(); return }
        }

        for (index, secondary) in secondaryCharacters.enumerated() where !secondary.node.isHidden {
            if characterHitTest(secondary.node.position, at: scenePoint) {
                triggerSecondaryInteraction(index: index)
                return
            }
        }
    }

    private func triggerSecondaryInteraction(index: Int) {
        let secondary = secondaryCharacters[index]
        let settings = UserSettings.load()
        guard let apiKey = KeychainService.loadAPIKey(for: settings.aiProvider), !apiKey.isEmpty else {
            if secondary.manifest.isImageBased {
                applySecondaryEmotionWithRestore(index: index, emotion: emotionForCurrentContext())
            } else {
                secondaryCharacters[index].behavior.pause()
                secondaryCharacters[index].node.stopWalk()
                let resume = SKAction.run { [weak self] in self?.secondaryCharacters[index].behavior.resume() }
                secondaryCharacters[index].node.run(.sequence([.wait(forDuration: 3.5), resume]), withKey: "messageResume")
            }
            let pool = (secondary.manifest.stateMessages["idle"] ?? []) + secondary.manifest.idleMessages
            if let message = pool.randomElement() { secondary.node.playIdleMessage(message) }
            return
        }
        let client = AIAPIClient(apiKey: apiKey, provider: settings.aiProvider)
        let hour = Calendar.current.component(.hour, from: Date())
        Task { @MainActor [weak self] in
            guard let self, index < self.secondaryCharacters.count else { return }
            guard let raw = try? await client.respond(to: "지금은 \(hour)시 클릭해서 반응해줘!") else { return }
            let parsed = AIAPIClient.AIResponse.parse(raw)
            if self.secondaryCharacters[index].manifest.isImageBased {
                self.applySecondaryEmotionWithRestore(index: index, emotion: parsed.emotion)
            } else {
                self.secondaryCharacters[index].behavior.pause()
                self.secondaryCharacters[index].node.stopWalk()
                let resume = SKAction.run { [weak self] in self?.secondaryCharacters[index].behavior.resume() }
                self.secondaryCharacters[index].node.run(.sequence([.wait(forDuration: 6.0), resume]), withKey: "messageResume")
            }
            self.secondaryCharacters[index].node.playAIResponse(parsed.text)
        }
    }

    private func applySecondaryEmotionWithRestore(index: Int, emotion: String) {
        guard index < secondaryCharacters.count else { return }
        secondaryCharacters[index].behavior.pause()
        secondaryCharacters[index].node.stopWalk()
        let frames = loadSecondaryEmotionFrames(index: index, emotion: emotion)
        if !frames.isEmpty {
            secondaryCharacters[index].node.playEmotion(frames)
        }
        if let messages = secondaryCharacters[index].manifest.stateMessages[emotion],
           let message = messages.randomElement() {
            secondaryCharacters[index].node.playIdleMessage(message)
        }
        let restore = SKAction.run { [weak self] in
            guard let self, index < self.secondaryCharacters.count else { return }
            self.secondaryCharacters[index].node.stopEmotion()
            if let texture = self.loadSecondaryTexture(index: index, emotion: "idle") {
                self.secondaryCharacters[index].node.setEmotionTexture(texture)
            }
            self.secondaryCharacters[index].behavior.resume()
        }
        secondaryCharacters[index].node.run(.sequence([.wait(forDuration: 6.0), restore]), withKey: "restoreEmotion")
    }

    private func loadSecondaryEmotionFrames(index: Int, emotion: String) -> [SKTexture] {
        if let cached = secondaryCharacters[index].emotionFrameCache[emotion] { return cached }
        let manifest = secondaryCharacters[index].manifest
        guard manifest.isImageBased, let paths = manifest.animations[emotion], !paths.isEmpty else { return [] }
        let textures = paths.compactMap { path -> SKTexture? in
            let url = CharacterStorageService.imageURL(characterId: manifest.id, relativePath: path)
            guard let image = NSImage(contentsOf: url) else { return nil }
            return SKTexture(image: image)
        }
        if !textures.isEmpty { secondaryCharacters[index].emotionFrameCache[emotion] = textures }
        return textures
    }

    private func loadSecondaryTexture(index: Int, emotion: String) -> SKTexture? {
        return loadTexture(emotion: emotion, manifest: secondaryCharacters[index].manifest, cache: &secondaryCharacters[index].emotionTextureCache)
    }

    private func maybeShowSecondaryIdleMessage(index: Int) {
        guard index < secondaryCharacters.count, !secondaryCharacters[index].node.isHidden else { return }
        let now = CACurrentMediaTime()
        guard now - secondaryCharacters[index].lastIdleMessageTime > 30,
              Double.random(in: 0...1) < 0.3 else { return }
        secondaryCharacters[index].lastIdleMessageTime = now
        let manifest = secondaryCharacters[index].manifest
        if manifest.isImageBased, Double.random(in: 0...1) < 0.5 {
            applySecondaryEmotionWithRestore(index: index, emotion: emotionForCurrentContext())
        } else {
            let pool = manifest.idleMessages.isEmpty
                ? (manifest.stateMessages["idle"] ?? [])
                : manifest.idleMessages
            if let message = pool.randomElement() {
                secondaryCharacters[index].node.playIdleMessage(message)
            }
        }
    }

    private func maybeShowSecondaryWalkMessage(index: Int, at currentTime: TimeInterval) {
        guard secondaryCharacters[index].nextWalkMessageTime > 0,
              currentTime >= secondaryCharacters[index].nextWalkMessageTime else { return }
        secondaryCharacters[index].nextWalkMessageTime = currentTime + Double.random(in: 20...40)
        guard !secondaryCharacters[index].node.isHidden else { return }
        let manifest = secondaryCharacters[index].manifest
        let pool = manifest.idleMessages.isEmpty
            ? (manifest.stateMessages["idle"] ?? [])
            : manifest.idleMessages
        if let message = pool.randomElement() {
            secondaryCharacters[index].node.playIdleMessage(message)
        }
    }

    private func pauseWalkForMessage(duration: TimeInterval) {
        walkBehavior.pause()
        characterNode.stopWalk()
        let resume = SKAction.run { [weak self] in self?.walkBehavior.resume() }
        characterNode.run(.sequence([.wait(forDuration: duration), resume]), withKey: "messageResume")
    }

    private func triggerAIInteraction() {
        let settings = UserSettings.load()
        guard let apiKey = KeychainService.loadAPIKey(for: settings.aiProvider), !apiKey.isEmpty else {
            if manifest.isImageBased {
                applyEmotionWithRestore(emotionForCurrentContext())
            } else {
                pauseWalkForMessage(duration: 3.5)
            }
            let pool = (manifest.stateMessages["idle"] ?? []) + manifest.idleMessages
            if let message = pool.randomElement() {
                characterNode.playIdleMessage(message)
            }
            return
        }
        let client = AIAPIClient(apiKey: apiKey, provider: settings.aiProvider)
        let hour = Calendar.current.component(.hour, from: Date())
        let timeContext = "\(hour)시"
        Task { @MainActor in
            guard let raw = try? await client.respond(to: "지금은 \(timeContext) 클릭해서 반응해줘!") else { return }
            let parsed = AIAPIClient.AIResponse.parse(raw)
            if manifest.isImageBased {
                applyEmotionWithRestore(parsed.emotion)
            } else {
                pauseWalkForMessage(duration: 6.0)
            }
            characterNode.playAIResponse(parsed.text)
        }
    }

    // MARK: - Transfer (main character only)

    private func handleTransferOut(direction: WalkDirection) {
        walkBehavior.pause()
        characterNode.isHidden = true
        NotificationCenter.default.post(
            name: .tikiTimeCharacterTransfer,
            object: nil,
            userInfo: ["fromScreenIndex": screenIndex, "direction": direction == .right ? "right" : "left"]
        )
    }

    @objc private func handleCrossDragUpdate(_ notification: Notification) {
        guard !isDragging else { return }
        guard let userInfo = notification.userInfo,
              let activeIndex = userInfo["activeScreenIndex"] as? Int
        else { return }

        if activeIndex == screenIndex {
            let x = userInfo["x"] as? CGFloat ?? characterNode.position.x
            let y = userInfo["y"] as? CGFloat ?? characterNode.position.y
            characterNode.isHidden = false
            isReceivingCrossDrag = true
            walkBehavior.pause()
            characterNode.position = CGPoint(x: max(0, min(size.width, x)), y: max(0, min(size.height, y)))
            walkBehavior.positionX = characterNode.position.x
            currentFloorY = characterNode.position.y
        } else if isReceivingCrossDrag {
            isReceivingCrossDrag = false
            characterNode.isHidden = true
        }
    }

    @objc private func handleCrossDragEnd(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let targetIndex = userInfo["targetIndex"] as? Int,
              targetIndex == screenIndex
        else { return }

        isReceivingCrossDrag = false
        let finalX = characterNode.position.x
        walkBehavior.positionX = finalX
        let floorTarget = snappedFloorY(forX: finalX)
        if characterNode.position.y > floorTarget + 2 {
            isDropping = true
            dropVelocity = 0
            currentFloorY = characterNode.position.y
        } else {
            currentFloorY = floorTarget
            characterNode.position = CGPoint(x: finalX, y: currentFloorY)
            walkBehavior.resume()
        }
    }

    @objc private func handleSecondaryDragUpdate(_ notification: Notification) {
        guard !isDragging else { return }
        guard let userInfo = notification.userInfo,
              let activeIndex = userInfo["activeScreenIndex"] as? Int,
              let secIdx = userInfo["secondaryIndex"] as? Int,
              secIdx < secondaryCharacters.count
        else { return }

        if activeIndex == screenIndex {
            let x = userInfo["x"] as? CGFloat ?? secondaryCharacters[secIdx].node.position.x
            let y = userInfo["y"] as? CGFloat ?? secondaryCharacters[secIdx].node.position.y
            secondaryCharacters[secIdx].node.isHidden = false
            isReceivingSecondaryDragIndex = secIdx
            secondaryCharacters[secIdx].behavior.pause()
            secondaryCharacters[secIdx].node.position = CGPoint(x: max(0, min(size.width, x)), y: max(0, min(size.height, y)))
            secondaryCharacters[secIdx].behavior.positionX = secondaryCharacters[secIdx].node.position.x
            secondaryCharacters[secIdx].currentFloorY = secondaryCharacters[secIdx].node.position.y
        } else if isReceivingSecondaryDragIndex == secIdx {
            isReceivingSecondaryDragIndex = nil
            secondaryCharacters[secIdx].node.isHidden = true
        }
    }

    @objc private func handleSecondaryDragEnd(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let targetIndex = userInfo["targetIndex"] as? Int,
              let secIdx = userInfo["secondaryIndex"] as? Int,
              targetIndex == screenIndex,
              secIdx < secondaryCharacters.count
        else { return }

        isReceivingSecondaryDragIndex = nil
        let finalX = secondaryCharacters[secIdx].node.position.x
        secondaryCharacters[secIdx].behavior.positionX = finalX
        let floorTarget = snappedFloorY(forX: finalX)
        if secondaryCharacters[secIdx].node.position.y > floorTarget + 2 {
            secondaryCharacters[secIdx].isDropping = true
            secondaryCharacters[secIdx].dropVelocity = 0
            secondaryCharacters[secIdx].currentFloorY = secondaryCharacters[secIdx].node.position.y
        } else {
            secondaryCharacters[secIdx].currentFloorY = floorTarget
            secondaryCharacters[secIdx].node.position = CGPoint(x: finalX, y: floorTarget)
            secondaryCharacters[secIdx].behavior.resume()
        }
    }

    @objc private func handleCharacterTransfer(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let fromIndex = userInfo["fromScreenIndex"] as? Int,
              let dirString = userInfo["direction"] as? String
        else { return }

        let direction: WalkDirection = dirString == "right" ? .right : .left
        let targetIndex = direction == .right ? fromIndex + 1 : fromIndex - 1
        guard targetIndex == screenIndex else { return }

        characterNode.isHidden = false
        walkBehavior.enterFromEdge(traveling: direction)
    }

    // MARK: - Hourly Animation

    private func scheduleHourlyAnimation() {
        let now = Date()
        let next = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(3600)

        DispatchQueue.main.asyncAfter(deadline: .now() + next.timeIntervalSinceNow) { [weak self] in
            self?.triggerHourlyAnimation()
            self?.hourlyTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
                self?.triggerHourlyAnimation()
            }
        }
    }

    private func triggerHourlyAnimation() {
        guard !characterNode.isHidden else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        let message: String
        if !manifest.hourlyGreetings.isEmpty {
            message = manifest.hourlyGreetings[min(hour, manifest.hourlyGreetings.count - 1)]
        } else if let custom = UserSettings.load().hourlyMessages.randomElement() {
            message = custom
        } else {
            return
        }
        walkBehavior.pause()
        characterNode.playHourlyMessage(message) { [weak self] in
            self?.walkBehavior.resume()
        }
    }

    @objc private func handleTestAlert() { triggerHourlyAnimation() }

    @objc private func handleTestEmotion(_ notification: Notification) {
        guard !characterNode.isHidden else { return }
        let emotion = (notification.userInfo?["emotion"] as? String) ?? emotionForCurrentContext()
        if manifest.isImageBased {
            applyEmotionWithRestore(emotion)
        } else {
            let pool = manifest.stateMessages[emotion] ?? manifest.stateMessages["idle"] ?? manifest.idleMessages
            let message = pool.randomElement() ?? "감정: \(emotion)"
            characterNode.playIdleMessage(message)
        }
    }

    @objc private func handleTestDockStairs() {
        guard let s = screen else { return }

        // 이 화면에 Dock이 없으면 캐릭터 숨김
        let dockHeight = s.visibleFrame.minY - s.frame.minY
        guard dockHeight > 0 else {
            walkBehavior.pause()
            characterNode.isHidden = true
            return
        }

        dockInfo = DockDetector.detect(on: s)
        characterNode.isHidden = false
        currentFloorY = floorY
        characterNode.position = CGPoint(x: 10, y: floorY)

        guard let dock = dockInfo else {
            characterNode.playIdleMessage(DockDetector.debugSummary(on: s))
            walkBehavior.pause()
            return
        }
        let info = "h:\(Int(dock.height)) x:\(Int(dock.xRange.lowerBound))~\(Int(dock.xRange.upperBound))"
        characterNode.playIdleMessage(info)

        // Dock 바로 왼쪽 근처에서 시작해 계단 오르내림이 즉시 보이게
        let startX = max(0, dock.xRange.lowerBound - 80)
        currentFloorY = snappedFloorY(forX: startX)
        characterNode.position = CGPoint(x: startX, y: currentFloorY)
        walkBehavior.beginForcedRoundTrip(from: startX) { [weak self] in
            self?.characterNode.isHidden = false
        }
    }

    @objc private func handleSettingsChanged() {
        let settings = UserSettings.load()
        manifest = CharacterSpriteScene.loadManifest(id: manifest.id)
        characterNode.footOffsetY = CGFloat(manifest.footOffsetY)
        characterNode.footOffsetX = CGFloat(manifest.footOffsetX)
        if let emoji = manifest.emoji { characterNode.emoji = emoji }
        characterNode.setScale(settings.characterScale)
        characterNode.isFlipped = settings.flippedCharacterIds.contains(manifest.id)
        walkBehavior.updateSpeed(manifest.walkSpeed)
        for (i, secondary) in secondaryCharacters.enumerated() {
            let updatedManifest = CharacterSpriteScene.loadManifest(id: secondary.manifest.id)
            secondaryCharacters[i].node.footOffsetY = CGFloat(updatedManifest.footOffsetY)
            secondaryCharacters[i].node.footOffsetX = CGFloat(updatedManifest.footOffsetX)
            secondary.node.setScale(settings.characterScale)
            secondaryCharacters[i].node.isFlipped = settings.flippedCharacterIds.contains(secondary.manifest.id)
            secondary.behavior.updateSpeed(updatedManifest.walkSpeed)
        }
    }

}
