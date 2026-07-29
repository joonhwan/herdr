#requires -Version 5.1
<#
.SYNOPSIS
    herdr master를 직접 빌드해 최신 ConPTY 꾸러미와 함께 이 PC에 설치한다.

.DESCRIPTION
    빌드 -> ConPTY 꾸러미 준비 -> 별도 폴더에 설치 -> PATH 앞자리 -> 배치 검증까지
    한 번에 처리한다. 릴리스 설치본(%LOCALAPPDATA%\Programs\Herdr\bin, 정션)은
    건드리지 않으므로 herdr update 와 서로 간섭하지 않는다.

.EXAMPLE
    .\install-local.ps1
    빌드부터 설치까지 전부 실행한다.

.EXAMPLE
    .\install-local.ps1 -DryRun
    무엇을 할지만 출력하고 아무것도 바꾸지 않는다.

.EXAMPLE
    .\install-local.ps1 -SkipBuild -Verify
    이미 빌드된 target\release\herdr.exe 를 설치하고, 임시 세션을 띄워
    실제로 꾸러미가 불려오는지까지 확인한다.

.NOTES
    저장소 루트에 두어도, .local\ 같은 하위 폴더에 두어도 동작한다.
    Cargo.toml 이 있는 자리까지 올라가며 저장소를 찾는다.
    중간 산출물(nupkg, 준비 폴더)은 git 이 무시하는 .local\ 아래에 만든다.
