import SwiftUI
import UniformTypeIdentifiers
import TikiTimeCore

struct CharacterSetupView: View {
    let onComplete: (CharacterManifest) -> Void

    enum CharacterMode: String, CaseIterable {
        case image = "이미지"
        case emoji = "이모지/텍스트"
    }

    @State private var characterMode: CharacterMode = .image
    @State private var displayName = ""
    @State private var selectedImageData: Data?
    @State private var selectedImagePreview: NSImage?
    @State private var emojiInput: String = ""
    @State private var isGenerating = false
    @State private var progressLabel = ""
    @State private var progressCurrent = 0
    @State private var progressTotal = 1
    @State private var errorMessage: String?
    @State private var selectedProvider: UserSettings.AIProvider? = nil
    @Environment(\.dismiss) private var dismiss

    private var availableProviders: [(provider: UserSettings.AIProvider, apiKey: String)] {
        [UserSettings.AIProvider.openai, .gemini].compactMap { p in
            guard let key = KeychainService.loadAPIKey(for: p), !key.isEmpty else { return nil }
            return (p, key)
        }
    }

    private var activeGeneration: (provider: UserSettings.AIProvider, apiKey: String)? {
        guard let p = selectedProvider ?? availableProviders.first?.provider,
              let key = KeychainService.loadAPIKey(for: p), !key.isEmpty
        else { return nil }
        return (p, key)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("새 캐릭터 추가")
                .font(.headline)

            Picker("", selection: $characterMode) {
                ForEach(CharacterMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            if characterMode == .image {
                imagePickerSection
            } else {
                emojiPickerSection
            }

            nameSection

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if isGenerating {
                progressSection
            }

            actionButtons
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            let preferred = UserSettings.load().aiProvider
            if availableProviders.contains(where: { $0.provider == preferred }) {
                selectedProvider = preferred
            } else {
                selectedProvider = availableProviders.first?.provider
            }
        }
        .onChange(of: characterMode) { _, _ in
            errorMessage = nil
        }
    }

    // MARK: - Image Mode

    @ViewBuilder
    private var providerSection: some View {
        if availableProviders.isEmpty {
            Text("OpenAI 또는 Gemini API 키를 등록하면 감정·애니메이션 프레임을 자동 생성합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        } else if availableProviders.count == 1 {
            Text("\(availableProviders[0].provider.displayName)로 감정·애니메이션 프레임을 자동 생성합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        } else {
            LabeledContent("생성 공급자") {
                Picker("", selection: Binding(
                    get: { selectedProvider ?? availableProviders[0].provider },
                    set: { selectedProvider = $0 }
                )) {
                    ForEach(availableProviders, id: \.provider) { item in
                        Text(item.provider.displayName).tag(item.provider)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                .disabled(isGenerating)
            }
        }
    }

    private var imagePickerSection: some View {
        VStack(spacing: 8) {
            if let preview = selectedImagePreview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.4), lineWidth: 1))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text("PNG 선택")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    )
            }

            Button("이미지 선택") { pickImage() }
                .buttonStyle(.bordered)
                .disabled(isGenerating)
        }
    }

    // MARK: - Emoji Mode

    private var emojiPickerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                if emojiInput.isEmpty {
                    Text("🐱")
                        .font(.system(size: 64))
                        .opacity(0.3)
                } else {
                    Text(String(emojiInput.prefix(2)))
                        .font(.system(size: 64))
                }
            }

            TextField("이모지 또는 텍스트 입력", text: $emojiInput)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 200)
                .onChange(of: emojiInput) { _, newValue in
                    let truncated = String(newValue.prefix(2))
                    if newValue != truncated { emojiInput = truncated }
                }
        }
    }

    // MARK: - Common

    private var nameSection: some View {
        LabeledContent("이름") {
            TextField("캐릭터 이름", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .disabled(isGenerating)
        }
    }

    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(progressCurrent), total: Double(progressTotal))
            Text("\(progressLabel) (\(progressCurrent)/\(progressTotal))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var actionButtons: some View {
        HStack {
            Button("취소") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isGenerating)

            Spacer()

            if characterMode == .image && activeGeneration != nil {
                Button("AI로 생성") { startFullGeneration() }
                    .buttonStyle(.bordered)
                    .disabled(!canGenerate || isGenerating)
            }

            Button("캐릭터 추가") {
                if characterMode == .emoji {
                    addEmojiCharacter()
                } else {
                    addStaticCharacter()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canGenerate || isGenerating)
        }
    }

    private var canGenerate: Bool {
        let nameOK = !displayName.trimmingCharacters(in: .whitespaces).isEmpty
        switch characterMode {
        case .image: return selectedImageData != nil && nameOK
        case .emoji: return !emojiInput.trimmingCharacters(in: .whitespaces).isEmpty && nameOK
        }
    }

    // MARK: - Actions

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url)
        else { return }
        selectedImageData = data
        selectedImagePreview = NSImage(data: data)
    }

    private func addStaticCharacter() {
        guard let imageData = selectedImageData else { return }
        let name = displayName.trimmingCharacters(in: .whitespaces)
        let characterId = UUID().uuidString
        do {
            try CharacterGenerationService.createStaticCharacter(id: characterId, displayName: name, imageData: imageData)
            if let manifest = CharacterStorageService.loadManifest(id: characterId) {
                onComplete(manifest)
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addEmojiCharacter() {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        let emoji = emojiInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !emoji.isEmpty else { return }
        let characterId = UUID().uuidString
        let manifest = CharacterManifest(
            id: characterId,
            displayName: name,
            version: "1.0.0",
            emoji: String(emoji.prefix(2)),
            isImageBased: false
        )
        do {
            try CharacterStorageService.saveManifest(manifest)
            onComplete(manifest)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startFullGeneration() {
        guard let imageData = selectedImageData,
              let gen = activeGeneration
        else { return }

        let name = displayName.trimmingCharacters(in: .whitespaces)
        let characterId = UUID().uuidString
        let settings = UserSettings.load()
        let service = CharacterGenerationService(apiKey: gen.apiKey, provider: gen.provider, geminiModel: settings.geminiImageModel)

        isGenerating = true
        errorMessage = nil

        Task {
            do {
                try await service.generateCharacter(
                    id: characterId,
                    displayName: name,
                    originalImageData: imageData
                ) { label, current, total in
                    Task { @MainActor in
                        self.progressLabel = label
                        self.progressCurrent = current
                        self.progressTotal = total
                    }
                }

                await MainActor.run {
                    if let manifest = CharacterStorageService.loadManifest(id: characterId) {
                        onComplete(manifest)
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
