import Foundation

extension NSNotification.Name {
    static let tikiTimeHourlyAlert       = NSNotification.Name("com.tikitime.hourlyAlert")
    static let tikiTimeSettingsChanged   = NSNotification.Name("com.tikitime.settingsChanged")
    static let tikiTimeCharacterTransfer = NSNotification.Name("com.tikitime.characterTransfer")
    static let tikiTimeTestEmotion       = NSNotification.Name("com.tikitime.testEmotion")
    static let tikiTimeTestDockStairs    = NSNotification.Name("com.tikitime.testDockStairs")
    static let tikiTimeDragUpdate        = NSNotification.Name("com.tikitime.dragUpdate")
    static let tikiTimeDragEnd           = NSNotification.Name("com.tikitime.dragEnd")
}