#>
[CmdletBinding()]
param(
    # 설치할 폴더. 릴리스 설치본과 분리된 자리를 기본으로 쓴다.
    [string] $Dest = "$env:LOCALAPPDATA\Programs\Herdr-master\bin",

    # ConPTY nupkg 를 받아 둘 자리. 한 번 받으면 다음부터는 해시만 검사한다.
    [string] $Nupkg,

    # 판 문자열에 붙는 표식. 릴리스본과 구별하는 용도라 'preview' 는 쓰지 않는다.
    [string] $BuildChannel = 'local',
    [string] $BuildId,

    # 이미 빌드된 target\release\herdr.exe 를 그대로 쓴다.
    [switch] $SkipBuild,

    # PATH 를 건드리지 않는다.
    [switch] $SkipPath,

    # 설치 대상 exe 를 쓰고 있는 herdr 서버를 내린다.
    [switch] $StopServer,

    # 임시 세션을 띄워 실제로 어느 ConPTY 가 불려오는지 확인한다.
    [switch] $Verify,

    # 아무것도 바꾸지 않고 계획만 출력한다.
    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------- 출력 도우미

function Write-Step { param([string] $Text) Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Write-Info { param([string] $Text) Write-Host "    $Text" -ForegroundColor DarkGray }
function Write-Ok { param([string] $Text) Write-Host "  + $Text" -ForegroundColor Green }
function Write-Note { param([string] $Text) Write-Host "  ! $Text" -ForegroundColor Yellow }

function Stop-WithReason {
    param([string] $Text, [string] $Hint)
    Write-Host "  x $Text" -ForegroundColor Red
    if ($Hint) { Write-Host "    $Hint" -ForegroundColor DarkGray }
    exit 1
}

function Invoke-Native {
    param([string] $File, [string[]] $Arguments, [string] $What)
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        Stop-WithReason "$What 실패 (종료 코드 $LASTEXITCODE)"
    }
}

# Get-Process 의 Path 는 접근 권한에 따라 예외를 던질 수 있어 CIM 으로 읽는다.
function Get-HerdrProcess {
    @(Get-CimInstance Win32_Process -Filter "Name='herdr.exe'" -ErrorAction SilentlyContinue)
}

# ----------------------------------------------------------------- 0. 저장소

function Find-RepositoryRoot {
    param([string] $StartAt)
    $candidate = $StartAt
    while ($candidate) {
        if ((Test-Path (Join-Path $candidate 'Cargo.toml')) -and
            (Test-Path (Join-Path $candidate 'src\main.rs'))) {
            return $candidate
        }
        $parent = Split-Path -Parent $candidate
        if (-not $parent -or ($parent -eq $candidate)) { return $null }
        $candidate = $parent
    }
    return $null
}

$repo = Find-RepositoryRoot -StartAt $PSScriptRoot
if (-not $repo) {
    Stop-WithReason "herdr 저장소를 찾지 못했다 (기준: $PSScriptRoot)" `
        "이 스크립트는 herdr 저장소 안에 두고 실행한다 (루트나 .local\ 어디든 된다)."
}

$builtExe = Join-Path $repo 'target\release\herdr.exe'
$stageDir = Join-Path $repo '.local\conpty-stage'
$packager = Join-Path $repo 'scripts\package_windows_conpty.py'

if ([string]::IsNullOrWhiteSpace($Nupkg)) {
    $Nupkg = Join-Path $repo '.local\conpty\Microsoft.Windows.Console.ConPTY.nupkg'
}

$Dest = $Dest.TrimEnd('\')
$destExe = Join-Path $Dest 'herdr.exe'
$destBundle = Join-Path $Dest 'conpty'

Write-Host "herdr 로컬 설치" -ForegroundColor White
Write-Info "저장소   $repo"
Write-Info "설치 위치 $Dest"

# ----------------------------------------------------------------- 1. 사전 점검

Write-Step "준비물 점검"

foreach ($tool in @('git', 'cargo', 'python')) {
    $found = Get-Command $tool -ErrorAction SilentlyContinue
    if (-not $found) { Stop-WithReason "$tool 을 찾지 못했다" }
    Write-Ok "$tool  $($found.Source)"
}

if (-not (Test-Path $packager)) {
    Stop-WithReason "패키징 스크립트가 없다: $packager"
}

# Zig 판. build.rs 는 ZIG 환경 변수가 있으면 그 실행 파일을 쓴다.
$zigCommand = if ($env:ZIG) { $env:ZIG } else { 'zig' }
# Select-Object -First 1 은 파이프라인을 끊어 $LASTEXITCODE 를 남기지 않으므로 배열로 받는다.
$zigOutput = @(& $zigCommand version 2>$null)
if ($zigOutput.Count -eq 0) {
    Stop-WithReason "zig 을 실행할 수 없다 ($zigCommand)" "scoop install zig@0.15.2"
}
$zigVersion = ([string]$zigOutput[0]).Trim()
$zigMatch = [regex]::Match($zigVersion, '^0\.15\.(\d+)')
if (-not $zigMatch.Success) {
    Stop-WithReason "Zig $zigVersion 은 쓸 수 없다 (0.15.2 이상 0.15.x 필요)" "scoop install zig@0.15.2 또는 `$env:ZIG 로 해당 exe 지정"
}
if ([int]$zigMatch.Groups[1].Value -lt 2) {
    Stop-WithReason "Zig $zigVersion 은 쓸 수 없다 (0.15.2 이상 필요)"
}
Write-Ok "zig  $zigVersion"

# Zig 전역 캐시가 소스와 다른 드라이브면 빌드 도중 Run 단계에서 멈춘다.
if ([string]::IsNullOrWhiteSpace($env:ZIG_GLOBAL_CACHE_DIR)) {
    Write-Note "ZIG_GLOBAL_CACHE_DIR 가 비어 있다. 기본값은 C: 아래이고, 소스가 $((Split-Path -Qualifier $repo)) 이면 빌드가 멈춘다."
    Write-Info "권장: setx ZIG_GLOBAL_CACHE_DIR $((Split-Path -Qualifier $repo))\workspace\.zig-cache"
} else {
    $cacheDrive = Split-Path -Qualifier $env:ZIG_GLOBAL_CACHE_DIR
    $repoDrive = Split-Path -Qualifier $repo
    if ($cacheDrive -ne $repoDrive) {
        Write-Note "Zig 캐시($cacheDrive)와 소스($repoDrive)의 드라이브가 다르다. 빌드가 Run 단계에서 멈출 수 있다."
    } else {
        Write-Ok "zig 캐시  $env:ZIG_GLOBAL_CACHE_DIR"
    }
}

# 빌드 표식
$branch = (& git -C $repo rev-parse --abbrev-ref HEAD).Trim()
$sha = (& git -C $repo rev-parse --short HEAD).Trim()
$dirty = @(& git -C $repo status --porcelain).Count -gt 0
if ([string]::IsNullOrWhiteSpace($BuildId)) {
    $BuildId = "$branch-$sha"
    if ($dirty) { $BuildId = "$BuildId-dirty" }
}
$BuildId = $BuildId -replace '[^0-9A-Za-z._-]', '-'
$expectedVersionHint = "<Cargo 판>-$BuildChannel.$BuildId"
Write-Ok "빌드 표식  $BuildChannel / $BuildId"
if ($dirty) { Write-Note "작업 트리에 커밋되지 않은 변경이 있다 (표식에 -dirty 를 붙였다)." }

# 설치 대상을 쓰고 있는 서버.
# 함수 반환값은 파이프라인에서 풀리므로(0개면 $null, 1개면 스칼라) 배열로 다시 감싼다.
$running = @(Get-HerdrProcess)
$destInUse = @($running | Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -eq $destExe) }).Count -gt 0
if ($running.Count -gt 0) {
    Write-Note "herdr 프로세스 $($running.Count)개가 실행 중이다: $(($running | ForEach-Object { $_.ProcessId }) -join ', ')"
    if ($destInUse) {
        if (-not $StopServer -and -not $DryRun) {
            Stop-WithReason "설치 대상 exe 가 실행 중이라 덮어쓸 수 없다" "herdr server stop 을 먼저 실행하거나 -StopServer 를 붙인다."
        }
    } else {
        Write-Info "설치 대상과 다른 exe 다. 판이 섞이지 않도록 설치 후 서버를 새로 시작하는 편이 좋다."
    }
}

