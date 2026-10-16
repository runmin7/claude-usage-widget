# Api.ps1 - user agent, starting the request, handling the response
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.

function Resolve-UserAgent {
    # 이 헤더가 rate limit 버킷을 결정한다. claude-code/<버전> 형태가 아니면 훨씬 빨리 429가 난다.
    # 버전 숫자가 최신이어야 하는 것은 아니지만, 설치된 값을 알 수 있으면 그쪽을 쓴다.
    $version = $null

    # claude가 PATH에 있으면 가장 정확하다. Get-Command로 먼저 확인해 없을 때 오류를 내지 않는다.
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        try {
            $raw = & claude --version 2>$null
            if ($raw) {
                $found = [regex]::Match([string]$raw, '\d+\.\d+\.\d+')
                if ($found.Success) { $version = $found.Value }
            }
        }
        catch { }
    }

    # 로그온 자동 실행처럼 PATH가 기대와 다를 수 있다. 설정 디렉터리에 남는 갱신 기록에서 주워본다.
    if (-not $version) {
        $marker = Join-Path (Get-ClaudeConfigDir) '.last-update-result.json'
        if (Test-Path $marker) {
            try {
                $info = Get-Content $marker -Raw -Encoding UTF8 | ConvertFrom-Json
                $reported = Get-JsonProperty $info 'version_to'
                if ($reported) { $version = [string]$reported }
            }
            catch { }
        }
    }

    if ($version) { return "claude-code/$version" }
    return $script:FallbackAgent
}

function Start-UsageRequest([switch]$IsRetry) {
    if (-not $IsRetry) { $script:RetriedAuth = $false }

    $cred = Get-Credential
    if (-not $cred) {
        Set-Status -Status 'expired' -Text '자격증명을 읽을 수 없습니다. Claude Code 로그인이 필요합니다.'
        return $false
    }

    # 만료된 토큰으로는 요청하지 않는다. 보내봐도 401이고, 그 401이 쌓이면 429로 차단되어
    # 정작 토큰이 갱신된 뒤에도 한동안 아무것도 받을 수 없게 된다.
    # 대신 자격증명 파일만 주기적으로 다시 읽는다(로컬 I/O라 비용이 없다).
    # 시계 오차와 전송 시간을 감안해 만료 60초 전부터 만료로 본다.
    if ($cred.ExpiresAt -and $cred.ExpiresAt -le (Get-Date).AddSeconds(60)) {
        $script:CredentialStamp = $cred.Stamp
        $script:Backoff = [int]$script:Config.pollActiveSeconds
        Set-Status -Status 'expired' -Text (
            "토큰 만료({0:HH:mm}) — 터미널에서 claude로 작업하면 갱신됩니다" -f $cred.ExpiresAt)

        # 켜져 있으면 CLI를 대신 실행해 갱신을 유도한다. 쿨다운은 함수가 확인한다.
        if ($script:Config.autoRefreshToken) { [void](Invoke-TokenRefresh) }
        return $false
    }

    $token = $cred.Token
    $script:CredentialStamp = $cred.Stamp

    $request = New-Object System.Net.Http.HttpRequestMessage(
        [System.Net.Http.HttpMethod]::Get, $script:UsageUrl)
    $request.Headers.Authorization =
        New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $token)
    $request.Headers.UserAgent.ParseAdd($script:UserAgent)
    $request.Headers.Accept.ParseAdd('application/json')

    try {
        $script:PendingTask   = $script:HttpClient.SendAsync($request)
        $script:PendingSentAt = Get-Date
        $script:LastAttempt   = Get-Date
        return $true
    }
    catch {
        $request.Dispose()
        Set-NetworkBackoff $_.Exception.Message
        return $false
    }
}


function Complete-UsageRequest {
    $task = $script:PendingTask
    $script:PendingTask = $null

    if ($task.IsFaulted -or $task.IsCanceled) {
        $reason = if ($task.Exception) {
            $task.Exception.GetBaseException().Message
        } else { '요청이 취소되었습니다' }
        Set-NetworkBackoff $reason
        return
    }

    $response = $task.Result
    try {
        $code = [int]$response.StatusCode

        if ($code -eq 401 -or $code -eq 403) {
            # 재시도는 "요청을 보내는 사이에 Claude Code가 토큰을 갱신했다"는 경우만 의미가 있다.
            # 그 판단을 자격증명 파일의 수정 시각으로 한다. 파일이 그대로인데 다시 보내면
            # 같은 401이 보장된 중복 요청이고, 그런 401이 쌓이면 서버가 429로 차단한다.
            $fresh = Get-Credential
            $changed = $fresh -and $script:CredentialStamp -and ($fresh.Stamp -ne $script:CredentialStamp)

            if ($changed -and -not $script:RetriedAuth) {
                $script:RetriedAuth = $true
                $script:Backoff = 0
                if (Start-UsageRequest -IsRetry) { return }
                $script:Backoff = [int]$script:Config.pollActiveSeconds
                return
            }

            $detail = if ($fresh -and $fresh.ExpiresAt) {
                "토큰 만료({0:HH:mm}) — Claude Code를 한 번 실행하면 갱신됩니다" -f $fresh.ExpiresAt
            } else {
                '인증 거부 — Claude Code 로그인이 필요합니다'
            }
            Set-Status -Status 'expired' -Text $detail
            $script:Backoff = [int]$script:Config.pollActiveSeconds
            return
        }

        if ($code -eq 429) {
            # 이 엔드포인트는 Retry-After를 주지 않는다. 지수 백오프로 물러난다.
            $script:Backoff = if ($script:Backoff -lt $script:RateLimitFirstBackoff) {
                $script:RateLimitFirstBackoff
            } else {
                [Math]::Min($script:Backoff * 2, $script:RateLimitMaxBackoff)
            }

            # 재시작해도 이 대기를 지키게 파일에 남긴다. 안 되면 사용자는 껐다 켜는데,
            # 그때마다 즉시 요청이 나가 차단이 연장된다 — 고치려는 행동이 악화시키는 구조가 된다.
            Save-RetryAfter $script:Backoff
            Set-Status -Status 'ratelimited' -Text (
                "요청 제한(429) — {0}분 후 재시도. 껐다 켜도 빨라지지 않습니다" -f `
                [int][Math]::Ceiling($script:Backoff / 60))
            return
        }

        if ($code -lt 200 -or $code -ge 300) {
            Set-NetworkBackoff "HTTP $code"
            return
        }

        $body = $response.Content.ReadAsStringAsync().Result
        # 빈 결과는 PowerShell 파이프라인에서 $null로 언롤된다. @()로 감싸 배열 의미를 보장한다.
        $parsed = @(ConvertFrom-UsagePayload ($body | ConvertFrom-Json))
        if ($parsed.Count -eq 0) {
            Set-NetworkBackoff '응답에서 한도 정보를 찾지 못했습니다'
            return
        }

        $script:Limits      = $parsed
        $script:LastSuccess = Get-Date
        $script:Backoff     = 0
        Save-RetryAfter 0   # 대기 해제. 남겨두면 다음 실행이 이유 없이 기다린다.
        Set-Status -Status 'ok' -Text '정상'
        Send-ThresholdNotifications
    }
    catch {
        Set-NetworkBackoff $_.Exception.Message
    }
    finally {
        $response.Dispose()
    }
}

