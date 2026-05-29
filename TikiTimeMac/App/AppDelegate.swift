import AppKit
import CoreGraphics
import TikiTimeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var desktopControllers: [DesktopWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        requestScreenRecordingPermissionIfNeeded()

        Task {
            let granted = await NotificationService.shared.requestPermission()
            let settings = UserSettings.load()
            if granted && settings.isHourlyNotificationEnabled {
                let greetings = CharacterStorageService.loadManifest(id: settings.mainCharacterId)?.hourlyGreetings ?? []
                NotificationService.shared.scheduleHourlyNotifications(greetings: greetings, sound: settings.notificationSound)
            }
        }

        menuBarController = MenuBarController()
        setupDesktopCharacters()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationService.shared.cancelHourlyNotifications()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func screensChanged() {
        setupDesktopCharacters()
    }

    private func requestScreenRecordingPermissionIfNeeded() {
        guard !CGPreflightScreenCaptureAccess() else { return }
        CGRequestScreenCaptureAccess()
    }

    private func setupDesktopCharacters() {
        desktopControllers.forEach { $0.close() }
        // 좌→우 순으로 정렬해 인접 스크린 인덱스 결정
        let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        desktopControllers = screens.enumerated().map { index, screen in
            let controller = DesktopWindowController(
                screen: screen,
                screenIndex: index,
                hasLeftNeighbor: index > 0,
                hasRightNeighbor: index < screens.count - 1,
                isActive: index == 0
            )
            controller.showWindow(nil)
            return controller
        }
    }
}
