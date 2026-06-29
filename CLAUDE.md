# TikiTime — Claude 작업 가이드

## 프로젝트 개요

macOS 데스크탑 마스코트 앱. 귀여운 캐릭터가 화면 위를 걸어다니며 정각 알림을 표시하고, 클릭하면 AI가 반응한다.

| 항목 | 내용 |
|------|------|
| 언어 | Swift 5.9, macOS 14.0+ |
| 빌드 도구 | XcodeGen (`project.yml` → `.xcodeproj`) |
| 번들 ID | `com.tikitime.mac` |
| 앱 스타일 | `LSUIElement: true` — Dock 없는 메뉴바 앱 |

## 빌드 & 검증

```bash
# 필요 시 xcodeproj 재생성
xcodegen generate

# 빌드 (오류 유무 확인)
xcodebuild -scheme TikiTimeMac -destination 'platform=macOS' build 2>&1 | grep -E "(error:|BUILD)"
```

> SourceKit의 `No such module 'TikiTimeCore'` 경고는 false positive — 실제 빌드에서는 정상.

## 디렉터리 구조

```
tiki-time/
├── project.yml                        # XcodeGen 설정
├── CLAUDE.md                          # 이 파일
├── HANDOFF.md                         # 개발 핸드오프 문서
├── Packages/TikiTimeCore/             # Swift Package (공유 모델)
│   └── Sources/TikiTimeCore/
│       ├── Models/
│       │   ├── Character.swift        # Character, CharacterManifest 모델
│       │   └── UserSettings.swift     # 설정 모델 + 영속성
│       └── Services/
│           └── NotificationService.swift  # UNUserNotificationCenter 래퍼
└── TikiTimeMac/
    ├── App/
    │   ├── TikiTimeMacApp.swift        # @main SwiftUI App
    │   ├── AppDelegate.swift           # 앱 초기화, 다중 디스플레이 설정
    │   └── Notifications.swift         # NSNotification.Name 확장
    ├── Features/
    │   ├── Desktop/
    │   │   ├── CharacterSpriteScene.swift  # 핵심: 게임 루프, 드래그, 물리
    │   │   ├── CharacterNode.swift          # SKNode 렌더링, 애니메이션, 말풍선
    │   │   ├── WalkBehavior.swift           # 이동 상태 머신
    │   │   ├── DesktopWindowController.swift # 투명 윈도우, 마우스 이벤트 필터
    │   │   └── DockDetector.swift           # Dock 위치·높이 감지
    │   ├── AI/
    │   │   ├── ClaudeAPIClient.swift        # Anthropic/OpenAI/Gemini API 클라이언트
    │   │   └── KeychainService.swift        # API 키 Keychain 저장/로드
    │   ├── Character/
    │   │   ├── CharacterStorageService.swift    # 캐릭터 파일 I/O (Application Support)
    │   │   ├── CharacterGenerationService.swift # AI로 스프라이트 시트 생성 + 배경 제거
    │   │   ├── CharacterSetupView.swift         # 새 캐릭터 추가 시트
    │   │   └── CharacterEditorView.swift        # 캐릭터 편집 시트
    │   ├── Settings/
    │   │   └── SettingsView.swift          # 설정 UI (알림·캐릭터·AI 패널)
    │   └── MenuBar/
    │       └── MenuBarController.swift     # 메뉴바 아이콘, 테스트 메뉴
    ├── Resources/
    │   └── Characters/default/
    │       └── manifest.json           # 기본 캐릭터 (아롬 🐈‍⬛) 번들 리소스
    └── Info.plist
```

## 핵심 모델 (TikiTimeCore)

### `CharacterManifest`
캐릭터 한 개의 메타데이터. `~/Library/Application Support/TikiTime/Characters/<id>/manifest.json`에 저장.

