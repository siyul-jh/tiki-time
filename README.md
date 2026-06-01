# TikiTime
> **macOS 데스크탑 마스코트 & 지능형 정각 알림 시스템**

`TikiTime`은 귀여운 마스코트 캐릭터들이 데스크탑을 자유롭게 탐색하며, 매 정각마다 특별한 인터랙션과 알림으로 시간을 동반해 주는 macOS 전용 데스크탑 컴패니언 애플리케이션입니다.  
SpriteKit 기반 커스텀 2D 물리 엔진, 다중 디스플레이 크로스 드래그, 보안 키체인 연동 로컬 AI 인터랙션을 특징으로 합니다.

---

## 핵심 기술 구현 (Technical Highlights)

### 1. 투명 윈도우 인터랙션 투과 (Mouse Event Pass-Through)
- `DesktopWindow`: `canBecomeKey/Main = false`로 포커스 탈취 방지
- `DesktopSKView.hitTest(_:)` 오버라이드 — 캐릭터 위에서만 이벤트 수신, 그 외 투명 배경은 100% pass-through
- `NSEvent.addGlobalMonitorForEvents` 전역 모니터링 — 커서 위치에 따라 `ignoresMouseEvents` 실시간 토글
- **모든 캐릭터(메인 + 보조)** 히트 테스트 지원 (`isCharacterHit` 전체 순회)

### 2. 다중 디스플레이 전환 & 크로스 드래그 (Cross-Screen Space Bus)
- 모니터 레이아웃 자동 추적, 스크린별 독립 `DesktopWindowController` 생성
- 보행 화면 전환: `tikiTimeCharacterTransfer` 알림으로 인접 스크린으로 소유권 이식
- **메인 캐릭터 크로스 드래그**: `tikiTimeDragUpdate` / `tikiTimeDragEnd`
- **보조 캐릭터 크로스 드래그**: `tikiTimeSecondaryDragUpdate` / `tikiTimeSecondaryDragEnd` — 보조 캐릭터 독립 크로스 스크린 드래그 지원

### 3. 탄성 중력 물리 & Dock 충돌 감지
- 낙하 물리: `dropGravity = -1500`, `dropBounce = 0.25`, 캐릭터 크기 기반 `weightedBounce()` 연산
- Squash & Stretch 착지 애니메이션 (`playLand`) — **방향(xScale 부호) 보존** 처리
- `applyDockJump`: 시스템 Dock xRange/height 감지, 15pt 선행 마진 점프 물리

### 4. 독립 다중 캐릭터 시스템 (Multi-Agent Simulation)
- 메인 + 보조 캐릭터 각각 독립 `WalkBehavior` 상태 머신 병렬 실행
- **메인/보조 캐릭터 차이**: 메인만 정각 메시지 알림 담당, 나머지(걷기·클릭 반응·감정·AI·idle 메시지)는 동일
- 보조 캐릭터별 독립 드래그, 독립 드롭 물리, 독립 AI 인터랙션 지원
- `draggingSecondaryIndex` 로 메인/보조 드래그 구분 — 메인 드래그 중에도 보조 캐릭터 정상 동작

### 5. 반응형 설정 동기화 (Reactive Settings Sync)
- `tikiTimeSettingsChanged` 알림으로 크기(Scale), 걷기 속도, 좌우 반전을 앱 재시작 없이 실시간 적용

### 6. 드래그 방향 보존
- 드래그 중 방향 flip 제거 (`face()` 호출 삭제)
- `WalkBehavior.resume()` 후 idle → walk 전환 시 착지 애니메이션이 방향을 초기화하지 않도록 `playLand`에서 xScale 부호 보존

---

## 아키텍처

```
AppDelegate (Screen Tracker & Lifecycle)
    └── DesktopWindowController × N screens
            └── DesktopSKView (Dynamic Event Filter)
                    └── CharacterSpriteScene (Physics & Game Loop)
                            ├── WalkBehavior × (1 main + N secondary)
                            └── CharacterNode × (1 main + N secondary)

TikiTimeCore (Shared Package)
    ├── Models/CharacterManifest
    ├── Models/UserSettings
    └── Services/NotificationService
```

---

## 프로젝트 구조

```
tiki-time/
├── project.yml                           # XcodeGen 선언 명세
├── Packages/
│   └── TikiTimeCore/                     # 공유 Swift Package
│       └── Sources/TikiTimeCore/
│           ├── Models/Character.swift    # CharacterManifest
│           ├── Models/UserSettings.swift
│           └── Services/NotificationService.swift
└── TikiTimeMac/
    ├── App/
    │   ├── TikiTimeMacApp.swift
    │   ├── AppDelegate.swift             # 멀티 디스플레이 관리
    │   └── Notifications.swift           # 전역 알림 식별자
    ├── Features/
    │   ├── Desktop/
    │   │   ├── DesktopWindowController.swift
    │   │   ├── CharacterSpriteScene.swift  # 핵심 게임 루프
    │   │   ├── CharacterNode.swift
    │   │   └── WalkBehavior.swift
    │   ├── MenuBar/
    │   │   └── MenuBarController.swift
    │   └── Settings/
    │       └── SettingsView.swift
    └── Resources/
        └── Characters/default/manifest.json
```

---

## 빠른 시작

```bash
# 요구사항: macOS 14.0+, Xcode 15+, xcodegen (brew install xcodegen)

cd /path/to/tiki-time
xcodegen generate
xcodebuild -scheme TikiTimeMac -destination 'platform=macOS' build
open TikiTime.xcodeproj
```

---

## 로드맵

| 버전 | 내용 |
|------|------|
| MVP (현재) | 데스크탑 배회 + 정각 알림 + AI 클릭 반응 + 다중 캐릭터 |
| v1.1 | iOS 앱 + WidgetKit |
| v2.0 | 캐릭터 마켓플레이스 + StoreKit 2 구독 |
