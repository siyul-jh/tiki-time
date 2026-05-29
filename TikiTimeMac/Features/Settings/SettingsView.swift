import SwiftUI
import TikiTimeCore

struct SettingsView: View {
    @State private var settings = UserSettings.load()
    @State private var apiKey: String = ""
    @State private var apiKeySaved = false
    @State private var availableCharacters: [CharacterManifest] = []
    @State private var showingCharacterSetup = false
    @State private var editingCharacterId: String? = nil
    @State private var newHourlyMessage: String = ""
    @State private var selection: SettingsPane? = .notification

    static let soundOptions: [(label: String, value: String)] = [
        ("기본", "default"),
        ("Tink", "Tink"),
        ("Ping", "Ping"),
        ("Glass", "Glass"),
        ("Bottle", "Bottle"),
        ("없음", "none"),
    ]

    enum SettingsPane: String, CaseIterable, Identifiable {
        case notification = "알림"
        case character = "캐릭터"
        case ai = "AI (개발중)"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .notification: "bell.fill"
            case .character: "person.crop.circle.fill"
            case .ai: "sparkles"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.rawValue, systemImage: pane.icon)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(140)
        } detail: {
            Group {
                switch selection {
                case .notification: notificationPane
                case .character: characterPane
                case .ai: aiPane
                case nil: Text("항목을 선택하세요").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 520, minHeight: 400)
        .onAppear {
            apiKey = KeychainService.loadAPIKey(for: settings.aiProvider) ?? ""
            availableCharacters = CharacterStorageService.allManifests()
        }
        .onChange(of: settings.isHourlyNotificationEnabled) { _, _ in save() }
        .onChange(of: settings.notificationSound) { _, _ in save() }
        .onChange(of: settings.characterScale) { _, _ in persist() }
        .sheet(isPresented: $showingCharacterSetup) {
            CharacterSetupView { newManifest in
                availableCharacters = CharacterStorageService.allManifests()
                settings.secondaryCharacterIds.append(newManifest.id)
                persist()
            }
        }
        .sheet(item: Binding(
            get: { editingCharacterId.map { IdentifiableString(value: $0) } },
            set: { editingCharacterId = $0?.value }
        )) { item in
            CharacterEditorView(characterId: item.value)
                .onDisappear { availableCharacters = CharacterStorageService.allManifests() }
        }
    }

    // MARK: - 알림 패널

    private var notificationPane: some View {
        Form {
            Section("알림") {
                Toggle("매 정각 알림 활성화", isOn: $settings.isHourlyNotificationEnabled)
                LabeledContent("알림 소리") {
                    Picker("", selection: $settings.notificationSound) {
                        ForEach(Self.soundOptions, id: \.value) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .disabled(!settings.isHourlyNotificationEnabled)
                }
            }

            Section("정각 메시지") {
                if settings.hourlyMessages.isEmpty {
                    Text("메시지가 없습니다. 추가해보세요!")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.hourlyMessages.indices, id: \.self) { index in
                        HStack {
                            Text(settings.hourlyMessages[index])
                                .lineLimit(1)
                            Spacer()
                            Button(role: .destructive) {
                                settings.hourlyMessages.remove(at: index)
                                save()
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                HStack {
                    TextField("새 메시지 입력...", text: $newHourlyMessage)
                    Button("추가") {
                        let trimmed = newHourlyMessage.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        settings.hourlyMessages.append(trimmed)
                        newHourlyMessage = ""
                        save()
                    }
                    .disabled(newHourlyMessage.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("정각마다 목록에서 랜덤으로 하나씩 표시됩니다. \\n 으로 줄바꿈할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 캐릭터 패널

    private var characterPane: some View {
        Form {
            Section("캐릭터 목록") {
                characterListRows

                if settings.allCharacterIds.count < UserSettings.maxCharacters {
                    Button("+ 새 캐릭터 추가") { showingCharacterSetup = true }
                        .foregroundColor(.accentColor)
                }
            }

            Section("표시") {
                LabeledContent("크기") {
                    Slider(value: $settings.characterScale, in: 0.5...2.0, step: 0.1)
                        .frame(width: 180)
                    Text(String(format: "%.1fx", settings.characterScale))
                        .monospacedDigit()
                        .frame(width: 36)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - AI 패널

    private var aiPane: some View {
        Form {
            Section("공급자") {
                LabeledContent("AI 공급자") {
                    Picker("", selection: $settings.aiProvider) {
                        ForEach(UserSettings.AIProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                    .onChange(of: settings.aiProvider) { _, newProvider in
                        apiKey = KeychainService.loadAPIKey(for: newProvider) ?? ""
                        apiKeySaved = false
                        persist()
                    }
                }

                if settings.aiProvider == .gemini {
                    LabeledContent("이미지 생성 모델") {
                        Picker("", selection: $settings.geminiImageModel) {
                            ForEach(UserSettings.geminiImageModels, id: \.id) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)
                        .onChange(of: settings.geminiImageModel) { _, _ in persist() }
                    }
                }
            }

            Section("API 키") {
                LabeledContent("키") {
                    SecureField(settings.aiProvider.apiKeyPlaceholder, text: $apiKey)
                        .frame(width: 220)
                    Button(apiKeySaved ? "저장됨 ✓" : "저장") { saveAPIKey() }
                        .disabled(apiKey.isEmpty)
                }

                if !apiKey.isEmpty {
                    Button("키 삭제", role: .destructive) {
                        KeychainService.deleteAPIKey(for: settings.aiProvider)
                        apiKey = ""
                        apiKeySaved = false
                    }
                }

                Text("캐릭터를 클릭하면 AI가 반응해요.\nAPI 키는 이 기기의 키체인에만 저장됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 공용

    private var characterListRows: some View {
        let filtered = availableCharacters.filter { settings.allCharacterIds.contains($0.id) }
        return CharacterListRows(
            manifests: filtered,
            mainId: settings.mainCharacterId,
            flippedIds: settings.flippedCharacterIds,
            onSetMain: { setAsMain($0) },
            onToggleFlip: { id in
                if settings.flippedCharacterIds.contains(id) {
                    settings.flippedCharacterIds.removeAll { $0 == id }
                } else {
                    settings.flippedCharacterIds.append(id)
                }
                persist()
            },
            onEdit: { editingCharacterId = $0 },
            onRemove: { removeCharacter($0) }
        )
    }

    // MARK: - Actions

    private func setAsMain(_ id: String) {
        guard let currentMain = availableCharacters.first(where: { $0.id == settings.mainCharacterId }) else { return }
        settings.secondaryCharacterIds.removeAll { $0 == id }
        settings.secondaryCharacterIds.append(currentMain.id)
        settings.mainCharacterId = id
        persist()
    }

    private func removeCharacter(_ id: String) {
        if settings.mainCharacterId == id {
            if let newMain = settings.secondaryCharacterIds.first {
                settings.mainCharacterId = newMain
                settings.secondaryCharacterIds.removeFirst()
            }
        } else {
            settings.secondaryCharacterIds.removeAll { $0 == id }
        }
        try? CharacterStorageService.delete(id: id)
        settings.save()
        availableCharacters = CharacterStorageService.allManifests()
        persist()
    }

    private func saveAPIKey() {
        KeychainService.saveAPIKey(apiKey, for: settings.aiProvider)
        apiKeySaved = true
    }

    private func persist() {
        settings.save()
        NotificationCenter.default.post(name: .tikiTimeSettingsChanged, object: nil)
    }

    private func save() {
        persist()
        if settings.isHourlyNotificationEnabled {
            Task { await NotificationService.shared.requestPermission() }
            let greetings = CharacterStorageService.loadManifest(id: settings.mainCharacterId)?.hourlyGreetings ?? []
            NotificationService.shared.scheduleHourlyNotifications(greetings: greetings, sound: settings.notificationSound)
        } else {
            NotificationService.shared.cancelHourlyNotifications()
        }
    }
}

// MARK: - 캐릭터 목록 행

private struct CharacterListRows: View {
    let manifests: [CharacterManifest]
    let mainId: String
    let flippedIds: [String]
    let onSetMain: (String) -> Void
    let onToggleFlip: (String) -> Void
    let onEdit: (String) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        ForEach(manifests) { manifest in
            HStack {
                Text(manifest.emoji ?? "🐾")
                Text(manifest.displayName)
                if manifest.id == mainId {
                    Text("메인").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2)).cornerRadius(4)
                } else {
                    Button("메인으로") { onSetMain(manifest.id) }
                        .buttonStyle(.borderless).font(.caption)
                }
                Spacer()
                if manifest.isImageBased {
                    Button {
                        onToggleFlip(manifest.id)
                    } label: {
                        Label(
                            flippedIds.contains(manifest.id) ? "반전됨" : "좌우반전",
                            systemImage: "arrow.left.arrow.right"
                        )
                        .font(.caption)
                        .foregroundStyle(flippedIds.contains(manifest.id) ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.borderless)
                }
                Button("편집") { onEdit(manifest.id) }
                    .buttonStyle(.borderless).font(.caption)
                Button(role: .destructive) { onRemove(manifest.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Helpers

private struct IdentifiableString: Identifiable {
    let value: String
    var id: String { value }
}
