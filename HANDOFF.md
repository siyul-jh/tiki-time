# TikiTime — 개발 핸드오프 문서

> 최종 업데이트: 2026-06-01
> 빌드 상태: **BUILD SUCCEEDED**

---

## 프로젝트 개요

macOS 데스크탑 마스코트 앱. 귀여운 캐릭터가 화면을 돌아다니며 정각 알림을 보여주고 AI와 대화할 수 있다.

| 항목 | 내용 |
|------|------|
| 경로 | `/Users/ljiheum/Developer/personal/tiki-time` |
| 빌드 | `xcodebuild -scheme TikiTimeMac -destination 'platform=macOS' build` |
| 대상 | macOS 14.0+, Swift 5.9 |

---

## 구현 완료 항목

### 핵심 아키텍처
- `LSUIElement: true` — Dock 없는 메뉴바 앱
- `DesktopWindow` — `canBecomeKey/Main = false`로 포커스 탈취 방지
- `DesktopSKView.hitTest` — 캐릭터 위에서만 이벤트 수신, 그 외 pass-through
- 다중 디스플레이 — 스크린별 독립 `DesktopWindowController` + `CharacterSpriteScene`
- Window level: `desktopIconWindow + 1`

### 캐릭터 시스템
- 메인 + 보조 캐릭터 병렬 `WalkBehavior` 상태 머신
- **메인 캐릭터**: 정각 메시지 알림 + 크로스 스크린 보행 이동
- **보조 캐릭터**: 정각 메시지 제외, 나머지 동작 메인과 동일
  - 독립 드래그 (`draggingSecondaryIndex`)
  - 독립 드롭 물리 (`isDropping`, `dropVelocity` per secondary)
  - 독립 크로스 스크린 드래그 (`tikiTimeSecondaryDragUpdate/End`)
  - 독립 idle/walk 메시지, 감정 애니메이션, AI 인터랙션

### 물리 엔진
- 낙하 중력: `dropGravity = -1500`, 캐릭터 크기 비례 탄성 (`weightedBounce`)
- Squash & Stretch 착지 (`playLand`) — xScale 부호 보존으로 방향 유지
- Dock 감지 & 계단 점프 물리 (`applyDockJump`, 15pt 선행 마진)

### 드래그 & 인터랙션
- 드래그 방향에 따른 캐릭터 flip 없음 (방향은 걷기 방향으로만 결정)
- `WalkBehavior.resume()` → `enterIdle()` — 드래그 후 이전 방향 유지
  - `playLand` xScale 부호 보존이 핵심 fix
- 크로스 스크린 드래그: 메인/보조 모두 지원

### 설정 UI
- 알림 패널: Toggle + Picker `LabeledContent` 통일로 우측 정렬
- 캐릭터 패널: 이미지 기반 캐릭터만 좌우반전 버튼 노출
- AI 패널: Gemini / OpenAI 공급자 선택, API 키 Keychain 저장
- 설정 변경 → `tikiTimeSettingsChanged` → 런타임 즉시 반영

### AI 인터랙션
- 클릭 → API 호출 → 감정(emotion) + 텍스트 말풍선
- API 키 없을 때: 랜덤 idle 메시지 + 감정 표출
- Gemini / OpenAI 공급자 모두 지원

---

## 알림 이름 (Notifications.swift)

| 이름 | 방향 | 용도 |
|------|------|------|
| `tikiTimeHourlyAlert` | → Scene | 메뉴바 테스트 트리거 |
| `tikiTimeSettingsChanged` | → Scene | 설정 실시간 반영 |
| `tikiTimeCharacterTransfer` | Scene ↔ Scene | 메인 캐릭터 보행 화면 이동 |
| `tikiTimeDragUpdate` | Scene ↔ Scene | 메인 크로스 드래그 위치 |
| `tikiTimeDragEnd` | Scene ↔ Scene | 메인 크로스 드래그 완료 |
| `tikiTimeSecondaryDragUpdate` | Scene ↔ Scene | 보조 크로스 드래그 위치 (`secondaryIndex` 포함) |
| `tikiTimeSecondaryDragEnd` | Scene ↔ Scene | 보조 크로스 드래그 완료 (`secondaryIndex` 포함) |
| `tikiTimeTestEmotion` | → Scene | 감정 테스트 |
| `tikiTimeTestDockStairs` | → Scene | Dock 계단 테스트 |

---

## 알려진 이슈 / 주의사항

| 항목 | 내용 |
|------|------|
| SourceKit 경고 | `No such module 'TikiTimeCore'` — false positive, 빌드는 정상 |
| git 미초기화 | `git init` 후 작업 권장 |
| xcodegen | `.xcodeproj` 직접 커밋하지 않는 경우 `xcodegen generate` 선행 필요 |

---

## 남은 작업 (우선순위 순)

### 즉시 작업 가능
없음 — 현재 MVP 기능 완성 상태.

### 다음 버전 (v1.1)
- iOS 타겟 추가 (`TikiTimeIOS/`, `project.yml`)
- WidgetKit: 다음 정각 카운트다운

### 다음 버전 (v2.0)
- 캐릭터 마켓플레이스 + StoreKit 2 구독
- 커스텀 이미지/사운드 manifest 포맷 확장

---

## 빠른 시작

```bash
cd /Users/ljiheum/Developer/personal/tiki-time
xcodegen generate   # .xcodeproj 재생성 필요 시
xcodebuild -scheme TikiTimeMac -destination 'platform=macOS' build 2>&1 | grep -E "(error:|BUILD)"
open TikiTime.xcodeproj
```
