$ErrorActionPreference = "Stop"

$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) "scripts/scan-plan-notes.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "plan-scan-test-$([System.Guid]::NewGuid().ToString('N'))"
$dailyDir = Join-Path $testRoot "daily"
$longTermTodoFile = Join-Path $testRoot "长期待办.md"
$runtimeDir = Join-Path $testRoot "runtime"
$stateFile = Join-Path $runtimeDir "scan-state.json"
$checkpointFile = Join-Path $runtimeDir "scan-checkpoint.json"

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Expected: $Expected; Actual: $Actual"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Scanner {
    param(
        [ValidateSet("Scan", "Commit")][string]$Mode,
        [switch]$ForceFullScan
    )

    $arguments = @{
        Mode = $Mode
        DailyDir = $dailyDir
        LongTermTodoFile = $longTermTodoFile
        FromDate = "2026-07-02"
        StateFile = $stateFile
        CheckpointFile = $checkpointFile
    }
    if ($ForceFullScan) {
        $arguments.ForceFullScan = $true
    }

    $json = & $scriptPath @arguments
    return $json | ConvertFrom-Json
}

try {
    New-Item -ItemType Directory -Force -Path $dailyDir, $runtimeDir | Out-Null
    Set-Content -Encoding utf8NoBOM -LiteralPath $longTermTodoFile -Value "# 长期待办`n`n- [ ] 项目 L。"
    Set-Content -Encoding utf8NoBOM -LiteralPath (Join-Path $dailyDir "2026-07-01.md") -Value "范围外。"
    Set-Content -Encoding utf8NoBOM -LiteralPath (Join-Path $dailyDir "2026-07-02.md") -Value "项目 A 开始。"
    Set-Content -Encoding utf8NoBOM -LiteralPath (Join-Path $dailyDir "2026-07-03.md") -Value "项目 B 完成。"
    Set-Content -Encoding utf8NoBOM -LiteralPath (Join-Path $dailyDir "2026-07-04.md") -Value "正常笔记可以没有句末标点" -NoNewline

    $initial = Invoke-Scanner -Mode Scan
    Assert-Equal $initial.status "scanned" "Initial scan should succeed."
    Assert-Equal $initial.sources.Count 4 "Initial scan should include the todo file and three in-range daily files."
    Assert-Equal ($initial.sources | Where-Object sourceType -eq "longTermTodo").Count 1 "Initial scan should include the long-term todo source."
    Assert-True (-not (Test-Path -LiteralPath $stateFile)) "Scan must not advance committed state."
    Assert-True (Test-Path -LiteralPath $checkpointFile) "Scan should write a pending checkpoint."

    $commit = Invoke-Scanner -Mode Commit
    Assert-Equal $commit.status "committed" "Checkpoint commit should succeed."
    Assert-Equal $commit.committedCount 4 "Commit should record all scanned sources."
    Assert-True (Test-Path -LiteralPath $stateFile) "Commit should create the state file."

    $repeat = Invoke-Scanner -Mode Scan
    Assert-Equal $repeat.sources.Count 0 "Unchanged sources should not be returned again."

    Add-Content -Encoding utf8NoBOM -LiteralPath (Join-Path $dailyDir "2026-07-02.md") -Value "`n项目 A 有新结果。"
    Set-Content -Encoding utf8NoBOM -LiteralPath $longTermTodoFile -Value "# 长期待办`n`n- [x] 项目 L。`n- [ ] 项目 N。"
    $incremental = Invoke-Scanner -Mode Scan
    Assert-Equal $incremental.sources.Count 2 "The appended daily file and changed todo file should be returned."

    $dailySource = $incremental.sources | Where-Object sourceKey -eq "daily/2026-07-02.md"
    Assert-True ($dailySource.PSObject.Properties.Name -contains "newContent") "Incremental daily scan should return newContent."
    Assert-True ($dailySource.newContent -match "新结果") "newContent should contain the appended text."

    $todoSource = $incremental.sources | Where-Object sourceKey -eq "long-term-todo"
    Assert-True ($todoSource.PSObject.Properties.Name -contains "content") "Changed todo files should be returned in full."
    Assert-True ($todoSource.content -match "项目 N") "Changed todo content should include the new item."

    $commit = Invoke-Scanner -Mode Commit
    Assert-Equal $commit.committedCount 2 "Incremental checkpoint should contain both changed sources."

    $forced = Invoke-Scanner -Mode Scan -ForceFullScan
    Assert-Equal $forced.sources.Count 4 "A forced scan should return every configured source in full."
    Assert-True (($forced.sources | Where-Object sourceType -eq "daily" | Where-Object { $_.PSObject.Properties.Name -contains "content" }).Count -eq 3) "Forced daily sources should contain full content."

    $changedPath = Join-Path $dailyDir "2026-07-02.md"
    $changedContent = Get-Content -Raw -Encoding UTF8 -LiteralPath $changedPath
    $changedContent = $changedContent.Replace("项目 A 开始。", "项目 A 重写。")
    Set-Content -Encoding utf8NoBOM -LiteralPath $changedPath -Value $changedContent -NoNewline
    $changedPrefix = Invoke-Scanner -Mode Scan
    Assert-True (($changedPrefix.errors | Where-Object code -eq "PROCESSED_PREFIX_CHANGED").Count -eq 1) "Changed daily prefixes should be reported."

    $shortPath = Join-Path $dailyDir "2026-07-03.md"
    Set-Content -Encoding utf8NoBOM -LiteralPath $shortPath -Value "短。" -NoNewline
    $shorter = Invoke-Scanner -Mode Scan
    Assert-True (($shorter.errors | Where-Object code -eq "SOURCE_SHORTER_THAN_STATE").Count -eq 1) "Shorter daily files should be reported."

    "All scan-plan-notes tests passed."
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -Recurse -Force -LiteralPath $testRoot
    }
}
