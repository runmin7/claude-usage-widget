# Credential.ps1 - reading the token, expiry check, CLI refresh nudge
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.


# Claude Code는 설정과 자격증명을 한 디렉터리에 모아둔다. 이 위치는 사용자 프로필 기준이며
# Claude를 어디에 설치했는지와 무관하다. 따라서 PC마다 경로를 맞춰줄 필요가 없다.
# 예외는 CLAUDE_CONFIG_DIR인데, 한 PC에서 계정을 여러 개 쓰려고 설정을 옮긴 경우 이 변수가 잡혀 있다.
function Get-ClaudeConfigDir {
    if ($env:CLAUDE_CONFIG_DIR -and (Test-Path $env:CLAUDE_CONFIG_DIR)) {
        return $env:CLAUDE_CONFIG_DIR
    }
    return (Join-Path $env:USERPROFILE '.claude')
}

# 토큰과 함께 만료 시각·파일 수정 시각을 돌려준다.
#
# 만료 시각을 보는 이유: 만료된 토큰으로 요청하면 반드시 401이다. 그걸 모르고 계속 보내면
# 401이 쌓여 서버가 429로 차단하고, 그때부터는 토큰을 갱신해도 한동안 아무것도 못 받는다.
# 부를 필요가 없는 요청을 아예 보내지 않는 것이 유일한 방어다.
#
# 파일 수정 시각을 보는 이유: 401 재시도는 "Claude Code가 방금 갱신했을지도 모른다"는 가정인데,
# 파일이 그대로면 재시도는 같은 결과가 보장된 중복 요청일 뿐이다.
function Get-Credential {
    $path = Join-Path (Get-ClaudeConfigDir) '.credentials.json'
    if (-not (Test-Path $path)) { return $null }

    try {
        $cred = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $stamp = (Get-Item $path).LastWriteTimeUtc
    }
    catch { return $null }

    $token = $null
    foreach ($getter in @(
        { $cred.claudeAiOauth.accessToken },
        { $cred.accessToken },
        { $cred.access_token }
    )) {
        try {
            $value = & $getter
            if ($value) { $token = [string]$value; break }
        }
        catch { }
    }
    if (-not $token) { return $null }

    # expiresAt은 밀리초 단위 Unix 시각이다. 없으면 만료를 판단하지 않는다(null).
    $expires = $null
    foreach ($getter in @(
        { $cred.claudeAiOauth.expiresAt },
        { $cred.expiresAt },
        { $cred.expires_at }
    )) {
        try {
            $value = & $getter
            if ($value) {
                $expires = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$value).LocalDateTime
                break
            }
        }
        catch { }
    }

    return @{ Token = $token; ExpiresAt = $expires; Stamp = $stamp }
}

# 토큰이 만료됐을 때 claude CLI로 아주 짧은 작업을 시켜 갱신을 유도한다.
#
# 왜 이 방법뿐인가: 이 파일을 갱신하는 것은 CLI가 인증 API 호출을 할 때다. `--version`,
# `auth status`로는 갱신되지 않고(인증 호출이 없다), 데스크톱 앱은 자격증명 저장소가 달라
# 아무리 써도 이 파일을 건드리지 않는다.
#
# 왜 --bare를 쓰지 않는가: --bare는 자격증명 읽기를 건너뛰어 "Not logged in"으로 실패한다.
# 왜 컨텍스트를 줄이지 않는가: 시스템 프롬프트를 바꾸면 프롬프트 캐시가 깨져 오히려 비싸진다
# (실측: 일반 형태 4만 토큰 $0.022, 최소화 시도 2.5만 토큰 $0.050).
#
# 비용: 회당 약 10초, 약 4만 토큰. 그래서 기본은 꺼져 있고 사용자가 켜거나 직접 누른다.
function Invoke-TokenRefresh([switch]$Manual) {
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Set-Status -Status 'expired' -Text 'claude 명령을 찾을 수 없습니다. Claude Code 설치가 필요합니다'
        return $false
    }

    $cooldown = [int]$script:Config.refreshCooldownMinutes
    if (-not $Manual -and $script:LastRefreshAttempt -and
        ((Get-Date) - $script:LastRefreshAttempt).TotalMinutes -lt $cooldown) {
        return $false
    }

    $script:LastRefreshAttempt = Get-Date

    try {
        # 완전히 분리해 띄운다. 기다리면 10초 동안 위젯과 트레이가 멈춘다.
        # stdin을 NUL로 막지 않으면 CLI가 3초간 입력을 기다리며 경고를 낸다.
        # 출력은 버린다 — 응답 내용이 필요한 것이 아니라 인증이 일어나는 것이 목적이다.
        # 프롬프트는 "짧은 말"이 아니라 "짧게 답하라는 지시"여야 한다. 실측으로 확인했다 —
        # 'ok' 한 단어를 보내면 Claude가 무엇을 도와줄지 장황하게 되물어 출력이 438토큰이 된다.
        # 지시형으로 바꾸면 응답이 "ok"로 끝나 76토큰이 되고 3초 이상 빨라진다.
        # 시스템 프롬프트는 건드리지 않으므로 캐시 적중(31,344 읽기)은 그대로 유지된다.
        Start-Process -FilePath 'cmd.exe' -WindowStyle Hidden -ArgumentList @(
            '/c',
            'claude -p "Reply with only: ok" --model haiku < NUL > NUL 2>&1'
        ) -WorkingDirectory $env:USERPROFILE | Out-Null

        Set-Status -Status 'expired' -Text '토큰 갱신 시도 중 — 10초쯤 걸립니다'

        # 갱신이 끝나면 자격증명 파일이 바뀐다. 곧 다시 확인하도록 대기를 짧게 잡는다.
        $script:Backoff = 25
        return $true
    }
    catch {
        Set-Status -Status 'expired' -Text "갱신 시도 실패: $($_.Exception.Message)"
        return $false
    }
}