```swift
CharacterManifest(
    id: String,           // UUID (기본 캐릭터만 "default")
    displayName: String,
    version: String,
    emoji: String?,       // 이모지 기반 캐릭터일 때
    isImageBased: Bool,   // true면 이미지/스프라이트, false면 이모지
    animations: [String: [String]],    // state -> [frame relative paths]
    stateMessages: [String: [String]], // state -> [possible messages]
    footOffsetY: Double,  // 200×200 프레임 하단에서 발까지 Y 여백(px)
    footOffsetX: Double,  // X축 오프셋(px)
    walkSpeed: Double,    // pt/s (기본 70)
    hourlyGreetings: [String],  // 24개 — 메인 캐릭터 정각 메시지
    idleMessages: [String]      // idle/walk 중 랜덤 말풍선
)
```

**애니메이션 키**: `idle`, `walk`, `dance`, `happy`, `sad`, `angry`, `fearful`, `disgusted`, `surprised`

### `UserSettings`
`UserDefaults` (`com.tikitime.userSettings`)에 JSON으로 저장.

```swift
UserSettings(
    mainCharacterId: String,           // 정각 알림 담당
    secondaryCharacterIds: [String],   // 최대 5개 (총 최대 6개)
    flippedCharacterIds: [String],     // 좌우반전 적용된 캐릭터 ID
    isHourlyNotificationEnabled: Bool,
    notificationSound: String,         // "default" | "none" | "Tink" | "Ping" | "Glass" | "Bottle"
    characterScale: Double,            // 0.5 ~ 2.0 (기본 1.0)
    walkSpeed: WalkSpeed,              // .slow(50) | .normal(80) | .fast(130) pt/s
    aiProvider: AIProvider,            // .anthropic | .openai | .gemini
    geminiImageModel: String,          // 이미지 생성용 Gemini 모델
    hourlyMessages: [String]           // 커스텀 정각 메시지 풀
)
```

## 아키텍처

### 윈도우 스택
```
AppDelegate
  └── [DesktopWindowController × N화면]  (좌→우 인덱스 0, 1, 2...)
        ├── DesktopWindow (DesktopIconWindow + 1, 포커스 탈취 없음)
        └── DesktopSKView
              └── CharacterSpriteScene
                    ├── CharacterNode (메인)
                    ├── WalkBehavior (메인)
                    └── [SecondaryCharacter × M] (각자 CharacterNode + WalkBehavior)
```

- `NSApp.setActivationPolicy(.accessory)` — Dock 아이콘 없음
- `DesktopWindow.canBecomeKey/Main = false` — 포커스 탈취 방지
- `DesktopSKView.hitTest` — 캐릭터 위에서만 이벤트 수신, 그 외 pass-through
- `window.ignoresMouseEvents` — 커서가 캐릭터 바깥이면 true, 안이면 false (글로벌 마우스 모니터로 갱신)

### 다중 화면
화면은 `minX` 기준 좌→우 정렬. 각 화면마다 독립 `DesktopWindowController` + `CharacterSpriteScene`.
메인 캐릭터만 보행으로 화면 간 이동(`tikiTimeCharacterTransfer`) 지원.

## 캐릭터 시스템

### 메인 vs. 보조 캐릭터
| 기능 | 메인 | 보조 |
|------|------|------|
| 정각 메시지 알림 | ✓ | ✗ |
| 크로스 스크린 보행 이동 | ✓ | ✗ |
| 크로스 스크린 드래그 | ✓ | ✓ |
| idle/walk 메시지 | ✓ | ✓ |
| 감정 애니메이션 | ✓ | ✓ |
| AI 인터랙션 (클릭) | ✓ | ✓ |
| 독립 물리 드롭 | ✓ | ✓ (per-index) |

### 캐릭터 타입
- **이모지 기반** (`isImageBased: false`): `SKLabelNode`에 이모지 렌더링. 걷기 시 bob 애니메이션.
- **이미지 기반** (`isImageBased: true`): `SKSpriteNode`에 텍스처. walk/emotion 프레임 애니메이션.

## `WalkBehavior` 상태 머신

```
idle (1.5~4.0s) ──[35% 확률]──▶ idle
                 ──[65% 확률]──▶ walking(.left | .right, 3.0~7.0s)
walking ──[경계 도달]──▶ onTransfer (이웃 화면 있으면) or transitionNext
         ──[시간 만료]──▶ transitionNext
```

