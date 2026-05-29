import Foundation
import TikiTimeCore

enum CharacterStorageService {
    static let rootURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TikiTime/Characters", isDirectory: true)
    }()

    static func characterDirectory(id: String) -> URL {
        rootURL.appendingPathComponent(id, isDirectory: true)
    }

    static func animationsDirectory(id: String, animation: String) -> URL {
        characterDirectory(id: id).appendingPathComponent("animations/\(animation)", isDirectory: true)
    }

    static func ensureDirectoriesExist(for id: String) throws {
        try FileManager.default.createDirectory(at: characterDirectory(id: id), withIntermediateDirectories: true)
    }

    static func saveManifest(_ manifest: CharacterManifest) throws {
        try ensureDirectoriesExist(for: manifest.id)
        let url = characterDirectory(id: manifest.id).appendingPathComponent("manifest.json")
        try JSONEncoder().encode(manifest).write(to: url)
    }

    /// Application Support를 먼저 확인하고, "default"는 없으면 번들 폴백
    static func loadManifest(id: String) -> CharacterManifest? {
        let url = characterDirectory(id: id).appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: url),
           let manifest = try? JSONDecoder().decode(CharacterManifest.self, from: data) {
            return manifest
        }
        return id == "default" ? bundleDefaultManifest() : nil
    }

    static func bundleDefaultManifest() -> CharacterManifest? {
        let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "Characters/default")
            ?? Bundle.main.url(forResource: "manifest", withExtension: "json")
        guard let url,
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(CharacterManifest.self, from: data)
        else { return nil }
        return manifest
    }

    static func saveOriginal(imageData: Data, characterId: String) throws {
        try ensureDirectoriesExist(for: characterId)
        let url = characterDirectory(id: characterId).appendingPathComponent("original.png")
        try imageData.write(to: url)
    }

    static func saveAnimationFrame(_ imageData: Data, characterId: String, animation: String, frame: Int) throws {
        let dir = animationsDirectory(id: characterId, animation: animation)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("frame_\(frame).png")
        try imageData.write(to: url)
    }

    static func imageURL(characterId: String, relativePath: String) -> URL {
        characterDirectory(id: characterId).appendingPathComponent(relativePath)
    }

    static func allManifests() -> [CharacterManifest] {
        // "default"는 Application Support 우선, 없으면 번들
        var manifests: [CharacterManifest] = []
        if let def = loadManifest(id: "default") { manifests.append(def) }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return manifests }

        for dir in contents where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let id = dir.lastPathComponent
            guard id != "default" else { continue } // 이미 추가됨
            if let manifest = loadManifest(id: id) {
                manifests.append(manifest)
            }
        }
        return manifests
    }

    static func delete(id: String) throws {
        guard id != "default" else { return }
        try FileManager.default.removeItem(at: characterDirectory(id: id))
    }
}
