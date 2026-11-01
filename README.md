<p align="center"><img src="Resources/Logo.png" alt="트랙패드의 달인" width="480"></p>

# 트랙패드의 달인 (Trackpad-no-Tatsujin)

맥북 트랙패드를 북처럼 두드리는 태고의 달인 스타일 리듬게임. 자세한 설계는 [SPEC.md](SPEC.md).

## 빠른 시작

**필요한 것:** macOS 14 (Sonoma) 이상, Apple Silicon 또는 Intel Mac. 트랙패드가 없으면 키보드로도 할 수 있다.

### 방법 1. 내려받기 (권장)

1. [Releases](https://github.com/sonbumsu/Trackpad-no-Tatsujin/releases/latest)에서 `Trackpad-no-Tatsujin-<버전>.dmg`를 받는다.
2. dmg를 열고 **트랙패드의 달인**을 **Applications** 폴더로 끌어다 놓는다.
3. 처음 열 때 "열 수 없음" 경고가 나오면 [INSTALL.md](INSTALL.md)의 안내를 따른다(개발자 인증을 받지 않은 앱이라 한 번 허용해야 한다).

### 방법 2. 직접 빌드

Xcode는 필요 없고 Command Line Tools만 있으면 된다.

```sh
xcode-select --install    # Command Line Tools가 없을 때만 (이미 있으면 안내 메시지가 나오고 끝남)
git clone https://github.com/sonbumsu/Trackpad-no-Tatsujin.git
cd Trackpad-no-Tatsujin
./build.sh run            # 빌드 후 실행
```

데모곡이 들어 있어서 바로 플레이할 수 있다. 처음에는 **설정 › 타이밍 보정**을 한 번 해 두는 것이 좋다.

## 조작

| 동작 | 트랙패드 (기본: 테두리형) | 키보드 |
|---|---|---|
| 동 | 가운데 영역 | F, J, Space |
| 캇 | 바깥 테두리 띠 | D, K |
| 대음표 보너스 | 같은 영역을 두 손가락으로 동시에 | 두 키 동시에 |
| 메뉴 이동 / 결정 | 왼쪽·오른쪽 테 / 가운데 | ← → / Enter |
| 일시정지 · 다시 | | Esc · R |

- 게임 중에는 커서를 창 가운데에 고정한다 (⌘L로 켜고 끄기, ⌘⌃F 전체 화면).
- 설정에서 입력 방식(테두리형/세로 띠형/좌우 분할형/손가락 수형)과 테 두께를 바꾸고, 오른쪽 미리보기로 바로 확인할 수 있다.
- 처음에는 **타이밍 보정**을 한 번 해 두는 것이 좋다.

## 곡 추가

음악 파일 하나만 있으면 된다. 아래 방법 중 하나로 넣으면 박자를 분석해서 네 난이도 채보를 자동으로 만든다.

- 음악 파일을 게임 창으로 **끌어다 놓기** (여러 개 한꺼번에 가능)
- 곡 선택 화면의 **＋ 음악 추가** 또는 **⌘O**

지원 형식은 mp3, m4a, aac, wav, aiff, flac이다. ogg는 macOS에서 열 수 없다. TJA 채보 파일이나 TJA가 든 곡 폴더를 넣으면 채보를 만들지 않고 그대로 가져온다.

가져온 곡은 `~/Library/Application Support/Trackpad-no-Tatsujin/Songs/<제목>/`에 음악 파일과 `song.tja`로 저장된다(곡 선택 화면에서 O로 폴더 열기). 자동 채보가 마음에 안 들면 `song.tja`를 직접 고치면 된다. 박이 어긋나면 `OFFSET`을, 너무 빠르거나 느리면 `BPM`을 고친다.

자동 채보의 한계: 템포가 일정한 곡을 가정한다. 라이브 연주처럼 템포가 흔들리는 곡이나 중간에 템포가 바뀌는 곡에서는 뒤로 갈수록 박이 어긋날 수 있다.

연타와 풍선은 드럼 필인(마디 끝에 16분음표가 빽빽한 곳)에만 넣는다. 그래서 필인이 없는 곡에는 들어가지 않고, 하이햇이 계속 16분으로 울리는 곡에서는 엉뚱한 곳에 들어갈 수 있다. 설정의 「자동 채보 연타·풍선」으로 끌 수 있고, 이미 가져온 곡에는 적용되지 않는다(다시 가져와야 한다).

## 개발

```sh
./build.sh           # 빌드만 (build/Trackpad-no-Tatsujin.app, 이 Mac의 아키텍처만)
./build.sh run       # 빌드 후 실행
./build.sh test      # Core 로직 자체 테스트
./build.sh release   # 배포용 유니버설 빌드 → dist/Trackpad-no-Tatsujin-<버전>.dmg
```

### 배포

`VERSION=0.2.0 ./build.sh release`로 dmg를 만들어 GitHub Releases에 올린다. dmg 안에는 사용자용 [INSTALL.md](INSTALL.md)가 「설치 방법.txt」로 들어간다.

- **서명 없이(무료):** 임시 서명만 된다. 사용자가 처음 한 번 「그래도 열기」를 눌러야 한다(INSTALL.md에 안내).
- **정식 서명(Apple Developer Program 연 $99):** Developer ID 인증서를 설치하고, 공증 자격 증명을 한 번 저장한 뒤 실행한다.
  ```sh
  xcrun notarytool store-credentials trackpad-no-tatsujin --apple-id <Apple ID> --team-id <TEAMID>
  SIGN_ID="Developer ID Application: <이름> (<TEAMID>)" NOTARY_PROFILE=trackpad-no-tatsujin ./build.sh release
  ```
- 번들 ID는 `BUNDLE_ID` 환경변수로 바꿀 수 있다(기본 `app.trackpad-no-tatsujin.mac`).
- 앱 아이콘은 [Tools/make_icon.swift](Tools/make_icon.swift)가 `Resources/Logo.png`를 둥근 사각형 타일에 얹어 그린 것이고 `Resources/AppIcon.icns`에 들어 있다. 로고를 바꾸면 `swiftc Tools/make_icon.swift -o .build/make_icon && .build/make_icon Resources/Logo.png icon.png`로 다시 그린 뒤 `iconutil`로 icns를 만든다.

### 구조

```
Sources/Core/   순수 로직 (AppKit 없음): Chart, TJAParser, GameSession(판정·점수·게이지), AutoCharter(자동 채보), Records, Synth, DemoSongs
Sources/App/    AppKit/SpriteKit: 트랙패드 입력(GameView), AudioService, SongImporter, Settings, 장면들(Scenes/)
Tests/main.swift  Core 자체 테스트 (XCTest 없이 동작)
```

### 현재 구현 범위 (SPEC 마일스톤 기준)

- M0~M4 구현: 트랙패드 입력, 노트 스크롤, 판정, 대음표·연타·풍선·고고타임, 점수·혼 게이지·왕관, TJA 읽기(분기는 달인 분기만), 곡 선택, 설정, 타이밍 보정, 기록 저장
- 아직 없음: 출력 장치별 오프셋 저장, 압력(Force Touch) 대음표, 손바닥 크기 필터, 분기 채보 전체 지원