**중요 규칙**:
- `pause()`: `isPaused = true`, velocity = 0. **state는 변경하지 않음**.
- `resume()`: `enterIdle()` 호출 — 항상 idle 상태로 복귀.
- `enterFromEdge(traveling:)`: 크로스 스크린 보행 수신 시 가장자리에서 입장.
- `beginForcedRoundTrip(from:completion:)`: Dock 계단 테스트용 강제 왕복.

## `CharacterNode` 렌더링 규칙

- `face(_ direction:)` — **`playWalk()` 내부에서만 호출**. 드래그 중 절대 호출 금지.
- `playLand(intensity:)` — xScale 부호를 반드시 보존:
  ```swift
  let sign: CGFloat = target.xScale < 0 ? -1.0 : 1.0
  let squash = SKAction.scaleX(to: sign * (1 + clamped * 0.9), ...)
  ```
- `isFlipped: Bool` — 설정의 `flippedCharacterIds`로 제어. `face()` 내에서 방향을 반전.
- 말풍선은 `characterScale`과 무관하게 항상 고정 크기 (`counter-scale` 적용).
- `footOffsetX/Y` — 이미지 위치를 캐릭터 발 기준으로 보정.

## 드래그 상태 변수 (`CharacterSpriteScene`)

```swift
isDragging: Bool               // 드래그 진행 중
draggingSecondaryIndex: Int?   // nil=메인 드래그, Int=보조 캐릭터 인덱스
crossScreenTargetIndex: Int?   // 크로스 스크린 대상 스크린 인덱스 (메인·보조 공용)
isReceivingCrossDrag: Bool     // 이 씬이 메인 드래그를 수신 중
isReceivingSecondaryDragIndex: Int?  // 이 씬이 수신 중인 보조 드래그 인덱스
```

**update 루프 규칙**:
- `mainIsDragging = isDragging && draggingSecondaryIndex == nil` — 메인 드래그 중에만 메인 업데이트 중단.
- 보조 캐릭터 드래그 중에는 메인 캐릭터 정상 동작.
- 보조 캐릭터의 `onStateChange` 클로저는 `capturedIndex` (값 캡처)로 인덱스를 추적.

## 물리 엔진

### 낙하 드롭
```
dropGravity = -1500 pt/s²
bounce = impactSpeed × weightedBounce()   // 캐릭터 크기 비례 탄성
weightedBounce: 최대 180×180 기준 0.25, 작을수록 높게 튐
```

### Dock 계단 물리
`DockDetector.detect(on:)` → `DockInfo(xRange:, height:)` 반환.
캐릭터가 Dock X 범위 진입 시 **15pt 선행 마진**으로 미리 점프.
`snappedFloorY(forX:)`: Dock 범위 내면 `floorY + dock.height`, 아니면 `floorY`.

## AI 인터랙션

### 응답 흐름
```
캐릭터 클릭
  → API 키 없음: 랜덤 idle 메시지 + 감정 (이미지 기반만)
  → API 키 있음: AIAPIClient.respond() → JSON 파싱 → emotion + text
       → 감정 프레임 재생 + 말풍선 표시 (6초 후 복귀)
```

### AI 시스템 프롬프트 응답 형식
```json
{"emotion":"감정키","text":"한국어 한 문장 대사 (이모지 1개 포함)"}
```
감정키: `idle` | `happy` | `sad` | `angry` | `fearful` | `disgusted` | `surprised`

### 공급자별 모델
| 공급자 | 대화 모델 | 이미지 생성 |
|------|------|------|
| Anthropic | `claude-haiku-4-5-20251001` | 미지원 |
| OpenAI | `gpt-4o-mini` | `gpt-image-1` (multipart form-data) |
| Gemini | `gemini-2.0-flash` | 설정 가능 (기본 `gemini-2.5-flash-image`) |

