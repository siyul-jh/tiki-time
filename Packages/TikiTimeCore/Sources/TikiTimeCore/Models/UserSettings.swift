import Foundation

public struct UserSettings: Codable, Sendable {
    public var mainCharacterId: String
    public var secondaryCharacterIds: [String]  // max 5 (total max 6)
    public var flippedCharacterIds: [String]
    public var isHourlyNotificationEnabled: Bool
    public var notificationSound: String  // "default", "none", "Tink", "Ping", "Glass", "Bottle"
    public var characterScale: Double
    public var walkSpeed: WalkSpeed
    public var aiProvider: AIProvider
    public var geminiImageModel: String
    public var hourlyMessages: [String]

    public static let defaultHourlyMessages: [String] = [
        "정각이야. 잠깐 멈추고 쉬어. ☕",
        "시간 참 빠르다. 벌써 이만큼이나 지났어. 🕐",
        "목마르기 전에 물 한 잔 마셔. 💧",
        "지금 잘하고 있어. 그러니까 조금만 더 힘내. 🎉",
        "정각이네. 몸 굳기 전에 스트레칭 한번 해봐. 🤸"
    ]

    public init(
        mainCharacterId: String = "default",
        secondaryCharacterIds: [String] = [],
        flippedCharacterIds: [String] = [],
        isHourlyNotificationEnabled: Bool = true,
        notificationSound: String = "default",
        characterScale: Double = 1.0,
        walkSpeed: WalkSpeed = .normal,
        aiProvider: AIProvider = .anthropic,
        geminiImageModel: String = "gemini-2.5-flash-image",
        hourlyMessages: [String] = UserSettings.defaultHourlyMessages
    ) {
        self.mainCharacterId = mainCharacterId
        self.secondaryCharacterIds = secondaryCharacterIds
        self.flippedCharacterIds = flippedCharacterIds
        self.isHourlyNotificationEnabled = isHourlyNotificationEnabled
        self.notificationSound = notificationSound
        self.characterScale = characterScale
        self.walkSpeed = walkSpeed
        self.aiProvider = aiProvider
        self.geminiImageModel = geminiImageModel
        self.hourlyMessages = hourlyMessages
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DecodingKeys.self)
        // selectedCharacterId → mainCharacterId 하위 호환
        mainCharacterId = try c.decodeIfPresent(String.self, forKey: .mainCharacterId)
            ?? c.decodeIfPresent(String.self, forKey: .selectedCharacterId)
            ?? "default"
        secondaryCharacterIds = try c.decodeIfPresent([String].self, forKey: .secondaryCharacterIds) ?? []
        flippedCharacterIds = try c.decodeIfPresent([String].self, forKey: .flippedCharacterIds) ?? []
        isHourlyNotificationEnabled = try c.decodeIfPresent(Bool.self, forKey: .isHourlyNotificationEnabled) ?? true
        // 구버전 isSoundEnabled: false → "none" 호환
        if let sound = try c.decodeIfPresent(String.self, forKey: .notificationSound) {
            notificationSound = sound
        } else {
            let oldEnabled = try c.decodeIfPresent(Bool.self, forKey: .isSoundEnabled) ?? true
            notificationSound = oldEnabled ? "default" : "none"
        }
        characterScale = try c.decodeIfPresent(Double.self, forKey: .characterScale) ?? 1.0
        walkSpeed = try c.decodeIfPresent(WalkSpeed.self, forKey: .walkSpeed) ?? .normal
        aiProvider = try c.decodeIfPresent(AIProvider.self, forKey: .aiProvider) ?? .anthropic
        geminiImageModel = try c.decodeIfPresent(String.self, forKey: .geminiImageModel) ?? "gemini-2.5-flash-image"
        hourlyMessages = try c.decodeIfPresent([String].self, forKey: .hourlyMessages) ?? UserSettings.defaultHourlyMessages
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: EncodingKeys.self)
        try c.encode(mainCharacterId, forKey: .mainCharacterId)
        try c.encode(secondaryCharacterIds, forKey: .secondaryCharacterIds)
        try c.encode(flippedCharacterIds, forKey: .flippedCharacterIds)
        try c.encode(isHourlyNotificationEnabled, forKey: .isHourlyNotificationEnabled)
        try c.encode(notificationSound, forKey: .notificationSound)
        try c.encode(characterScale, forKey: .characterScale)
        try c.encode(walkSpeed, forKey: .walkSpeed)
        try c.encode(aiProvider, forKey: .aiProvider)
        try c.encode(geminiImageModel, forKey: .geminiImageModel)
        try c.encode(hourlyMessages, forKey: .hourlyMessages)
    }

    private enum DecodingKeys: String, CodingKey {
        case mainCharacterId
        case selectedCharacterId  // 구버전 호환용
        case secondaryCharacterIds
        case flippedCharacterIds
        case isHourlyNotificationEnabled
        case notificationSound
        case isSoundEnabled  // 구버전 호환용
        case characterScale
        case walkSpeed
        case aiProvider
        case geminiImageModel
        case hourlyMessages
    }

    private enum EncodingKeys: String, CodingKey {
        case mainCharacterId
        case secondaryCharacterIds
        case flippedCharacterIds
        case isHourlyNotificationEnabled
        case notificationSound
        case characterScale
        case walkSpeed
        case aiProvider
        case geminiImageModel
        case hourlyMessages
    }

    public var allCharacterIds: [String] {
        [mainCharacterId] + secondaryCharacterIds
    }

    public static let maxCharacters = 6

    public enum WalkSpeed: String, Codable, CaseIterable, Sendable {
        case slow, normal, fast

        public var pointsPerSecond: Double {
            switch self {
            case .slow: 50
            case .normal: 80
            case .fast: 130
            }
        }
    }

    public enum AIProvider: String, Codable, CaseIterable, Sendable {
        case anthropic
        case openai
        case gemini

        public var displayName: String {
            switch self {
            case .anthropic: "Anthropic (Claude)"
            case .openai: "OpenAI (GPT)"
            case .gemini: "Google (Gemini)"
            }
        }

        public var apiKeyPlaceholder: String {
            switch self {
            case .anthropic: "sk-ant-..."
            case .openai: "sk-..."
            case .gemini: "AIza..."
            }
        }
    }

    public static let geminiImageModels: [(id: String, displayName: String)] = [
        ("gemini-2.5-flash-image", "Gemini 2.5 Flash Image"),
        ("gemini-3-pro-image-preview", "Gemini 3 Pro Image (Preview)"),
        ("gemini-3.1-flash-image-preview", "Gemini 3.1 Flash Image (Preview)"),
    ]

    private static let storageKey = "com.tikitime.userSettings"

    public static func load() -> UserSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(UserSettings.self, from: data)
        else { return UserSettings() }
        return settings
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
