import SpriteKit

final class CharacterNode: SKNode {
    private let body = SKLabelNode()
    private var imageNode: SKSpriteNode?
    private var speechBubble: SKNode?

    private var idleTexture: SKTexture?
    private var walkFrameTextures: [SKTexture] = []

    var emoji: String = "🐈‍⬛" {
        didSet { body.text = emoji }
    }

    override init() {
        super.init()
        setup()
    }

    required init?(coder aDecoder: NSCoder) { nil }

    private func setup() {
        body.fontSize = 64
        body.text = emoji
        body.name = "character"
        body.verticalAlignmentMode = .center
        body.horizontalAlignmentMode = .center
        addChild(body)
    }

    // MARK: - Image Mode

    func setIdleTexture(_ texture: SKTexture) {
        idleTexture = texture
        setEmotionTexture(texture)
    }

    func setEmotionTexture(_ texture: SKTexture) {
        let size = aspectFitSize(texture.size(), maxDimension: 180)
        if let existing = imageNode {
            existing.texture = texture
            existing.size = size
        } else {
            let node = SKSpriteNode(texture: texture, size: size)
            node.name = "character"
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            imageNode = node
            addChild(node)
            body.isHidden = true
        }
        applyFootOffset()
    }

    private func aspectFitSize(_ original: CGSize, maxDimension: CGFloat) -> CGSize {
        guard original.width > 0, original.height > 0 else {
            return CGSize(width: maxDimension, height: maxDimension)
        }
        let scale = maxDimension / max(original.width, original.height)
        return CGSize(width: original.width * scale, height: original.height * scale)
    }

    func setWalkFrames(_ textures: [SKTexture]) {
        walkFrameTextures = textures
        if let first = textures.first {
            setEmotionTexture(first)
        }
    }

    // MARK: - Foot offset

    var footOffsetY: CGFloat = 0 { didSet { applyFootOffset() } }
    var footOffsetX: CGFloat = 0 { didSet { applyFootOffset() } }

    private func applyFootOffset() {
        if let node = imageNode {
            let scale = node.size.height / 200.0
            node.position = CGPoint(x: footOffsetX * scale, y: -footOffsetY * scale)
        } else {
            body.position = CGPoint(x: footOffsetX, y: -footOffsetY)
        }
    }

    // MARK: - Direction

    var isFlipped: Bool = false

    func face(_ direction: WalkDirection) {
        var scale: CGFloat = direction == .right ? -1.0 : 1.0
        if isFlipped { scale = -scale }
        body.xScale = scale
        imageNode?.xScale = scale
    }

    // MARK: - Animations

    func playWalk(direction: WalkDirection) {
        face(direction)
        if !walkFrameTextures.isEmpty, let node = imageNode {
            guard node.action(forKey: "walk") == nil else { return }
            let anim = SKAction.animate(with: walkFrameTextures, timePerFrame: 0.12, resize: false, restore: false)
            node.run(.repeatForever(anim), withKey: "walk")
        } else {
            body.removeAction(forKey: "bob")
            let up = SKAction.moveBy(x: 0, y: 6, duration: 0.18)
            let down = SKAction.moveBy(x: 0, y: -6, duration: 0.18)
            up.timingMode = .easeInEaseOut
            down.timingMode = .easeInEaseOut
            body.run(SKAction.repeatForever(.sequence([up, down])), withKey: "bob")
        }
    }

    func stopWalk() {
        if let node = imageNode {
            node.removeAction(forKey: "walk")
            let restoreTexture = walkFrameTextures.first ?? idleTexture
            if let t = restoreTexture { node.texture = t }
        } else {
            body.removeAction(forKey: "bob")
            body.run(SKAction.moveTo(y: -footOffsetY, duration: 0.08))
        }
    }

    func playHourlyMessage(_ text: String, completion: @escaping () -> Void) {
        stopWalk()
        showSpeechBubble(text: text)
        spawnSparkles()
        let finish = SKAction.run { [weak self] in
            self?.hideSpeechBubble()
            completion()
        }
        run(.sequence([.wait(forDuration: 4.0), finish]), withKey: "hourlyMessage")
    }

    func playIdleMessage(_ text: String) {
        showSpeechBubble(text: text)
        let hide = SKAction.run { [weak self] in self?.hideSpeechBubble() }
        run(.sequence([.wait(forDuration: 3.5), hide]), withKey: "idleMessage")
    }