### 캐릭터 생성 파이프라인 (`CharacterGenerationService`)
1. 원본 이미지 → 200×200 정규화 (`resizeToSquare`)
2. 각 애니메이션(7감정 + walk + dance = 9개)마다:
   - AI API로 1000×1000 스프라이트 시트 (5×5 그리드 = 25프레임) 생성
   - `sliceSpriteSheet`: 25개 200×200 셀로 분리
   - `removeBackground` (Vision `VNGenerateForegroundInstanceMaskRequest`, macOS 14+)
3. `CharacterManifest` 저장

## 알림 이름 (`Notifications.swift`)

| 이름 | 방향 | 용도 |
|------|------|------|
| `tikiTimeHourlyAlert` | MenuBar → Scene | 정각 알림 테스트 트리거 |
| `tikiTimeSettingsChanged` | SettingsView → Scene | 설정 실시간 반영 |
| `tikiTimeCharacterTransfer` | Scene ↔ Scene | 메인 캐릭터 보행 화면 이동 (`fromScreenIndex`, `direction`) |
| `tikiTimeDragUpdate` | Scene ↔ Scene | 메인 크로스 드래그 위치 (`activeScreenIndex`, `x`, `y`) |
| `tikiTimeDragEnd` | Scene ↔ Scene | 메인 크로스 드래그 완료 (`targetIndex`) |
| `tikiTimeSecondaryDragUpdate` | Scene ↔ Scene | 보조 크로스 드래그 위치 (`activeScreenIndex`, `secondaryIndex`, `x`, `y`) |
| `tikiTimeSecondaryDragEnd` | Scene ↔ Scene | 보조 크로스 드래그 완료 (`targetIndex`, `secondaryIndex`) |
| `tikiTimeTestEmotion` | MenuBar → Scene | 감정 테스트 (`emotion` 키 옵셔널) |
| `tikiTimeTestDockStairs` | MenuBar → Scene | Dock 계단 테스트 |

## 설정 UI (`SettingsView`)

3개 패널 (`NavigationSplitView`):
- **알림**: 매 정각 알림 토글, 소리 선택, 커스텀 메시지 풀 관리
- **캐릭터**: 캐릭터 목록 (메인 지정, 좌우반전, 편집, 삭제), 크기 슬라이더
- **AI**: 공급자 선택, API 키 Keychain 저장/삭제

`CharacterListRows`의 좌우반전 버튼은 `isImageBased == true`인 캐릭터에만 표시.

설정 변경 → `settings.save()` + `tikiTimeSettingsChanged` 포스트 → 런타임 즉시 반영.

## 데이터 저장 위치

| 데이터 | 저장 위치 |
|------|------|
| `UserSettings` | `UserDefaults` (`com.tikitime.userSettings`) |
| API 키 | Keychain (`com.tikitime` service, account = provider.rawValue) |
| 캐릭터 manifest | `~/Library/Application Support/TikiTime/Characters/<id>/manifest.json` |
| 캐릭터 이미지 | `~/Library/Application Support/TikiTime/Characters/<id>/animations/<state>/frame_N.png` |
| 기본 캐릭터 | 앱 번들 `Characters/default/manifest.json` (Application Support 없으면 폴백) |

## 주의사항 & 알려진 패턴

- **`face()` 호출 제한**: `playWalk()` 내에서만. 드래그 중 방향 전환 금지.
- **`playLand()` xScale 보존**: sign 추출 후 squash/restore에 적용 필수.
- **`WalkBehavior.pause()`**: state 변경 없음. `resume()`만 `enterIdle()` 호출.
- **보조 캐릭터 인덱스 캡처**: `capturedIndex = secondaryCharacters.count` 값 캡처로 클로저 안전성 보장.
- **`UserSettings.maxCharacters = 6`**: 메인 1 + 보조 최대 5.
- **`CharacterStorageService.delete(id:)`**: `"default"` ID는 삭제 거부.
- **화면 순서**: `NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }` — 항상 좌→우.
- `floorY = 4` (화면 하단 기준 y 오프셋, `DesktopWindowController`에서 설정).

## 향후 계획 (참고)

- **v1.1**: iOS 타겟 (`TikiTimeIOS/`), WidgetKit 정각 카운트다운
- **v2.0**: 캐릭터 마켓플레이스 + StoreKit 2 구독