# ----------------------------------------------------------------- 계획만 출력

if ($DryRun) {
    Write-Step "계획 (아무것도 바꾸지 않는다)"
    if ($SkipBuild) {
        Write-Info "빌드 건너뜀 — $builtExe 를 그대로 쓴다"
    } else {
        Write-Info "빌드      cargo build --release --locked --bin herdr"
        Write-Info "          HERDR_BUILD_CHANNEL=$BuildChannel HERDR_BUILD_ID=$BuildId"
        Write-Info "          판 문자열은 $expectedVersionHint 꼴이 된다"
    }
    Write-Info "꾸러미    python scripts\package_windows_conpty.py stage"
    Write-Info "          nupkg  $Nupkg"
    Write-Info "          준비    $stageDir (있으면 지운다)"
    if ($destInUse) { Write-Info "서버      $destExe 를 쓰는 서버를 내린다" }
    Write-Info "설치      $destExe"
    Write-Info "          $destBundle\ (conpty.dll, herdr-conpty.json, x64\, arm64\)"
    if ($SkipPath) {
        Write-Info "PATH      건드리지 않는다"
    } else {
        Write-Info "PATH      사용자 PATH 앞자리에 $Dest 를 둔다"
    }
    if ($Verify) { Write-Info "검증      임시 세션을 띄워 불려온 ConPTY 를 확인한다" }
    Write-Host ""
    exit 0
}

# ----------------------------------------------------------------- 2. 빌드

if ($SkipBuild) {
    Write-Step "빌드 건너뜀"
    if (-not (Test-Path $builtExe)) {
        Stop-WithReason "빌드 결과가 없다: $builtExe" "-SkipBuild 를 빼고 다시 실행한다."
    }
    Write-Ok "$builtExe ($([math]::Round((Get-Item $builtExe).Length / 1MB, 1)) MB, $((Get-Item $builtExe).LastWriteTime))"
} else {
    Write-Step "빌드"
    $env:HERDR_BUILD_CHANNEL = $BuildChannel
    $env:HERDR_BUILD_ID = $BuildId
    Push-Location $repo
    try {
        Invoke-Native 'cargo' @('build', '--release', '--locked', '--bin', 'herdr') 'cargo build'
    } finally {
        Pop-Location
    }
    if (-not (Test-Path $builtExe)) { Stop-WithReason "빌드는 끝났는데 결과가 없다: $builtExe" }
    Write-Ok "$builtExe"
}

# ----------------------------------------------------------------- 3. ConPTY 꾸러미

Write-Step "ConPTY 꾸러미 준비"

$nupkgDir = Split-Path -Parent $Nupkg
if (-not (Test-Path $nupkgDir)) { New-Item -ItemType Directory -Force $nupkgDir | Out-Null }
if (Test-Path $Nupkg) {
    Write-Info "nupkg 가 이미 있다 (해시만 검사한다): $Nupkg"
} else {
    Write-Info "nupkg 를 받는다: $Nupkg"
}

if (Test-Path $stageDir) { Remove-Item -Recurse -Force $stageDir }

Push-Location $repo
try {
    Invoke-Native 'python' @(
        $packager, 'stage',
        '--package', $Nupkg,
        '--herdr-exe', $builtExe,
        '--output-dir', $stageDir
    ) '꾸러미 준비'
} finally {
    Pop-Location
}

