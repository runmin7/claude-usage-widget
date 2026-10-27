# Api.ps1 - user agent, starting the request, handling the response (Claude / Gemini / AGY)
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

function Sync-CombinedState {
    $combined = @()
    if (-not $script:Config.hideClaude -and $script:ClaudeLimits) { $combined += @($script:ClaudeLimits) }
    if (-not $script:Config.hideGemini -and $script:GeminiLimits) { $combined += @($script:GeminiLimits) }
    if (-not $script:Config.hideAgy    -and $script:AgyLimits)    { $combined += @($script:AgyLimits) }
    $script:Limits = $combined

    $anyOk = ((-not $script:Config.hideClaude -and $script:ClaudeStatus -eq 'ok') -or
              (-not $script:Config.hideGemini -and $script:GeminiStatus -eq 'ok') -or
              (-not $script:Config.hideAgy    -and $script:AgyStatus    -eq 'ok'))
    if ($anyOk) {
        $script:LastSuccess = Get-Date
        # 표시 중인 서비스 가운데 주의가 필요한 상태가 있으면 전체 상태에도 반영한다.
        if (-not $script:Config.hideClaude -and $script:ClaudeStatus -ne 'ok' -and $script:ClaudeStatus -ne 'init') {
            Set-Status -Status $script:ClaudeStatus -Text $script:ClaudeStatusText
        }
        elseif (-not $script:Config.hideGemini -and $script:GeminiStatus -ne 'ok' -and $script:GeminiStatus -ne 'init') {
            Set-Status -Status $script:GeminiStatus -Text $script:GeminiStatusText
        }
        elseif (-not $script:Config.hideAgy -and $script:AgyStatus -ne 'ok' -and $script:AgyStatus -ne 'init') {
            Set-Status -Status $script:AgyStatus -Text $script:AgyStatusText
        }
        else {
            Set-Status -Status 'ok' -Text '정상'
        }
    }
    else {
        if (-not $script:Config.hideClaude) {
            Set-Status -Status $script:ClaudeStatus -Text $script:ClaudeStatusText
        }
        elseif (-not $script:Config.hideGemini) {
            Set-Status -Status $script:GeminiStatus -Text $script:GeminiStatusText
        }
        else {
            Set-Status -Status $script:AgyStatus -Text $script:AgyStatusText
        }
    }
}

function Update-GeminiUsage {
    $cred = Get-GeminiCredential
    if (-not $cred -or -not $cred.Token) {
        $script:GeminiStatus     = 'expired'
        $script:GeminiStatusText = 'Gemini CLI 로그인이 필요합니다'
        return
    }

    if (-not $script:GeminiProjectId -and $env:GOOGLE_CLOUD_PROJECT) {
        $script:GeminiProjectId = [string]$env:GOOGLE_CLOUD_PROJECT
    }

    if (-not $script:GeminiProjectId) {
        $loadReq = New-Object System.Net.Http.HttpRequestMessage(
            [System.Net.Http.HttpMethod]::Post, $script:GeminiLoadUrl)
        $loadReq.Headers.Authorization =
            New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $cred.Token)
        $loadBody = '{"metadata":{"ideType":"IDE_UNSPECIFIED","platform":"PLATFORM_UNSPECIFIED","pluginType":"GEMINI"}}'
        $loadReq.Content = New-Object System.Net.Http.StringContent(
            $loadBody, [System.Text.Encoding]::UTF8, 'application/json')
        try {
            $loadResp = $script:HttpClient.SendAsync($loadReq).Result
            try {
                if ($loadResp.IsSuccessStatusCode) {
                    $loadJson = $loadResp.Content.ReadAsStringAsync().Result | ConvertFrom-Json
                    $proj = Get-JsonProperty $loadJson 'cloudaicompanionProject'
                    if ($proj) { $script:GeminiProjectId = [string]$proj }
                }
            }
            finally { $loadResp.Dispose() }
        }
        catch { }
        finally { $loadReq.Dispose() }
    }

    $quotaReq = New-Object System.Net.Http.HttpRequestMessage(
        [System.Net.Http.HttpMethod]::Post, $script:GeminiQuotaUrl)
    $quotaReq.Headers.Authorization =
        New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $cred.Token)
    $quotaBody = if ($script:GeminiProjectId) {
        ConvertTo-Json @{ project = $script:GeminiProjectId } -Compress
    } else { '{}' }
    $quotaReq.Content = New-Object System.Net.Http.StringContent(
        $quotaBody, [System.Text.Encoding]::UTF8, 'application/json')

    try {
        $resp = $script:HttpClient.SendAsync($quotaReq).Result
        try {
            $code = [int]$resp.StatusCode
            if ($code -eq 401 -or $code -eq 403) {
                $script:GeminiAccessToken = $null
                $script:GeminiStatus      = 'expired'
                $script:GeminiStatusText  = 'Gemini 인증 만료 — 재로그인 필요'
                return
            }
            if (-not $resp.IsSuccessStatusCode) {
                $script:GeminiStatus     = 'error'
                $script:GeminiStatusText = "Gemini HTTP $code"
                return
            }

            $body = $resp.Content.ReadAsStringAsync().Result | ConvertFrom-Json
            $parsed = @(ConvertFrom-GeminiQuotaPayload $body)
            if ($parsed.Count -eq 0) {
                $script:GeminiStatus     = 'error'
                $script:GeminiStatusText = 'Gemini 한도 정보 없음'
                return
            }

            $script:GeminiLimits     = $parsed
            $script:GeminiStatus     = 'ok'
            $script:GeminiStatusText = '정상'
        }
        finally { $resp.Dispose() }
    }
    catch {
        $script:GeminiStatus     = 'error'
        $script:GeminiStatusText = "Gemini 조회 실패: $($_.Exception.Message)"
    }
    finally { $quotaReq.Dispose() }
}

