import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import TikiTimeCore
import Vision

final class CharacterGenerationService {
    static let emotions = ["idle", "happy", "sad", "angry", "fearful", "disgusted", "surprised"]

    private static let cellSize = 200
    private static let gridSize = 5
    private static let sheetSize = cellSize * gridSize // 1000

    private static let openAIEndpoint = URL(string: "https://api.openai.com/v1/images/edits")!

    private let apiKey: String
    private let provider: UserSettings.AIProvider
    private let geminiModel: String

    init(apiKey: String, provider: UserSettings.AIProvider, geminiModel: String = "gemini-2.5-flash-image") {
        self.apiKey = apiKey
        self.provider = provider
        self.geminiModel = geminiModel
    }

    // MARK: - Public: 원본 이미지 200×200 정규화

    static func resizeToSquare(_ imageData: Data, size: Int = cellSize) throws -> Data {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw GenerationError.invalidResponse }

        let w = cgImage.width
        let h = cgImage.height
        let scale = min(CGFloat(size) / CGFloat(w), CGFloat(size) / CGFloat(h))
        let drawW = CGFloat(w) * scale
        let drawH = CGFloat(h) * scale
        let x = (CGFloat(size) - drawW) / 2
        let y = (CGFloat(size) - drawH) / 2

        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw GenerationError.backgroundRemovalFailed }

        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
        // CGContext의 원점은 좌하단이므로, makeImage()가 정상 방향이 되도록 플립
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(x: x, y: y, width: drawW, height: drawH))

        guard let resized = ctx.makeImage() else { throw GenerationError.backgroundRemovalFailed }
        return try pngData(from: resized)
    }

    static func createStaticCharacter(id: String, displayName: String, imageData: Data) throws {
        let resized = try resizeToSquare(imageData)
        try CharacterStorageService.saveOriginal(imageData: resized, characterId: id)
        let manifest = CharacterManifest(
            id: id,
            displayName: displayName,
            version: "1.0.0",
            isImageBased: true,
            animations: ["idle": ["original.png"]]
        )
        try CharacterStorageService.saveManifest(manifest)
    }

    func generateCharacter(
        id: String,
        displayName: String,
        originalImageData: Data,
        onProgress: @escaping @Sendable (String, Int, Int) -> Void
    ) async throws {
        let resizedOriginal = try Self.resizeToSquare(originalImageData)
        try CharacterStorageService.saveOriginal(imageData: resizedOriginal, characterId: id)

        let total = Self.emotions.count + 2 // emotions + walk + dance
        var current = 0
        var animationPaths: [String: [String]] = [:]

        for emotion in Self.emotions {
            current += 1
            onProgress("감정: \(emotionLabel(emotion))", current, total)
            let frames = try await generateAnimationFrames(
                prompt: emotionPrompt(for: emotion),
                sourceImageData: resizedOriginal
            )
            for (i, frameData) in frames.enumerated() {
                try CharacterStorageService.saveAnimationFrame(frameData, characterId: id, animation: emotion, frame: i)
            }
            animationPaths[emotion] = frames.indices.map { "animations/\(emotion)/frame_\($0).png" }
        }

        current += 1
        onProgress("걷기 애니메이션", current, total)
        let walkFrames = try await generateAnimationFrames(
            prompt: walkPrompt(),
            sourceImageData: resizedOriginal
        )
        for (i, frameData) in walkFrames.enumerated() {
            try CharacterStorageService.saveAnimationFrame(frameData, characterId: id, animation: "walk", frame: i)
        }
        animationPaths["walk"] = walkFrames.indices.map { "animations/walk/frame_\($0).png" }

        current += 1
        onProgress("댄스 애니메이션", current, total)
        let danceFrames = try await generateAnimationFrames(
            prompt: dancePrompt(),
            sourceImageData: resizedOriginal
        )
        for (i, frameData) in danceFrames.enumerated() {
            try CharacterStorageService.saveAnimationFrame(frameData, characterId: id, animation: "dance", frame: i)
        }
        animationPaths["dance"] = danceFrames.indices.map { "animations/dance/frame_\($0).png" }

        let manifest = CharacterManifest(
            id: id,
            displayName: displayName,
            version: "1.0.0",
            isImageBased: true,
            animations: animationPaths
        )
        try CharacterStorageService.saveManifest(manifest)
    }

    // MARK: - Pipeline: 스프라이트 시트 생성 → 슬라이싱 → 배경 제거

    private func generateAnimationFrames(prompt: String, sourceImageData: Data) async throws -> [Data] {
        let sheetData = try await generateSpriteSheet(prompt: prompt, sourceImageData: sourceImageData)
        let rawFrames = try sliceSpriteSheet(sheetData)
        return try await removeBackgrounds(from: rawFrames)
    }

    // MARK: - 스프라이트 시트 생성 API

    private func generateSpriteSheet(prompt: String, sourceImageData: Data) async throws -> Data {
        switch provider {
        case .openai:
            return try await generateSpriteSheetOpenAI(prompt: prompt, sourceImageData: sourceImageData)
        case .gemini:
            return try await generateSpriteSheetGemini(prompt: prompt, sourceImageData: sourceImageData)
        case .anthropic:
            throw GenerationError.unsupportedProvider
        }
    }

    // MARK: - OpenAI

    private func generateSpriteSheetOpenAI(prompt: String, sourceImageData: Data) async throws -> Data {
        var request = URLRequest(url: Self.openAIEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildOpenAIBody(boundary: boundary, imageData: sourceImageData, prompt: prompt)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GenerationError.requestFailed(String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        struct Response: Decodable {
            let data: [ImageItem]
            struct ImageItem: Decodable { let b64_json: String }
        }

        guard let b64 = try JSONDecoder().decode(Response.self, from: data).data.first?.b64_json,
              let imageData = Data(base64Encoded: b64)
        else { throw GenerationError.invalidResponse }

        return imageData
    }

    private func buildOpenAIBody(boundary: String, imageData: Data, prompt: String) -> Data {
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        let crlf = "\r\n"

        append("--\(boundary)\(crlf)")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"character.png\"\(crlf)")
        append("Content-Type: image/png\(crlf)\(crlf)")
        body.append(imageData)
        append(crlf)

        for (name, value) in [("model", "gpt-image-1"), ("prompt", prompt), ("size", "1024x1024")] {
            append("--\(boundary)\(crlf)")
            append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)")
            append(value + crlf)
        }

        append("--\(boundary)--\(crlf)")
        return body
    }

    // MARK: - Gemini

    private func generateSpriteSheetGemini(prompt: String, sourceImageData: Data) async throws -> Data {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(geminiModel):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw GenerationError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/png", "data": sourceImageData.base64EncodedString()]]
                ]
            ]],
            "generationConfig": ["responseModalities": ["IMAGE", "TEXT"]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw GenerationError.requestFailed("HTTP \(statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let parts = (candidates.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]],
              let inlineData = parts.first(where: { $0["inline_data"] != nil })?["inline_data"] as? [String: Any],
              let b64 = inlineData["data"] as? String,
              let imageData = Data(base64Encoded: b64)
        else { throw GenerationError.invalidResponse }

        return imageData
    }

    // MARK: - 스프라이트 시트 슬라이싱 (1000×1000 리사이즈 후 고정 그리드)

    private func sliceSpriteSheet(_ imageData: Data) throws -> [CGImage] {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw GenerationError.invalidResponse }

        let resized = try Self.stretchResize(sheet, to: Self.sheetSize)
        let cell = Self.cellSize
        var frames: [CGImage] = []
        for row in 0..<Self.gridSize {
            for col in 0..<Self.gridSize {
                let rect = CGRect(x: col * cell, y: row * cell, width: cell, height: cell)
                guard let frame = resized.cropping(to: rect) else {
                    throw GenerationError.invalidResponse
                }
                frames.append(frame)
            }
        }
        return frames
    }

    // MARK: - 배경 제거 (Vision)

    private func removeBackgrounds(from frames: [CGImage]) async throws -> [Data] {
        try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for (i, frame) in frames.enumerated() {
                group.addTask { (i, try self.removeBackground(from: frame)) }
            }
            var results: [(Int, Data)] = []
            for try await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    private func removeBackground(from image: CGImage) throws -> Data {
        if #available(macOS 14.0, *) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            if let result = request.results?.first {
                let maskedBuffer = try result.generateMaskedImage(
                    ofInstances: result.allInstances,
                    from: handler,
                    croppedToInstancesExtent: false
                )
                let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
                let context = CIContext()
                guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                    throw GenerationError.backgroundRemovalFailed
                }
                return try Self.pngData(from: cgImage)
            }
        }
        return try Self.pngData(from: image)
    }

    // MARK: - 이미지 유틸리티

    /// 스프라이트 시트를 정확한 size×size로 리사이즈 (셀 경계 정렬용)
    /// CGContext 원점이 좌하단이므로 플립 트랜스폼으로 makeImage() 방향을 정상화
    private static func stretchResize(_ image: CGImage, to size: Int) throws -> CGImage {
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw GenerationError.backgroundRemovalFailed }
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let resized = ctx.makeImage() else { throw GenerationError.backgroundRemovalFailed }
        return resized
    }

    static func pngData(from image: CGImage) throws -> Data {
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else {
            throw GenerationError.backgroundRemovalFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw GenerationError.backgroundRemovalFailed }
        return mutableData as Data
    }

    // MARK: - 프롬프트

    private static let promptSuffix = """
 \
Output format: a single 1000×1000 image containing a 5×5 grid of 25 animation frames (5 columns, 5 rows). \
Frame 1 is top-left; frames proceed left-to-right, top-to-bottom through frame 25. \
Each cell must be exactly 200×200 pixels. \
Do NOT add any separator lines, dividers, borders, or grid lines between cells — the 25 cells must be seamlessly tiled. \
CRITICAL RULES — do NOT violate any of these:
- Do NOT alter the character's design, colors, proportions, line art, or art style in any frame.
- Do NOT add shadows, drop shadows, cast shadows, or ground shadows of any kind.
- Do NOT add reflections, highlights, or environment lighting effects.
- Do NOT add any background elements, scenery, floor, wall, or ground inside any cell.
- Background of every cell must be flat pure white (#FFFFFF) with no gradients or textures.
- The entire character must remain fully visible in every frame — never crop or cut off any part of the body.
- Keep enough padding inside each cell so no limb goes out of frame even during motion.
- Only animate pose and motion across frames. Everything else stays identical to the reference image.
"""

    private func emotionPrompt(for emotion: String) -> String {
        let description: String
        switch emotion {
        case "idle":      description = "a seamless 25-frame idle loop: subtle breathing, gentle body sway, occasional blink"
        case "happy":     description = "a seamless 25-frame happy loop: bouncing joyfully, big smile, cheerful arm swinging"
        case "sad":       description = "a seamless 25-frame sad loop: drooping shoulders, sad face, gentle sobbing motion"
        case "angry":     description = "a seamless 25-frame angry loop: stomping in place, clenched fists, furious expression"
        case "fearful":   description = "a seamless 25-frame fearful loop: trembling and shaking, wide fearful eyes, cowering"
        case "disgusted": description = "a seamless 25-frame disgusted loop: recoiling, shuddering, grimacing face"
        case "surprised": description = "a seamless 25-frame surprised loop: jumping in shock, wide open eyes and mouth"
        default:          description = "a seamless 25-frame \(emotion) animation loop"
        }
        return "Generate \(description) of this exact character as a 5×5 sprite sheet.\(Self.promptSuffix)"
    }

    private func walkPrompt() -> String {
        "Generate a seamless 25-frame walk cycle of this exact character (one complete gait cycle, natural arm and leg movement) as a 5×5 sprite sheet.\(Self.promptSuffix)"
    }

    private func dancePrompt() -> String {
        "Generate a seamless 25-frame dance animation of this exact character (one complete joyful celebratory dance cycle) as a 5×5 sprite sheet.\(Self.promptSuffix)"
    }

    private func emotionLabel(_ emotion: String) -> String {
        switch emotion {
        case "idle": "기본"
        case "happy": "행복"
        case "sad": "슬픔"
        case "angry": "분노"
        case "fearful": "공포"
        case "disgusted": "혐오"
        case "surprised": "놀람"
        default: emotion
        }
    }

    enum GenerationError: LocalizedError {
        case requestFailed(String)
        case invalidResponse
        case unsupportedProvider
        case backgroundRemovalFailed
        case invalidSpriteSheet(String)

        var errorDescription: String? {
            switch self {
            case .requestFailed(let msg): "이미지 생성 실패: \(msg)"
            case .invalidResponse: "이미지 데이터를 받지 못했어요"
            case .unsupportedProvider: "이 AI 공급자는 이미지 생성을 지원하지 않아요"
            case .backgroundRemovalFailed: "배경 제거에 실패했어요"
            case .invalidSpriteSheet(let msg): "스프라이트 시트 처리 실패: \(msg)"
            }
        }
    }
}
