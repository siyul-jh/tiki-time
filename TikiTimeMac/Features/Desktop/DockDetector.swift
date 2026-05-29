import AppKit
import CoreGraphics

struct DockInfo {
    let xRange: ClosedRange<CGFloat>
    let height: CGFloat
}

enum DockDetector {
    static func detect(on screen: NSScreen) -> DockInfo? {
        let dockHeight = screen.visibleFrame.minY - screen.frame.minY
        guard dockHeight > 0 else { return nil }
        let xRange = dockXRange(on: screen, dockHeight: dockHeight) ?? centerFallback(on: screen)
        return DockInfo(xRange: xRange, height: dockHeight)
    }

    // 말풍선 디버그: layer 20 창 전체 표시
    static func debugSummary(on screen: NSScreen) -> String {
        let dockHeight = screen.visibleFrame.minY - screen.frame.minY
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return "list nil"
        }
        let shelfLayer = Int(CGWindowLevelForKey(.dockWindow))
        let layer20 = windowList.filter { ($0[kCGWindowLayer as String] as? Int) == shelfLayer }
        if layer20.isEmpty { return "h:\(Int(dockHeight)) L20없음 total:\(windowList.count)" }
        var lines: [String] = ["h:\(Int(dockHeight))"]
        for w in layer20 {
            if let cf = w[kCGWindowBounds as String] as? NSDictionary {
                var r = CGRect.zero
                CGRectMakeWithDictionaryRepresentation(cf, &r)
                let owner = (w[kCGWindowOwnerName as String] as? String) ?? "?"
                lines.append("\(owner) \(Int(r.width))x\(Int(r.height))@\(Int(r.minX))")
            }
        }
        return lines.joined(separator: " | ")
    }

    // Dock 창 탐지 실패 시 화면 중앙 55% 를 추정 범위로 사용
    private static func centerFallback(on screen: NSScreen) -> ClosedRange<CGFloat> {
        let estimatedWidth = min(screen.frame.width * 0.55, 1600)
        let center = screen.frame.width / 2
        let start = max(0, center - estimatedWidth / 2)
        let end = min(screen.frame.width, center + estimatedWidth / 2)
        return start...end
    }

    private static func dockXRange(on screen: NSScreen, dockHeight: CGFloat) -> ClosedRange<CGFloat>? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }

        let mainScreenHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0

        struct Candidate {
            let xRange: ClosedRange<CGFloat>
            let width: CGFloat
        }
        var candidates: [Candidate] = []

        for window in windowList {
            guard let cfDict = window[kCGWindowBounds as String] as? NSDictionary else { continue }

            var quartzRect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(cfDict, &quartzRect) else { continue }

            // 좁은 shelf 형태: height가 dockHeight의 1.5배 이하, width가 height의 3배 이상
            guard quartzRect.height <= dockHeight * 1.5,
                  quartzRect.width > quartzRect.height * 3
            else { continue }

            let appKitY = mainScreenHeight - quartzRect.minY - quartzRect.height
            let appKitRect = CGRect(x: quartzRect.minX, y: appKitY, width: quartzRect.width, height: quartzRect.height)
            guard screen.frame.intersects(appKitRect) else { continue }

            // 화면 하단 근처(Dock 높이 + 여유 10pt)에 있어야 함
            guard appKitY < dockHeight + 10 else { continue }

            let screenLocalX = quartzRect.minX - screen.frame.minX
            let start = max(0, screenLocalX)
            let end = min(screen.frame.width, screenLocalX + quartzRect.width)
            guard start < end else { continue }

            candidates.append(Candidate(xRange: start...end, width: quartzRect.width))
        }

        // 가장 넓은 창 = 실제 아이콘 셸프
        return candidates.max(by: { $0.width < $1.width })?.xRange
    }
}