function Get-AgyWeeklyCycle {
    $now       = Get-Date
    $resetDay  = [int]$script:Config.agyResetDay
    $resetHour = [Math]::Max(0, [Math]::Min(23, [int]$script:Config.agyResetHour))

    # agyResetDay가 0(일)~6(토)이면 해당 요일/시각을 주간 초기화 기준으로 삼는다(기본: 월요일 00:00).
    # -1 등 음수로 설정하면 최근 7일 롤링 윈도우 모드로 동작한다.
    if ($resetDay -ge 0 -and $resetDay -le 6) {
        $daysBack   = ([int]$now.DayOfWeek - $resetDay + 7) % 7
        $cycleStart = $now.Date.AddDays(-$daysBack).AddHours($resetHour)
        if ($cycleStart -gt $now) { $cycleStart = $cycleStart.AddDays(-7) }
        $resetsAt   = $cycleStart.AddDays(7)
        return @{
            IsRolling = $false
            CutoffUtc = $cycleStart.ToUniversalTime()
            ResetsAt  = $resetsAt
        }
    }

    return @{
        IsRolling = $true
        CutoffUtc = $now.ToUniversalTime().AddDays(-7)
        ResetsAt  = $now.AddDays(7)
    }
}

function Update-AgyUsage {
    try {
        $brainDir    = Join-Path $env:USERPROFILE '.gemini\antigravity\brain'
        $totalTokens = [int64]0
        $cycle       = Get-AgyWeeklyCycle
        $cutoffUtc   = $cycle.CutoffUtc
        $earliestUtc = $null

        if (Test-Path $brainDir) {
            $files = @(Get-ChildItem -Path $brainDir -Recurse -Filter 'transcript.jsonl' -ErrorAction SilentlyContinue)

            foreach ($file in $files) {
                $fullPath = $file.FullName
                $stamp    = $file.LastWriteTimeUtc
                $len      = $file.Length

                $cached = if ($script:AgyFileCache.ContainsKey($fullPath)) { $script:AgyFileCache[$fullPath] } else { $null }
                if (-not $cached -or $cached.Stamp -ne $stamp -or $cached.Length -ne $len) {
                    $entries = @()
                    try {
                        foreach ($line in [System.IO.File]::ReadLines($fullPath)) {
                            if ($line -match '"input_tokens":(\d+)') {
                                $inTok    = [int64]$Matches[1]
                                $cacheTok = if ($line -match '"cache_read_tokens":(\d+)') { [int64]$Matches[1] } else { [int64]0 }
                                $outTok   = if ($line -match '"output_tokens":(\d+)') { [int64]$Matches[1] } else { [int64]0 }
                                if ($line -match '"created_at":"([^"]+)"') {
                                    $dt = [DateTimeOffset]::Parse(
                                        $Matches[1],
                                        [System.Globalization.CultureInfo]::InvariantCulture).UtcDateTime
                                    $entries += [pscustomobject]@{
                                        Utc    = $dt
                                        Tokens = ($inTok + $cacheTok + $outTok)
                                    }
                                }
                            }
                        }
                    }
                    catch { }
                    $cached = @{ Stamp = $stamp; Length = $len; Entries = $entries }
                    $script:AgyFileCache[$fullPath] = $cached
                }

                foreach ($item in $cached.Entries) {
                    if ($item.Utc -ge $cutoffUtc) {
                        $totalTokens += [int64]$item.Tokens
                        if (-not $earliestUtc -or $item.Utc -lt $earliestUtc) {
                            $earliestUtc = $item.Utc
                        }
                    }
                }
            }
        }

        $resetsAt = if ($cycle.IsRolling -and $earliestUtc) {
            $earliestUtc.ToLocalTime().AddDays(7)
        } else {
            $cycle.ResetsAt
        }

        $limitMillion = [int]$script:Config.agyWeeklyLimitMillion
        if ($limitMillion -le 0) { $limitMillion = 170 }
        $limitTokens  = [int64]$limitMillion * [int64]1000000
        $percent      = [Math]::Max(0.0, ($totalTokens / [double]$limitTokens) * 100.0)
        $usedText     = Format-TokenMillion $totalTokens

        $row = [pscustomobject]@{
            Provider    = 'agy'
            Key         = 'agy_weekly'
            Label       = "주간 ($usedText / $($limitMillion)M)"
            NotifyLabel = 'AGY 주간'
            Percent     = $percent
            Window      = $resetsAt.ToString('yyyy-MM-dd-HH')
            ResetsAt    = $resetsAt
            Severity    = Get-EffectiveSeverity $percent $null
            DetailText  = $null
        }

        $script:AgyLimits     = @($row)
        $script:AgyStatus     = 'ok'
        $script:AgyStatusText = '정상'
    }
    catch {
        $script:AgyStatus     = 'error'
        $script:AgyStatusText = "AGY 집계 실패: $($_.Exception.Message)"
    }
}

