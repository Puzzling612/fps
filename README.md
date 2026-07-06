# FPS 프로젝트

간단한 **Godot 4 기반 FPS 예제 프로젝트**입니다.

## 요구 사항

- [Godot 4](https://godotengine.org/download) 설치

## 설치 및 실행

1. Godot 4를 다운로드 및 설치합니다.  
2. 프로젝트를 클론합니다:

   ```bash
   git clone <repository_url>
3. 클론한 폴더에서 project.godot 파일을 가져와 Godot에서 Import 합니다.
4. Godot 에디터에서 F5 키를 눌러 실행합니다.

## 모바일(터치) 플레이

데스크톱은 기존대로 마우스/키보드로 동작합니다. **터치 기기**(폰·태블릿·터치 웹)에서는 자동으로 온스크린 컨트롤이 켜집니다.

- **좌측 화면**: 가상 조이스틱(이동). 끝까지 밀면 자동 질주.
- **우측 화면 드래그**: 시점(룩).
- **버튼**(우하단): `FIRE`(누르는 동안 발사)·`ADS`(토글 조준)·`JMP`(점프)·`RLD`(재장전)·`NADE`(수류탄)·`MLE`(근접)·`WPN`(무기 전환)·`CRO`(토글 웅크림).
- 게임오버/승리 화면에서는 **아무 곳이나 탭** → 메뉴로.

> 동작 방식: 터치는 기존 입력 액션(`move_*`, `shoot`, `aim` …)을 그대로 구동하고, 시점만 `player.gd`의 `apply_look()`을 공유합니다. 터치 UI는 `scripts/touch_controls.gd` 한 파일로 격리되어 있고 데스크톱에선 스스로 비활성화되므로, 이후 게임플레이 코드를 수정해도 이 부분과 충돌하지 않습니다. (에디터에서 터치 UI를 강제로 켜 테스트하려면 실행 인자에 `--touch` 추가)

## 폰에서 테스트 플레이하는 법

### A. GitHub Pages 자동 배포 (추천)

`gamelike` 브랜치에 push하면 GitHub Actions가 웹 빌드를 만들어 Pages에 배포합니다.

1. **최초 1회**: 저장소 **Settings → Pages → Build and deployment → Source = "GitHub Actions"** 로 설정.
2. `gamelike`에 push → **Actions** 탭에서 `Deploy Web build to GitHub Pages` 워크플로우 완료를 확인.
3. 폰 브라우저에서 **`https://puzzling612.github.io/fps/`** 접속 → 가로로 돌려서 플레이. (이후 push마다 자동 갱신)

## PC용 다운로드 & 설치 (Windows / macOS)

실행 파일은 용량 제한(100MB) 때문에 **저장소 안에 들어있지 않습니다.** 대신 push마다 CI가 자동으로 빌드해 **GitHub Actions 아티팩트**로 올립니다.

**다운로드 (공통)**
1. GitHub 저장소 → **Actions** 탭
2. 목록 맨 위의 최신 초록색(✓) 실행 클릭
3. 페이지 하단 **Artifacts** 섹션에서 받기 (아티팩트는 90일 보관; 만료됐으면 Actions에서 `Run workflow`로 재빌드)

**Windows 설치**
1. `FPS-windows-x86_64` 다운로드 → 압축 해제
2. `FPS.exe` 더블클릭 (단일 파일, 설치 불필요)
3. "Windows의 PC 보호(SmartScreen)" 창이 뜨면 **추가 정보 → 실행** 클릭 (서명 없는 개인 빌드라 뜨는 정상 경고)

**macOS 설치**
1. `FPS-macos-universal` 다운로드 → 압축 해제 → `FPS.app`을 원하는 곳(예: 응용 프로그램)에 이동
2. 첫 실행은 **우클릭(Ctrl+클릭) → 열기 → 열기** (더블클릭하면 "확인되지 않은 개발자" 경고로 차단됨 — Apple 공증이 없는 개인 빌드라 정상)
3. 그래도 차단되면 터미널에서: `xattr -cr /경로/FPS.app` 후 다시 실행
- Intel/Apple Silicon 모두 지원(유니버설 바이너리)

**직접 빌드 (Godot 4.6 에디터)**
- Project → Export → **Windows** 또는 **macOS** 프리셋 → Export Project. (최초 1회 Editor → Manage Export Templates에서 템플릿 설치 필요)

### B. 로컬 서버 (CI 없이)

1. Godot 4.6 에디터에서 **Project → Export → Web** 프리셋으로 `build/web/index.html` 내보내기.
2. 내보낸 폴더에서 정적 서버 실행:

   ```bash
   cd build/web && python3 -m http.server 8000
   ```
3. PC와 **같은 와이파이**의 폰 브라우저에서 `http://<PC의-LAN-IP>:8000` 접속.
