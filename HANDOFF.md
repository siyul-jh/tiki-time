# TikiTime — 개발 핸드오프 문서

> 최종 업데이트: 2026-05-22  
> 빌드 상태: **BUILD SUCCEEDED** (xcodebuild Debug)

---

## 프로젝트 개요

**TikiTime**은 macOS 데스크탑 마스코트 + 정각 알림 앱이다.  
레퍼런스: [Shimeji](https://kilkakon.com/shimeji/), [Kiwipet](https://github.com/Kiwwwicat/Kiwipet)

| 항목 | 내용 |
|------|------|
| 경로 | `/Users/ljiheum/Developer/personal/tiki-time` |
| 빌드 방법 | `xcodegen generate && xcodebuild -project TikiTime.xcodeproj -scheme TikiTimeMac -configuration Debug build` |
| 실행 방법 | Xcode에서 TikiTimeMac 스킴 Run (또는 빌드 산출물 직접 실행) |
| 배포 대상 | macOS 14.0+ |
| Swift 버전 | 5.9 |

---

## 확정된 전체 기능 로드맵

| 버전 | 기능 |
|------|------|
| **MVP (현재)** | 데스크탑 배회 + 정각 알림 (Mac) |
| v1.1 | iOS 앱 + WidgetKit + 알림 |
| v1.2 | AI 상호작용 (Claude API, 유료 — 사용자 API 키) |
| v2.0 | 캐릭터 스킨/페르소나 마켓플레이스 + StoreKit 2 Pro 구독 |

---

## 현재 구현 완료 항목

### ✅ 핵심 아키텍처

- **`LSUIElement: true`** — Dock 아이콘 없는 메뉴바 앱
- **`DesktopWindow: NSWindow`** — `canBecomeKey/Main = false`로 포커스 탈취 방지
- **`DesktopSKView: SKView`** — `hitTest` 오버라이드로 투명 영역 click-through 구현
- **Window level**: `CGWindowLevelForKey(.desktopIconWindow) + 1` — 모든 앱 창 뒤
- **정각 댄스 시**: `tikiTimeWillDance` → `.floating` 레벨 상승 → `tikiTimeDidDance` → 원복
- **멀티 디스플레이**: 모든 스크린의 union rect 하나의 투명 창 → 캐릭터가 디스플레이 경계를 자유롭게 이동

### ✅ 파일 구조

```
tiki-time/
├── project.yml                          # xcodegen 스펙
├── TikiTime.xcodeproj                   # 생성된 Xcode 프로젝트
├── Packages/
│   └── TikiTimeCore/                    # 공유 Swift Package (macOS 14+, iOS 17+)
│       └── Sources/TikiTimeCore/
│           ├── Models/Character.swift   # Character, AnimationKey
│           ├── Models/UserSettings.swift # UserSettings, WalkSpeed
│           └── Services/NotificationService.swift
└── TikiTimeMac/
    ├── App/
    │   ├── TikiTimeMacApp.swift         # @main, Settings scene
    │   ├── AppDelegate.swift            # 앱 생명주기, 멀티 디스플레이 관리
    │   └── Notifications.swift          # NSNotification.Name 확장
    ├── Features/
    │   ├── Desktop/
    │   │   ├── DesktopWindowController.swift  # 투명 SpriteKit 윈도우
    │   │   ├── CharacterSpriteScene.swift     # 게임 루프, 정각 스케줄링
    │   │   ├── CharacterNode.swift            # 이모지 캐릭터 + 애니메이션
    │   │   └── WalkBehavior.swift             # 이동 상태 머신
    │   ├── MenuBar/
    │   │   └── MenuBarController.swift        # 메뉴바 아이콘 + 메뉴
    │   └── Settings/
    │       └── SettingsView.swift             # SwiftUI 설정 화면
    └── Resources/
        └── Characters/default/manifest.json  # 기본 캐릭터 데이터
```

---

## 각 파일 핵심 내용

### `AppDelegate.swift`
```swift
// 멀티 디스플레이: 모든 스크린의 union rect로 단일 컨트롤러 생성
private func setupDesktopCharacters() {
    desktopControllers.forEach { $0.close() }
    let virtualFrame = NSScreen.screens.reduce(NSRect.null) { $0.union($1.frame) }
    let controller = DesktopWindowController(frame: virtualFrame)
    desktopControllers = [controller]
    controller.showWindow(nil)
}
```
- `NSApplication.didChangeScreenParametersNotification` 감지 → `setupDesktopCharacters()` 재호출

### `DesktopWindowController.swift`
```swift
init(frame: NSRect)   // 가상 데스크탑 전체 프레임 받음
// window level: desktopIconWindow + 1 (기본) / .floating (댄스 시)
// collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle]
```

### `CharacterSpriteScene.swift`
- `update(_:)`: `WalkBehavior.update(deltaTime:)` → `characterNode.position.x` 동기화
- `scheduleHourlyAnimation()`: `Calendar.nextDate(after:matching:)` → 정각 타이머
- `triggerHourlyAnimation()`: `tikiTimeWillDance` post → 댄스 → `tikiTimeDidDance` post
- `.tikiTimeHourlyAlert` 수신 → 즉시 댄스 (메뉴바 테스트 트리거)
- **⚠️ 현재 메시지 하드코딩됨** — `hourlyMessage(for:)` 직접 문자열 생성 (manifest.json 미연결)

### `CharacterNode.swift`
- 이모지 `🐱` 기반 `SKLabelNode`
- `playWalk(direction:)`: 상하 bob 애니메이션
- `playHourlyDance(message:completion:)`: 스핀 × 3 + 말풍선 + 스파클
- `playInteract()`: 점프 애니메이션 (클릭 시)
- `showSpeechBubble`: `SKShapeNode(rect:cornerRadius:)` + `SKColor.white`

### `WalkBehavior.swift`
- States: `idle` / `walking(WalkDirection)` / `dancing`
- `sceneBounds`: 경계 도달 시 방향 전환
- `pause()` / `resume()`: 댄스 중 이동 정지
- **⚠️ 현재 speed 하드코딩 `80`** — `UserSettings.walkSpeed` 미연결

### `UserSettings.swift` (TikiTimeCore)
```swift
struct UserSettings: Codable {
    var isHourlyNotificationEnabled: Bool  // 기본 true
    var isSoundEnabled: Bool               // 기본 true
    var walkSpeed: WalkSpeed               // .slow / .normal / .fast
    var characterScale: Double             // 0.5 ~ 2.0, 기본 1.0
}
// UserDefaults 저장: static func load() / func save()
```

### `manifest.json` (기본 캐릭터)
```json
{
  "id": "default",
  "displayName": "티키",
  "emoji": "🐱",
  "hourlyGreetings": ["오전 12시예요! ...", ...],  // 24개
  "idleMessages": ["심심하다~ 🥱", ...]            // 6개
}
```

---

## 남은 작업 (우선순위 순)

### 🔴 즉시 연결 필요 (MVP 완성)

#### 1. manifest.json → CharacterSpriteScene 연결
`CharacterSpriteScene.hourlyMessage(for:)`가 현재 하드코딩. manifest.json의 `hourlyGreetings`를 읽어서 사용해야 함.

```swift
// CharacterSpriteScene.swift에서 할 일
// 1. TikiTimeCore의 Character 모델 로드
// 2. character.hourlyGreetings[hour] 사용
// 현재 코드:
private func hourlyMessage(for hour: Int) -> String {
    let period = hour < 12 ? "오전" : "오후"
    let display = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
    return "\(period) \(display)시예요! 🎉"
}
```

**참고**: `TikiTimeCore/Models/Character.swift`에 `Character` 모델 존재.  
manifest.json은 `TikiTimeMac/Resources/Characters/default/manifest.json`.  
번들에서 JSON을 읽어 `Character`로 디코딩 → `hourlyGreetings` 배열 접근.

#### 2. UserSettings.walkSpeed → WalkBehavior 연결
설정 화면에서 걷기 속도를 바꿔도 실제 캐릭터 속도에 반영이 안 됨.

```swift
// WalkBehavior.init: speed 파라미터 있음 (기본값 80)
// CharacterSpriteScene.setupWalkBehavior()에서:
let speed: CGFloat = {
    switch UserSettings.load().walkSpeed {
    case .slow: return 50
    case .normal: return 80
    case .fast: return 130
    }
}()
walkBehavior = WalkBehavior(startX: ..., sceneBounds: ..., speed: speed)
// 설정 변경 시 실시간 반영: NotificationCenter로 walkSpeed 변경 알림 or
// update()마다 UserSettings.load()는 비효율적 → 설정 저장 시 NotificationCenter 브로드캐스트 추천
```

#### 3. UserSettings.characterScale → CharacterNode 연결
`characterScale` 값이 `CharacterNode.body.fontSize` 또는 `xScale/yScale`에 반영되지 않음.

```swift
// CharacterNode에 scale 적용 메서드 추가 또는
// CharacterSpriteScene에서 characterNode.setScale(UserSettings.load().characterScale)
```

### 🟡 품질 개선

#### 4. 설정 실시간 반영
현재 설정 저장 후 앱을 재시작하지 않으면 반영 안 됨.  
`NotificationCenter`로 `tikiTimeSettingsChanged` 알림 발행 → `CharacterSpriteScene`에서 수신 후 적용.

#### 5. 캐릭터 위치 Y축 (바닥 고정)
현재 `y: 120` 하드코딩. 실제 macOS 메뉴바 높이(보통 24~37pt)를 고려해 `NSScreen.main?.visibleFrame.minY + offset` 기준으로 바닥 위치 계산 권장.

#### 6. idle 메시지 랜덤 표시
manifest.json의 `idleMessages`를 일정 주기로 랜덤 표시하는 기능 미구현.  
`WalkBehavior`의 idle 진입 시 `CharacterNode.showSpeechBubble(text:)` 가끔 호출.

### 🟢 다음 버전

#### v1.1 — iOS 앱
- `TikiTimeMac/` 와 동급의 `TikiTimeIOS/` 타겟 추가 (`project.yml`)
- iOS 알림: `UNCalendarNotificationTrigger` (이미 `TikiTimeCore`에 구현됨)
- WidgetKit: 다음 정각까지 카운트다운 위젯

#### v1.2 — AI 상호작용
- 사용자 Claude API 키 입력 (Settings에 추가)
- 클릭 → AI 응답 → 말풍선 표시
- API 키는 Keychain 저장 (`Security` 프레임워크)

#### v2.0 — 마켓플레이스
- StoreKit 2 구독 모델
- 캐릭터 manifest.json 포맷 확장 (커스텀 이미지/사운드)
- 서버사이드 캐릭터 스토어

---

## 알려진 이슈 / 주의사항

| 항목 | 내용 |
|------|------|
| SourceKit 에러 | `CharacterSpriteScene`, `WalkState` 등 "not in scope" 에러는 **false positive** — 실제 빌드는 정상 |
| `requestPermission()` 경고 | `result of call to ... is unused` — `AppDelegate`에서 `Task { let granted = await ... }` 패턴 사용 중, 무해 |
| git 미초기화 | 현재 git repository가 아님. 작업 전 `git init` 권장 |
| xcodegen 필요 | `.xcodeproj`를 직접 커밋하지 않는다면 `xcodegen generate` 먼저 실행 |

---

## 빠른 시작 체크리스트

```bash
cd /Users/ljiheum/Developer/personal/tiki-time

# 1. 프로젝트 파일 재생성 (필요 시)
xcodegen generate

# 2. 빌드 확인
xcodebuild -project TikiTime.xcodeproj -scheme TikiTimeMac -configuration Debug build

# 3. Xcode에서 열기
open TikiTime.xcodeproj
```

다음 세션에서 이어할 첫 번째 작업: **manifest.json → hourlyGreetings 연결** (항목 #1)