    func playAIResponse(_ text: String) {
        removeAction(forKey: "idleMessage")
        showSpeechBubble(text: text)
        let hide = SKAction.run { [weak self] in self?.hideSpeechBubble() }
        run(.sequence([.wait(forDuration: 6.0), hide]), withKey: "aiResponse")
    }

    var physicsSize: CGSize {
        imageNode?.size ?? CGSize(width: 64, height: 64)
    }

    func playLand(intensity: CGFloat) {
        let clamped = max(0.05, min(intensity, 0.6))
        let target: SKNode = imageNode ?? body
        target.removeAction(forKey: "land")
        let sign: CGFloat = target.xScale < 0 ? -1.0 : 1.0
        let squash = SKAction.scaleX(to: sign * (1 + clamped * 0.9), y: 1 - clamped * 0.5, duration: 0.06)
        let restore = SKAction.scaleX(to: sign * 1.0, y: 1.0, duration: 0.14)
        squash.timingMode = .easeOut
        restore.timingMode = .easeIn
        target.run(.sequence([squash, restore]), withKey: "land")
    }

    func playEmotion(_ textures: [SKTexture]) {
        guard let node = imageNode, let first = textures.first else { return }
        node.removeAction(forKey: "walk")
        node.removeAction(forKey: "emotion")
        node.texture = first
        node.size = aspectFitSize(first.size(), maxDimension: 180)
        applyFootOffset()
        guard textures.count > 1 else { return }
        let anim = SKAction.animate(with: textures, timePerFrame: 0.08, resize: false, restore: false)
        node.run(.repeatForever(anim), withKey: "emotion")
    }

    func stopEmotion() {
        imageNode?.removeAction(forKey: "emotion")
    }


    // MARK: - Speech Bubble

    private func showSpeechBubble(text: String) {
        hideSpeechBubble()

        let label = SKLabelNode(text: text)
        label.fontSize = 13
        label.fontColor = .black
        label.fontName = "AppleSDGothicNeo-Regular"
        label.numberOfLines = 1  // 한 줄 고정, \n 사용 시 numberOfLines=0으로 자동 처리
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        // \n 포함 시 멀티라인 허용
        if label.text?.contains("\n") == true { label.numberOfLines = 0 }

        let padding: CGFloat = 10
        let w = max(label.frame.width + padding * 2, 80)
        let h = label.frame.height + padding * 2

        let bg = SKShapeNode(rect: CGRect(x: -w/2, y: -h/2, width: w, height: h), cornerRadius: 10)
        bg.fillColor = SKColor.white
        bg.strokeColor = SKColor.lightGray
        bg.lineWidth = 1.5

        let bubble = SKNode()
        bubble.name = "speechBubble"
        bubble.addChild(bg)
        bubble.addChild(label)
        // footOffset에 따른 버블 위치 반영 (X/Y 모두)
        let bubbleX: CGFloat = imageNode?.position.x ?? body.position.x
        let bubbleY: CGFloat
        if let node = imageNode {
            bubbleY = node.position.y + node.size.height / 2 + h / 2 + 10
        } else {
            bubbleY = body.position.y + 62
        }
        bubble.position = CGPoint(x: bubbleX, y: bubbleY)
        // characterScale에 관계없이 대사 크기 고정 (counter-scale)
        let nodeScale = abs(xScale)
        if nodeScale > 0.01 { bubble.setScale(1.0 / nodeScale) }
        bubble.alpha = 0
        addChild(bubble)
        bubble.run(.fadeIn(withDuration: 0.25))
        speechBubble = bubble
    }

    private func hideSpeechBubble() {
        guard let bubble = speechBubble else { return }
        speechBubble = nil
        bubble.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
    }

    // MARK: - Particles

    private func spawnSparkles() {
        let sparkles = ["✨", "⭐", "🌟"]
        for _ in 0..<6 {
            let node = SKLabelNode(text: sparkles.randomElement()!)
            node.fontSize = 18
            let offsetX = CGFloat.random(in: -50...50)
            let offsetY = CGFloat.random(in: 10...50)
            node.position = CGPoint(x: offsetX, y: offsetY)
            addChild(node)
            node.run(.sequence([
                .group([
                    .moveBy(x: CGFloat.random(in: -20...20), y: 55, duration: 1.0),
                    .fadeOut(withDuration: 1.0),
                    .scale(to: 0.3, duration: 1.0)
                ]),
                .removeFromParent()
            ]))
        }
    }
}
