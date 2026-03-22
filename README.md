# ShinkiliAddon

## 목차 Table of Contents

- [개요 Overview](#overview)
- [주요 기능 Features](#features)
- [프로젝트 구조 Project Structure](#project-structure)
- [로컬 설치 대상 Local Install Target](#local-install-target)
- [개발 Development](#development)
- [비고 Notes](#notes)

<a id="overview"></a>
## 개요 Overview

`Shinkili`는 Blizzard Assisted Combat 추천 주문을 사용자 정의 색상 신호로 바꿔 보여주는 World of Warcraft 애드온입니다.

`Shinkili` is a World of Warcraft addon that turns Blizzard Assisted Combat recommendations into configurable visual signals.

<a id="features"></a>
## 주요 기능 Features

- 추천 주문을 사용자 지정 색상에 매핑합니다.
- 미리 여러 빈 슬롯을 두지 않고 검색 중심 편집 흐름을 제공합니다.
- 저장된 주문별로 보조 마커, GCD spiral, 선택적 `Move Glow`를 표시할 수 있습니다.
- 캐스팅, 채널링, 강화 상태용 예약색 오버라이드를 지원합니다.
- 메인 인디케이터의 크기와 위치를 조정할 수 있습니다.

- Maps recommended spells to user-selected colors.
- Uses a search-first editing flow instead of preallocated empty slots.
- Supports a helper marker, GCD spiral, and optional move glow per saved spell.
- Supports reserved color overrides for casting, channeling, and empower states.
- Includes size and position controls for the main indicator.

<a id="project-structure"></a>
## 프로젝트 구조 Project Structure

- [`Shinkili/Shinkili.toc`](./Shinkili/Shinkili.toc)
- [`Shinkili/Shinkili.lua`](./Shinkili/Shinkili.lua)
- [`scripts/sync_to_wow.sh`](./scripts/sync_to_wow.sh)

<a id="local-install-target"></a>
## 로컬 설치 대상 Local Install Target

동기화 스크립트는 아래 경로로 파일을 복사합니다.

The sync script copies files to the path below.

`/Applications/World of Warcraft/_retail_/Interface/AddOns/Shinkili`

<a id="development"></a>
## 개발 Development

애드온 파일을 WoW AddOns 디렉터리로 동기화합니다.

Sync the addon files into the WoW AddOns directory.

```bash
./scripts/sync_to_wow.sh
```

게임 내 UI를 다시 불러옵니다.

Reload the UI in game.

```text
/reload
```

설정 창을 엽니다.

Open the addon settings.

```text
/sk
```

<a id="notes"></a>
## 비고 Notes

- 이 저장소는 애드온 소스 파일과 로컬 동기화 스크립트만 추적합니다.
- 애드온은 추천 기반 메인 인디케이터를 제공합니다.
- 추천 주문 표시 가능 여부는 Blizzard Assisted Combat 제공 상태에 따라 달라집니다.

- This repository tracks only the addon source files and the local sync helper.
- The addon provides a recommendation-driven main indicator.
- Recommendation availability depends on Blizzard Assisted Combat being available.
