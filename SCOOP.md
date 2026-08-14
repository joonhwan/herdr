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

### Q2. 기존 공식 `herdr`와 바이너리 충돌이 발생하는 경우
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
