# Scoop을 이용한 Herdr Nightly 설치 및 가이드

이 문서는 개인 Fork 저장소(`joonhwan/herdr`)에서 자동 빌드되는 최신 **Herdr Windows Nightly Build**를 Windows 패키지 매니저인 **Scoop**을 사용하여 설치, 업데이트, 관리하는 안내서입니다.

---

## 1. 사전 준비 (Prerequisites)

- Windows 10 / 11 환경
- PowerShell 실행 권한
- Scoop 설치 여부 확인:
  ```powershell
  scoop --version
  ```
  *(Scoop이 설치되어 있지 않다면 `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` 실행 후 `iwr -useb get.scoop.sh | iex` 명령으로 설치할 수 있습니다.)*

---

## 2. Scoop Bucket 등록 (최초 1회)

내 Fork 저장소의 **`deploy` 브랜치**를 Scoop 커스텀 버킷으로 등록합니다.
*(URL 뒤에 `#deploy`를 붙여주어야 `deploy` 브랜치 매니페스트를 정확히 로드합니다.)*

```powershell
scoop bucket add my-herdr https://github.com/joonhwan/herdr.git#deploy
```

---

## 3. Herdr Nightly 설치 (Install)

Scoop 버킷 등록 후 아래 명령어로 설치합니다:

```powershell
scoop install herdr-nightly
```

### 💡 Shims 및 실행 위치 안내
- **실제 위치**: `%USERPROFILE%\scoop\apps\herdr-nightly\current\herdr.exe`
- **Shim 위치**: `%USERPROFILE%\scoop\shims\herdr.exe`
- Scoop이 `shims` 경로를 사용자 `PATH`에 등록하므로, **어느 폴더에서든 `herdr` 명령어로 즉시 실행** 가능합니다.

---

## 4. 최신 Nightly 버전으로 업데이트 (Update)

GitHub Actions에서 새로운 Nightly 빌드가 완료되면 아래 명령어로 최신 바이너리를 받으실 수 있습니다:

```powershell
# 모든 버킷 및 설치된 패키지 일괄 업데이트
scoop update

# 또는 herdr-nightly 전용 업데이트
scoop update herdr-nightly
```

*(강제 재설치가 필요한 경우: `scoop install --force herdr-nightly`)*

### 버전 체계 (동작 원리)

`bucket/herdr-nightly.json`은 **날짜 태그 릴리스를 그때그때 고정해서 가리킵니다.**

```json
"version": "2026.08.15-2319",
"url": ".../releases/download/nightly-2026.08.15-2319/herdr-windows-x86_64.zip",
"hash": "02bf5078..."
```

`.github/workflows/nightly.yml`이 빌드를 마치면 이 세 값을 새 태그로 갱신해서 `deploy`
브랜치에 되커밋합니다. Scoop은 버킷을 `git pull`한 뒤 매니페스트의 `version`이 설치된
버전보다 새로우면 업데이트하므로, 이렇게 버전이 매번 바뀌어야 `scoop update`가 동작합니다.

> `nightly` 고정 태그 릴리스는 "항상 최신" 다운로드 링크용으로 남아 있지만, Scoop은
> 더 이상 이 태그를 쓰지 않습니다. 매니페스트 `version`이 안 바뀌면 Scoop은 업데이트가
> 없다고 판단해서 그냥 넘어가고, 다운로드 캐시(`앱#버전#URL해시.zip`)도 옛 zip을
> 재사용하기 때문입니다.

Scoop의 `checkver` / `autoupdate` 필드는 일부러 넣지 않았습니다. 이 필드는 `scoop update`
때 실행되는 게 아니라 버킷 관리자가 매니페스트를 갱신할 때 쓰는 것이고, 여기서는 CI가
그 역할을 직접 하기 때문입니다.

---

## 5. 삭제 (Uninstall)

```powershell
# herdr-nightly 패키지 삭제
scoop uninstall herdr-nightly

# 등록한 버킷 삭제 (필요시)
scoop bucket rm my-herdr
```

---

## 6. 문제 해결 (Troubleshooting)

### Q1. `Couldn't find manifest for 'herdr-nightly'` 또는 Manifests 수량이 `0`인 경우
- Scoop이 기본 브랜치(`master`)로 머물러 있어 `deploy` 브랜치의 매니페스트를 읽지 못하는 현상일 수 있습니다.
- 아래 명령어로 버킷 저장소를 `deploy` 브랜치로 체크아웃해 주시면 해결됩니다:
  ```powershell
  git -C "$env:USERPROFILE\scoop\buckets\my-herdr" checkout deploy
  ```

### Q2. `scoop update herdr-nightly`가 아무것도 안 하고 넘어가는 경우

`scoop status`는 `Everything is ok!`인데 새 빌드가 분명히 올라와 있다면, 설치된 버전
문자열이 매니페스트 버전보다 크게 판정되고 있는 경우입니다. (예: 예전 `nightly-20260814`
방식으로 설치된 상태) 아래처럼 캐시를 지우고 강제 재설치하면 초기화됩니다.

```powershell
scoop cache rm herdr-nightly
scoop install -f herdr-nightly
```

캐시를 먼저 지워야 하는 이유는, Scoop 캐시 파일명이 `앱#버전#URL해시.zip`이라서 버전과
URL이 같으면 네트워크로 다시 받지 않고 옛 zip을 그대로 쓰기 때문입니다.

### Q3. 기존 공식 `herdr`와 바이너리 충돌이 발생하는 경우
- 만약 기존 공식 `herdr` 패키지가 Scoop으로 이미 설치되어 있다면 `shims/herdr.exe` 이름이 겹칠 수 있습니다.
- **해결방법 1 (추천)**: 기존 패키지 제거 후 nightly 설치
  ```powershell
  scoop uninstall herdr
  scoop install herdr-nightly
  ```
- **해결방법 2**: `scoop reset`으로 현재 적용할 브랜치 스위칭
  ```powershell
  scoop reset herdr-nightly   # Nightly 버전 활성화
  scoop reset herdr           # 공식 버전으로 원복
  ```
