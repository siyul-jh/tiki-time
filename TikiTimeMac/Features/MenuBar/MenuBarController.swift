import AppKit
import SwiftUI

final class MenuBarController {
    private let statusItem: NSStatusItem
    private var settingsWindow: NSWindow?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setup()
    }

    private func setup() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "TikiTime")
        }

        let menu = NSMenu()
        menu.addItem(.init(title: "TikiTime", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let testItem = NSMenuItem(title: "정각 알림 테스트", action: #selector(testHourly), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        let testEmotionItem = NSMenuItem(title: "감정 트리거 테스트", action: nil, keyEquivalent: "")
        let emotionSubmenu = NSMenu()
        let emotions: [(label: String, key: String)] = [
            ("😐 기본 (idle)", "idle"),
            ("😊 행복 (happy)", "happy"),
            ("😢 슬픔 (sad)", "sad"),
            ("😠 분노 (angry)", "angry"),
            ("😨 공포 (fearful)", "fearful"),
            ("🤢 혐오 (disgusted)", "disgusted"),
            ("😲 놀람 (surprised)", "surprised"),
        ]
        for emotion in emotions {
            let item = NSMenuItem(title: emotion.label, action: #selector(testSpecificEmotion(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = emotion.key
            emotionSubmenu.addItem(item)
        }
        testEmotionItem.submenu = emotionSubmenu
        menu.addItem(testEmotionItem)

        let testDockItem = NSMenuItem(title: "Dock 점프 테스트", action: #selector(testDockStairs), keyEquivalent: "d")
        testDockItem.target = self
        menu.addItem(testDockItem)

        let settingsItem = NSMenuItem(title: "설정...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(.init(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func testHourly() {
        NotificationCenter.default.post(name: .tikiTimeHourlyAlert, object: nil)
    }

    @objc private func testSpecificEmotion(_ sender: NSMenuItem) {
        let emotion = sender.representedObject as? String
        NotificationCenter.default.post(
            name: .tikiTimeTestEmotion,
            object: nil,
            userInfo: emotion.map { ["emotion": $0] }
        )
    }

    @objc private func testDockStairs() {
        NotificationCenter.default.post(name: .tikiTimeTestDockStairs, object: nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: controller)
            window.title = "TikiTime 설정"
            window.styleMask = [NSWindow.StyleMask.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 620, height: 460))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