$stageBundle = Join-Path $stageDir 'conpty'
if (-not (Test-Path (Join-Path $stageBundle 'herdr-conpty.json'))) {
    Stop-WithReason "준비 폴더에 꾸러미가 없다: $stageBundle"
}
Write-Ok "준비 완료  $stageBundle"

# ----------------------------------------------------------------- 4. 서버 내리기

if ($destInUse -and $StopServer) {
    Write-Step "실행 중인 서버 내리기"
    $null = & $destExe server stop 2>&1
    Start-Sleep -Seconds 3
    $stillUsing = @(Get-HerdrProcess | Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -eq $destExe) })
    if ($stillUsing.Count -gt 0) {
        Stop-WithReason "아직 $destExe 를 쓰는 프로세스가 있다: $(($stillUsing | ForEach-Object { $_.ProcessId }) -join ', ')" `
            "이름 있는 세션은 herdr --session <이름> server stop 으로 따로 내린다."
    }
    Write-Ok "내려갔다"
}

# ----------------------------------------------------------------- 5. 설치

Write-Step "설치"

if (-not (Test-Path $Dest)) {
    New-Item -ItemType Directory -Force $Dest | Out-Null
    Write-Info "폴더를 만들었다: $Dest"
} else {
    $destItem = Get-Item $Dest -Force
    if ($destItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Write-Note "설치 위치가 정션이다. 실제로는 $($destItem.Target) 에 쓰인다."
        Write-Info "herdr update 가 이 정션을 갈아끼우면 설치한 내용이 사라진다."
    }
}

Copy-Item -Force $builtExe $destExe
Write-Ok "herdr.exe"

if (Test-Path $destBundle) { Remove-Item -Recurse -Force $destBundle }
Copy-Item -Recurse $stageBundle $destBundle
Write-Ok "conpty\"

# ----------------------------------------------------------------- 6. 배치 검증

Write-Step "배치 검증"

$markerPath = Join-Path $destBundle 'herdr-conpty.json'
$marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json

$expectedFiles = @('conpty/herdr-conpty.json')
foreach ($entry in $marker.files.PSObject.Properties) {
    $relative = $entry.Name
    $expectedFiles += $relative
    $path = Join-Path $Dest ($relative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path)) { Stop-WithReason "꾸러미 파일이 없다: $path" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne ([string]$entry.Value).ToLowerInvariant()) {
        Stop-WithReason "해시가 다르다: $relative" "꾸러미를 다시 준비한다."
    }
    Write-Ok "$relative  $($actual.Substring(0, 8))…"
}

# 여분 파일이 하나라도 있으면 herdr 이 꾸러미를 거부한다.
$actualFiles = @(Get-ChildItem -LiteralPath $destBundle -Recurse -File -Force | ForEach-Object {
    'conpty/' + $_.FullName.Substring($destBundle.Length + 1).Replace('\', '/')
})
$extra = @($actualFiles | Where-Object { $expectedFiles -notcontains $_ })
if ($extra.Count -gt 0) {
    Stop-WithReason "꾸러미에 여분 파일이 있다: $($extra -join ', ')" "이 상태면 herdr 서버가 시작할 때 멈춘다."
}
Write-Ok "파일 목록이 정확히 $($expectedFiles.Count)개다"

$versionOutput = @(& $destExe --version 2>&1)
if ($LASTEXITCODE -ne 0 -or $versionOutput.Count -eq 0) {
    Stop-WithReason "설치한 exe 를 실행할 수 없다: $destExe"
}
$reportedVersion = ([string]$versionOutput[0]).Trim()
Write-Ok "판 문자열  $reportedVersion"

if ($reportedVersion -notlike '*-*') {
    Write-Note "판 문자열에 빌드 표식이 없어 릴리스본과 구별되지 않는다."
    Write-Info "표식을 붙이려면 -SkipBuild 없이 다시 실행한다 (판이 …-$BuildChannel.$BuildId 로 바뀐다)."
}

# ----------------------------------------------------------------- 7. PATH

if ($SkipPath) {
    Write-Step "PATH 는 건드리지 않았다"
    Write-Info "이 exe 를 쓰려면 전체 경로로 실행한다: $destExe"
} else {
    Write-Step "PATH 앞자리"

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @()
    if ($userPath) { $entries = @($userPath -split ';' | Where-Object { $_ }) }
    $others = @($entries | Where-Object { $_.TrimEnd('\') -ne $Dest })
    $newUserPath = (@($Dest) + $others) -join ';'

    if ($newUserPath -cne $userPath) {
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
        Write-Ok "사용자 PATH 앞자리에 두었다 (새로 여는 창부터 적용된다)"
    } else {
        Write-Ok "사용자 PATH 에 이미 앞자리로 있다"
    }

    $processEntries = @($env:Path -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ne $Dest) })
    $env:Path = (@($Dest) + $processEntries) -join ';'

    $resolved = Get-Command herdr -ErrorAction SilentlyContinue
    if ($resolved -and ($resolved.Source -eq $destExe)) {
        Write-Ok "herdr -> $($resolved.Source)"
    } elseif ($resolved) {
        Write-Note "이 창에서는 herdr 이 아직 $($resolved.Source) 로 잡힌다. 새 창을 열어 확인한다."
    }
}

# ----------------------------------------------------------------- 8. 실제 로딩 검증

if ($Verify) {
    Write-Step "실제로 어느 ConPTY 를 불러오는지 확인"

    $session = "verify-local-$([guid]::NewGuid().ToString('N').Substring(0, 6))"
    $server = Start-Process -FilePath $destExe -ArgumentList '--session', $session, 'server' `
        -WindowStyle Hidden -PassThru
    Write-Info "임시 세션 $session (서버 PID $($server.Id))"

    try {
        Start-Sleep -Seconds 4
        $null = & $destExe --session $session workspace create --cwd $env:TEMP --label verify 2>&1
        Start-Sleep -Seconds 3

        $server.Refresh()
        $loaded = @($server.Modules | Where-Object { $_.ModuleName -like 'conpty*' })
        if ($loaded.Count -eq 0) {
            Write-Note "conpty.dll 을 불러오지 않았다 — 시스템 ConPTY 를 쓰는 중이다."
            Write-Info "$destBundle 의 배치를 다시 확인한다."
        } else {
            foreach ($module in $loaded) {
                if ($module.FileName -like "$destBundle*") {
                    Write-Ok "$($module.FileName)  $($module.FileVersion)"
                } else {
                    Write-Note "예상과 다른 자리에서 불렀다: $($module.FileName)"
                }
            }
        }

        $hosts = @(Get-CimInstance Win32_Process -Filter "Name='OpenConsole.exe'" |
            Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -like "$destBundle*") })
        if ($hosts.Count -gt 0) {
            Write-Ok "pane 호스트  $($hosts[0].ExecutablePath)"
        } else {
            Write-Note "이 꾸러미의 OpenConsole.exe 가 보이지 않는다 (conhost.exe 가 쓰였을 수 있다)."
        }
    } catch {
        Write-Note "확인 도중 문제가 생겼다: $($_.Exception.Message)"
        Write-Info "설치 자체는 끝났다. herdr 을 띄워 직접 확인한다."
    } finally {
        $null = & $destExe --session $session server stop 2>&1
        Start-Sleep -Seconds 2
        $server.Refresh()
        if (-not $server.HasExited) {
            Write-Note "임시 서버(PID $($server.Id))가 아직 살아 있다. 직접 확인이 필요하다."
        } else {
            Write-Info "임시 세션을 정리했다"
        }
    }
}

# ----------------------------------------------------------------- 마무리

Write-Step "끝났다"
Write-Info "설치   $destExe"
Write-Info "판     $reportedVersion"
Write-Host ""
Write-Host "  다음 할 일" -ForegroundColor White
Write-Info "1. 새 PowerShell 창을 열고  herdr  로 띄운다 (이전 서버가 떠 있었다면 herdr server stop 먼저)."
Write-Info "2. pane 에서 claude 를 실행하고 Ctrl-G 를 눌러 편집기가 그려지는지 본다."
Write-Info "3. 꾸러미가 담긴 릴리스가 나오기 전에는 herdr update 를 돌리지 않는다."
Write-Host ""
if ($SkipPath) {
    Write-Info "되돌리기: 설치 폴더($Dest)를 지우면 된다. PATH 는 건드리지 않았다."
} else {
    Write-Info "되돌리기: 사용자 PATH 에서 $Dest 를 빼면 릴리스 설치본으로 돌아간다."
}
Write-Host ""
