import SwiftUI
import UniformTypeIdentifiers
import TikiTimeCore

struct CharacterEditorView: View {
    let characterId: String

    @State private var manifest: CharacterManifest?
    @State private var previews: [String: [NSImage]] = [:]
    @State private var newMessageText: [String: String] = [:]
    @State private var hoveredFrame: [String: Int] = [:]
    @State private var selectedState: String? = "idle"
    @State private var editingDisplayName: String = ""
    @State private var editingEmoji: String = ""
    @Environment(\.dismiss) private var dismiss

    private static let stateList: [(key: String, label: String, icon: String)] = [
        ("idle",      "기본",  "figure.stand"),
        ("walk",      "걷기",  "figure.walk"),
        ("happy",     "행복",  "face.smiling"),
        ("sad",       "슬픔",  "cloud.drizzle"),
        ("angry",     "분노",  "flame"),
        ("fearful",   "공포",  "eye.trianglebadge.exclamationmark"),
        ("disgusted", "혐오",  "hand.thumbsdown"),
        ("surprised", "놀람",  "exclamationmark.bubble"),
    ]

    private var currentState: String { selectedState ?? "idle" }

    var body: some View {
        HStack(spacing: 0) {
            leftSidebar
            Divider()
            rightContent
        }
        .frame(width: 720, height: 600)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("닫기") { dismiss() }
            }
            ToolbarItem {
                Button("Finder에서 열기") { openInFinder() }
            }
        }
        .onAppear { loadAll() }
    }

    // MARK: - Left Sidebar

    private var leftSidebar: some View {
        List(Self.stateList, id: \.key, selection: $selectedState) { item in
            Label(item.label, systemImage: item.icon)
                .tag(item.key)
        }
        .listStyle(.sidebar)
        .frame(width: 150)
    }

    // MARK: - Right Content

    private var rightContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                characterInfoSection
                Divider()
                previewSection
                Divider()
                if currentState == "walk" {
                    walkSpeedSection
                    Divider()
                }
                animationSection(state: currentState, label: labelFor(currentState))
                Divider()
                messagesSection(state: currentState)
            }
            .padding()
        }
    }

    // MARK: - Character Info

    private var characterInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("캐릭터 정보").font(.headline)
            HStack(spacing: 16) {
                LabeledContent("이름") {
                    TextField("이름", text: $editingDisplayName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .onChange(of: editingDisplayName) { _, v in
                            guard !v.isEmpty else { return }
                            saveManifest(displayName: v)
                        }
                }
                LabeledContent("이모지") {
                    TextField("", text: $editingEmoji)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onChange(of: editingEmoji) { _, v in
                            let truncated = String(v.prefix(2))
                            if v != truncated { editingEmoji = truncated }
                            saveManifest(emoji: truncated)
                        }
                }
            }
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        let image = previews[currentState]?.first ?? previews["idle"]?.first
        let offsetY = CGFloat(manifest?.footOffsetY ?? 0)
        let offsetX = CGFloat(manifest?.footOffsetX ?? 0)
        let size: CGFloat = 140
        let scale = size / 200.0
        let floorLineY = size / 2 - offsetY * scale

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                // 미리보기 이미지
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                    if let img = image {
                        Image(nsImage: img).resizable().frame(width: size, height: size)
                    } else if let emoji = manifest?.emoji {
                        Text(emoji).font(.system(size: 60)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
                            Text("이미지 없음").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    // Y축 바닥 기준선 (가로 초록선)
                    Rectangle()
                        .fill(Color.green.opacity(0.85))
                        .frame(height: 2)
                        .offset(y: floorLineY - 1)

                    // X축 오프셋 기준선 (세로 파란선)
                    Color.blue.opacity(0.55)
                        .frame(width: 1.5, height: size)
                        .offset(x: size / 2 + offsetX * scale)
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Y축 오프셋 세로 슬라이더
                VStack(spacing: 4) {
                    Text("100").font(.caption2).foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { manifest?.footOffsetY ?? 0 },
                            set: { saveManifest(footOffsetY: $0) }
                        ),
                        in: -100...100, step: 1
                    )
                    .frame(width: size - 10)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 24, height: size - 10)
                    Text("-100").font(.caption2).foregroundStyle(.secondary)
                    Text("Y: \(Int(offsetY))px").font(.caption2).monospacedDigit()
                }

                // 정보
                VStack(alignment: .leading, spacing: 6) {
                    Label(labelFor(currentState), systemImage: iconFor(currentState)).font(.headline)
                    Spacer().frame(height: 2)
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.green).frame(width: 12, height: 2)
                        Text("바닥 기준선").font(.caption).foregroundStyle(.secondary)
                    }
                    let count = previews[currentState]?.count ?? 0
                    if count > 0 {
                        Text("프레임: \(count)개").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            // X축 오프셋 가로 슬라이더
            HStack(spacing: 6) {
                Text("X").font(.caption).foregroundStyle(.secondary).frame(width: 14)
                Text("-100").font(.caption2).foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { manifest?.footOffsetX ?? 0 },
                        set: { saveManifest(footOffsetX: $0) }
                    ),
                    in: -100...100, step: 1
                )
                .frame(width: size)
                Text("100").font(.caption2).foregroundStyle(.secondary)
                Text("\(Int(offsetX))px").font(.caption2).monospacedDigit().frame(width: 36, alignment: .trailing)
            }
        }
    }

    // MARK: - Walk Speed

    private var walkSpeedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("이동 속도").font(.headline)
            HStack(spacing: 8) {
                Text("느림").font(.caption).foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { manifest?.walkSpeed ?? 70 },
                        set: { saveManifest(walkSpeed: $0) }
                    ),
                    in: 20...150, step: 5
                )
                Text("빠름").font(.caption).foregroundStyle(.secondary)
                Text("\(Int(manifest?.walkSpeed ?? 70)) pt/s")
                    .monospacedDigit().font(.caption).frame(width: 60)
            }
        }
    }

    // MARK: - Animation Section

    private func animationSection(state: String, label: String) -> some View {
        let frames = Binding(
            get: { previews[state] ?? [] },
            set: { previews[state] = $0 }
        )
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(label).font(.headline)
                if state != "idle" {
                    Text("\(frames.wrappedValue.count)프레임")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()

                if state != "idle" {
                    Button {
                        importFramesFromFolder(state: state, frames: frames)
                    } label: {
                        Label("폴더", systemImage: "folder")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }

                Button {
                    if state == "idle", !frames.wrappedValue.isEmpty {
                        replaceFrame(state: state, index: 0, frames: frames)
                    } else {
                        pickFrame(state: state, frames: frames)
                    }
                } label: {
                    if state == "idle" && !frames.wrappedValue.isEmpty {
                        Label("변경", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("추가", systemImage: "plus")
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)

                if !frames.wrappedValue.isEmpty {
                    Button(role: .destructive) {
                        removeAllFrames(state: state, frames: frames)
                    } label: {
                        Label(state == "idle" ? "삭제" : "전체 삭제", systemImage: "trash")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }

            if frames.wrappedValue.isEmpty {
                Text(state == "idle"
                     ? "+ 버튼으로 기본 이미지를 1장 등록하세요."
                     : "폴더 버튼으로 PNG 폴더를 선택하거나, + 버튼으로 한 장씩 추가하세요.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(frames.wrappedValue.indices, id: \.self) { i in
                            VStack(spacing: 4) {
                                ZStack(alignment: .topTrailing) {
                                    Image(nsImage: frames.wrappedValue[i])
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                                        .onTapGesture { replaceFrame(state: state, index: i, frames: frames) }

                                    if hoveredFrame[state] == i {
                                        Button {
                                            removeFrame(state: state, index: i, frames: frames)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white, .red)
                                                .font(.system(size: 16))
                                        }
                                        .buttonStyle(.plain)
                                        .offset(x: 6, y: -6)
                                    }
                                }
                                .onHover { inside in hoveredFrame[state] = inside ? i : nil }

                                Text("F\(i + 1)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Messages Section

    private func messagesSection(state: String) -> some View {
        let messages = effectiveMessages(for: state)
        return VStack(alignment: .leading, spacing: 6) {
            Text("대사").font(.subheadline).foregroundStyle(.secondary)
            Text("줄바꿈이 필요하면 \\n 을 직접 입력하세요.")
                .font(.caption2).foregroundStyle(.tertiary)

            if messages.isEmpty {
                Text("이 상태에서 표시할 대사가 없습니다.")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(messages.indices, id: \.self) { i in
                    HStack {
                        Text(messages[i])
                            .font(.caption)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(role: .destructive) {
                            removeMessage(state: state, index: i)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain).controlSize(.small)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            HStack {
                TextField("새 대사 입력... (줄바꿈: \\n)", text: Binding(
                    get: { newMessageText[state] ?? "" },
                    set: { newMessageText[state] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit { addMessage(state: state) }

                Button { addMessage(state: state) } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled((newMessageText[state] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Helpers

    private func labelFor(_ state: String) -> String {
        Self.stateList.first(where: { $0.key == state })?.label ?? state
    }

    private func iconFor(_ state: String) -> String {
        Self.stateList.first(where: { $0.key == state })?.icon ?? "questionmark"
    }

    private func effectiveMessages(for state: String) -> [String] {
        guard let m = manifest else { return [] }
        if state == "idle" {
            return m.idleMessages + (m.stateMessages["idle"] ?? [])
        }
        return m.stateMessages[state] ?? []
    }

    // MARK: - Manifest Save

    private func saveManifest(
        animations: [String: [String]]? = nil,
        stateMessages: [String: [String]]? = nil,
        footOffsetY: Double? = nil,
        footOffsetX: Double? = nil,
        walkSpeed: Double? = nil,
        idleMessages: [String]? = nil,
        displayName: String? = nil,
        emoji: String? = nil
    ) {
        guard let m = manifest else { return }
        let newEmoji: String?
        if let e = emoji {
            newEmoji = e.isEmpty ? m.emoji : e
        } else {
            newEmoji = m.emoji
        }
        let updated = CharacterManifest(
            id: m.id,
            displayName: displayName ?? m.displayName,
            version: m.version,
            emoji: newEmoji,
            isImageBased: m.isImageBased,
            animations: animations ?? m.animations,
            stateMessages: stateMessages ?? m.stateMessages,
            footOffsetY: footOffsetY ?? m.footOffsetY,
            footOffsetX: footOffsetX ?? m.footOffsetX,
            walkSpeed: walkSpeed ?? m.walkSpeed,
            hourlyGreetings: m.hourlyGreetings,
            idleMessages: idleMessages ?? m.idleMessages
        )
        manifest = updated
        try? CharacterStorageService.saveManifest(updated)
        NotificationCenter.default.post(name: .tikiTimeSettingsChanged, object: nil)
    }

    // MARK: - Data Loading

    private func loadAll() {
        guard let m = CharacterStorageService.loadManifest(id: characterId) else { return }
        manifest = m
        editingDisplayName = m.displayName
        editingEmoji = m.emoji ?? ""
        for (state, paths) in m.animations {
            previews[state] = paths.compactMap { path in
                NSImage(contentsOf: CharacterStorageService.imageURL(characterId: characterId, relativePath: path))
            }
        }
    }

    // MARK: - Frame Operations

    private func pickFrame(state: String, frames: Binding<[NSImage]>) {
        guard let data = pickPNG(), let img = NSImage(data: data) else { return }
        let index = frames.wrappedValue.count
        try? CharacterStorageService.saveAnimationFrame(data, characterId: characterId, animation: state, frame: index)
        frames.wrappedValue.append(img)
        updateAnimations(state: state, count: frames.wrappedValue.count)
    }

    private func replaceFrame(state: String, index: Int, frames: Binding<[NSImage]>) {
        guard let data = pickPNG(), let img = NSImage(data: data) else { return }
        try? CharacterStorageService.saveAnimationFrame(data, characterId: characterId, animation: state, frame: index)
        frames.wrappedValue[index] = img
    }

    private func removeFrame(state: String, index: Int, frames: Binding<[NSImage]>) {
        let count = frames.wrappedValue.count
        guard index < count else { return }
        let targetURL = CharacterStorageService.imageURL(characterId: characterId, relativePath: "animations/\(state)/frame_\(index).png")
        try? FileManager.default.removeItem(at: targetURL)
        for i in (index + 1)..<count {
            let fromURL = CharacterStorageService.imageURL(characterId: characterId, relativePath: "animations/\(state)/frame_\(i).png")
            let toURL = CharacterStorageService.imageURL(characterId: characterId, relativePath: "animations/\(state)/frame_\(i - 1).png")
            try? FileManager.default.moveItem(at: fromURL, to: toURL)
        }
        frames.wrappedValue.remove(at: index)
        updateAnimations(state: state, count: frames.wrappedValue.count)
    }

    private func removeAllFrames(state: String, frames: Binding<[NSImage]>) {
        for i in 0..<frames.wrappedValue.count {
            let url = CharacterStorageService.imageURL(characterId: characterId, relativePath: "animations/\(state)/frame_\(i).png")
            try? FileManager.default.removeItem(at: url)
        }
        frames.wrappedValue = []
        updateAnimations(state: state, count: 0)
    }

    private func updateAnimations(state: String, count: Int) {
        guard let m = manifest else { return }
        var anims = m.animations
        anims[state] = count == 0 ? nil : (0..<count).map { "animations/\(state)/frame_\($0).png" }
        saveManifest(animations: anims.compactMapValues { $0 })
    }

    private func importFramesFromFolder(state: String, frames: Binding<[NSImage]>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folderURL = panel.url else { return }

        let pngURLs = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        guard !pngURLs.isEmpty else { return }

        for i in 0..<frames.wrappedValue.count {
            let url = CharacterStorageService.imageURL(characterId: characterId, relativePath: "animations/\(state)/frame_\(i).png")
            try? FileManager.default.removeItem(at: url)
        }
        frames.wrappedValue = []

        for (i, url) in pngURLs.enumerated() {
            guard let data = try? Data(contentsOf: url), let img = NSImage(data: data) else { continue }
            try? CharacterStorageService.saveAnimationFrame(data, characterId: characterId, animation: state, frame: i)
            frames.wrappedValue.append(img)
        }
        updateAnimations(state: state, count: frames.wrappedValue.count)
    }

    // MARK: - Message Operations

    private func addMessage(state: String) {
        let text = (newMessageText[state] ?? "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let m = manifest else { return }
        newMessageText[state] = ""
        if state == "idle" {
            var idleMsgs = m.idleMessages
            idleMsgs.append(text)
            saveManifest(idleMessages: idleMsgs)
        } else {
            var msgs = m.stateMessages
            msgs[state] = (msgs[state] ?? []) + [text]
            saveManifest(stateMessages: msgs)
        }
    }

    private func removeMessage(state: String, index: Int) {
        guard let m = manifest else { return }
        if state == "idle" {
            let idleCount = m.idleMessages.count
            if index < idleCount {
                var idleMsgs = m.idleMessages
                idleMsgs.remove(at: index)
                saveManifest(idleMessages: idleMsgs)
            } else {
                let stateIdx = index - idleCount
                var msgs = m.stateMessages
                var list = msgs["idle"] ?? []
                guard stateIdx < list.count else { return }
                list.remove(at: stateIdx)
                msgs["idle"] = list.isEmpty ? nil : list
                saveManifest(stateMessages: msgs.compactMapValues { $0 })
            }
        } else {
            var msgs = m.stateMessages
            var list = msgs[state] ?? []
            guard index < list.count else { return }
            list.remove(at: index)
            msgs[state] = list.isEmpty ? nil : list
            saveManifest(stateMessages: msgs.compactMapValues { $0 })
        }
    }

    // MARK: - Utilities

    private func pickPNG() -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try? Data(contentsOf: url)
    }

    private func openInFinder() {
        NSWorkspace.shared.open(CharacterStorageService.characterDirectory(id: characterId))
    }
}
