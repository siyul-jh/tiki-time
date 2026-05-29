import Foundation

public struct Character: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let displayName: String
    public let isPremium: Bool
    public let animations: [String: String]

    public init(id: String, name: String, displayName: String, isPremium: Bool, animations: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.isPremium = isPremium
        self.animations = animations
    }
}

public struct CharacterManifest: Identifiable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public let version: String
    public let emoji: String?
    public let isImageBased: Bool
    public let animations: [String: [String]]  // state name -> [frame relative paths]
    public let stateMessages: [String: [String]]  // state name -> possible messages
    public let footOffsetY: Double  // 200×200 프레임 하단에서 발까지의 Y 여백(px)
    public let footOffsetX: Double  // 캐릭터 X축 오프셋(px), 기본값 0
    public let walkSpeed: Double    // 이동 속도 (pt/s), 기본값 70
    public let hourlyGreetings: [String]
    public let idleMessages: [String]

    public init(
        id: String,
        displayName: String,
        version: String,
        emoji: String? = nil,
        isImageBased: Bool = false,
        animations: [String: [String]] = [:],
        stateMessages: [String: [String]] = [:],
        footOffsetY: Double = 0,
        footOffsetX: Double = 0,
        walkSpeed: Double = 70,
        hourlyGreetings: [String] = [],
        idleMessages: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.emoji = emoji
        self.isImageBased = isImageBased
        self.animations = animations
        self.stateMessages = stateMessages
        self.footOffsetY = footOffsetY
        self.footOffsetX = footOffsetX
        self.walkSpeed = walkSpeed
        self.hourlyGreetings = hourlyGreetings
        self.idleMessages = idleMessages
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        version = try c.decode(String.self, forKey: .version)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        isImageBased = try c.decodeIfPresent(Bool.self, forKey: .isImageBased) ?? false

        var anims = try c.decodeIfPresent([String: [String]].self, forKey: .animations) ?? [:]
        // Migrate old emotions format: {"idle": "emotions/idle.png"} -> {"idle": ["emotions/idle.png"]}
        if let oldEmotions = try? c.decode([String: String].self, forKey: .emotions) {
            for (key, path) in oldEmotions where anims[key] == nil {
                anims[key] = [path]
            }
        }
        animations = anims

        stateMessages = try c.decodeIfPresent([String: [String]].self, forKey: .stateMessages) ?? [:]
        footOffsetY = try c.decodeIfPresent(Double.self, forKey: .footOffsetY) ?? 0
        footOffsetX = try c.decodeIfPresent(Double.self, forKey: .footOffsetX) ?? 0
        walkSpeed = try c.decodeIfPresent(Double.self, forKey: .walkSpeed) ?? 70
        hourlyGreetings = try c.decodeIfPresent([String].self, forKey: .hourlyGreetings) ?? []
        idleMessages = try c.decodeIfPresent([String].self, forKey: .idleMessages) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(version, forKey: .version)
        try c.encodeIfPresent(emoji, forKey: .emoji)
        try c.encode(isImageBased, forKey: .isImageBased)
        try c.encode(animations, forKey: .animations)
        try c.encode(stateMessages, forKey: .stateMessages)
        try c.encode(footOffsetY, forKey: .footOffsetY)
        try c.encode(footOffsetX, forKey: .footOffsetX)
        try c.encode(walkSpeed, forKey: .walkSpeed)
        try c.encode(hourlyGreetings, forKey: .hourlyGreetings)
        try c.encode(idleMessages, forKey: .idleMessages)
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, version, emoji, isImageBased, animations, emotions
        case stateMessages, footOffsetY, footOffsetX, walkSpeed, hourlyGreetings, idleMessages
    }
}
