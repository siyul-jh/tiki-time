# TikiTime — Claude 작업 가이드

## 프로젝트 개요

macOS 데스크탑 마스코트 앱. SpriteKit 기반 물리 엔진 + 다중 디스플레이 크로스 드래그 + AI 인터랙션.

| 항목 | 내용 |
|------|------|
| 경로 | `/Users/ljiheum/Developer/personal/tiki-time` |
| 빌드 | `xcodebuild -scheme TikiTimeMac -destination 'platform=macOS' build` |
| 언어 | Swift 5.9, macOS 14.0+ |

## 빌드 검증

모든 코드 수정 후 반드시 빌드 확인:
```bash
xcodebuild -scheme TikiTimeMac -destination 'platform=macOS' build 2>&1 | grep -E "(error:|BUILD)"
```
SourceKit의 `No such module 'TikiTimeCore'` 경고는 false positive — 실제 빌드에서는 정상.

## 핵심 파일

| 파일 | 역할 |
|------|------|
| `CharacterSpriteScene.swift` | 게임 루프, 드래그·드롭, 물리, 다중 캐릭터 관리 |
| `CharacterNode.swift` | SKNode 렌더링, 애니메이션, 말풍선 |
| `WalkBehavior.swift` | 캐릭터 이동 상태 머신 |
| `DesktopWindowController.swift` | 투명 윈도우, 마우스 이벤트 필터 |
| `SettingsView.swift` | 설정 UI (알림·캐릭터·AI) |
| `Notifications.swift` | 전역 알림 이름 정의 |

## 캐릭터 시스템 핵심 규칙

- **메인 캐릭터**: 정각 메시지 알림 담당. 크로스 스크린 이동(보행) 지원.
- **보조 캐릭터**: 정각 메시지 없음. 그 외(걷기·idle 메시지·감정·AI·드래그)는 메인과 동일.
- **방향(xScale)**: `face()` 는 `playWalk()` 내에서만 호출. 드래그 중 절대 호출 금지.
- `playLand()` 는 xScale 부호를 반드시 보존 (`sign = target.xScale < 0 ? -1 : 1`).
- `WalkBehavior.pause()` 는 state를 변경하지 않음. `resume()` 은 `enterIdle()`로 복귀.

## 드래그 상태 변수

```swift
isDragging: Bool               // 드래그 진행 중
draggingSecondaryIndex: Int?   // nil=메인 드래그, Int=보조 캐릭터 인덱스
crossScreenTargetIndex: Int?   // 크로스 스크린 대상 스크린 인덱스 (메인·보조 공용)
isReceivingSecondaryDragIndex: Int?  // 이 씬이 수신 중인 보조 드래그 인덱스
```

## 알림 이름 (Notifications.swift)

| 이름 | 용도 |
|------|------|
| `tikiTimeSettingsChanged` | 설정 변경 → 런타임 즉시 반영 |
| `tikiTimeDragUpdate` | 메인 캐릭터 크로스 스크린 드래그 위치 |
| `tikiTimeDragEnd` | 메인 캐릭터 크로스 스크린 드래그 완료 |
| `tikiTimeSecondaryDragUpdate` | 보조 캐릭터 크로스 스크린 드래그 위치 |
| `tikiTimeSecondaryDragEnd` | 보조 캐릭터 크로스 스크린 드래그 완료 |
| `tikiTimeCharacterTransfer` | 메인 캐릭터 보행 중 화면 이동 |

## 주의사항

- `CharacterSpriteScene`의 update 루프: 메인 드래그(`draggingSecondaryIndex == nil`) 시에만 메인 캐릭터 업데이트 중단. 보조 드래그 중에는 메인 캐릭터 정상 동작.
- 보조 캐릭터의 `onStateChange` 클로저는 `capturedIndex`(값 캡처)로 인덱스 추적.
- `CharacterListRows`의 좌우반전 버튼은 이미지 기반 캐릭터(`isImageBased`)에만 표시.