function Start-UsageRequest([switch]$IsRetry) {
    if (-not $IsRetry) {
        $script:RetriedAuth = $false
        $script:LastAttempt = Get-Date
        if (-not $script:Config.hideAgy)    { Update-AgyUsage }
        if (-not $script:Config.hideGemini) { Update-GeminiUsage }
    }

    if ($script:Config.hideClaude) {
        Sync-CombinedState
        return $false
    }

    $cred = Get-Credential
    if (-not $cred) {
        $script:ClaudeStatus     = 'expired'
        $script:ClaudeStatusText = 'Claude 자격증명 없음 — 로그인 필요'
        Sync-CombinedState
        return $false
    }

    # 만료된 토큰으로는 요청하지 않는다. 보내봐도 401이고, 그 401이 쌓이면 429로 차단되어
    # 정작 토큰이 갱신된 뒤에도 한동안 아무것도 받을 수 없게 된다.
    # 대신 자격증명 파일만 주기적으로 다시 읽는다(로컬 I/O라 비용이 없다).
    # 시계 오차와 전송 시간을 감안해 만료 60초 전부터 만료로 본다.
    if ($cred.ExpiresAt -and $cred.ExpiresAt -le (Get-Date).AddSeconds(60)) {
        $script:CredentialStamp = $cred.Stamp
        $script:Backoff = [int]$script:Config.pollActiveSeconds
        $script:ClaudeStatus     = 'expired'
        $script:ClaudeStatusText = (
            "토큰 만료({0:HH:mm}) — claude 실행 시 갱신" -f $cred.ExpiresAt)

        # 켜져 있으면 CLI를 대신 실행해 갱신을 유도한다. 쿨다운은 함수가 확인한다.
        if ($script:Config.autoRefreshToken) { [void](Invoke-TokenRefresh) }
        Sync-CombinedState
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
        Sync-CombinedState
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
        Sync-CombinedState
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
                "토큰 만료({0:HH:mm}) — claude 실행 시 갱신" -f $fresh.ExpiresAt
            } else {
                '인증 거부 — Claude Code 로그인 필요'
            }
            $script:ClaudeStatus     = 'expired'
            $script:ClaudeStatusText = $detail
            $script:Backoff = [int]$script:Config.pollActiveSeconds
            Sync-CombinedState
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
            $script:ClaudeStatus     = 'ratelimited'
            $script:ClaudeStatusText = (
                "요청 제한(429) — {0}분 후 재시도" -f [int][Math]::Ceiling($script:Backoff / 60))
            Sync-CombinedState
            return
        }

        if ($code -lt 200 -or $code -ge 300) {
            Set-NetworkBackoff "HTTP $code"
            Sync-CombinedState
            return
        }

        $body = $response.Content.ReadAsStringAsync().Result
        # 빈 결과는 PowerShell 파이프라인에서 $null로 언롤된다. @()로 감싸 배열 의미를 보장한다.
        $parsed = @(ConvertFrom-UsagePayload ($body | ConvertFrom-Json))
        if ($parsed.Count -eq 0) {
            Set-NetworkBackoff '응답에서 한도 정보를 찾지 못했습니다'
            Sync-CombinedState
            return
        }

        $script:ClaudeLimits     = $parsed
        $script:ClaudeStatus     = 'ok'
        $script:ClaudeStatusText = '정상'
        $script:Backoff          = 0
        Save-RetryAfter 0   # 대기 해제. 남겨두면 다음 실행이 이유 없이 기다린다.
        Sync-CombinedState
    }
    catch {
        Set-NetworkBackoff $_.Exception.Message
        Sync-CombinedState
    }
    finally {
        $response.Dispose()
    }
}
