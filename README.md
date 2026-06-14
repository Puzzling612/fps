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

### B. 로컬 서버 (CI 없이)

1. Godot 4.6 에디터에서 **Project → Export → Web** 프리셋으로 `build/web/index.html` 내보내기.
2. 내보낸 폴더에서 정적 서버 실행:

   ```bash
   cd build/web && python3 -m http.server 8000
   ```
3. PC와 **같은 와이파이**의 폰 브라우저에서 `http://<PC의-LAN-IP>:8000` 접속.
