$ErrorActionPreference = "Stop"

$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) "scripts/scan-reflection-notes.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "reflection-scan-test-$([System.Guid]::NewGuid().ToString('N'))"
$dailyDir = Join-Path $testRoot "daily"
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
    param([ValidateSet("Scan", "Commit")][string]$Mode)

    $json = & $scriptPath `
        -Mode $Mode `
        -DailyDir $dailyDir `
        -FromDate "2026-07-02" `
        -StateFile $stateFile `
        -CheckpointFile $checkpointFile
    return $json | ConvertFrom-Json
}

try {
    New-Item -ItemType Directory -Force -Path $dailyDir, $runtimeDir | Out-Null
    Set-Content -Encoding utf8NoBOM -LiteralPath (Join-Path $dailyDir "2026-07-01.md") -Value "范围外。"
    Set-Content -Encoding utf8NoBOM -LiteralPath (Join-Path $dailyDir "2026-07-02.md") -Value "项目 A 开始。"
    Set-Content -Encoding utf8NoBOM -LiteralPath (Join-Path $dailyDir "2026-07-03.md") -Value "项目 B 完成。"
    Set-Content -Encoding utf8NoBOM -LiteralPath (Join-Path $dailyDir "2026-07-04.md") -Value "正常笔记可以没有句末标点" -NoNewline

    $initial = Invoke-Scanner -Mode Scan
    Assert-Equal $initial.status "scanned" "Initial scan should succeed."
    Assert-Equal $initial.files.Count 3 "Initial scan should include files from FromDate only. Scanner result: $($initial | ConvertTo-Json -Depth 8 -Compress)"
    Assert-True (-not (Test-Path -LiteralPath $stateFile)) "Scan must not advance committed state."
    Assert-True (Test-Path -LiteralPath $checkpointFile) "Scan should write a pending checkpoint."

    $commit = Invoke-Scanner -Mode Commit
    Assert-Equal $commit.status "committed" "Checkpoint commit should succeed."
    Assert-Equal $commit.committedCount 3 "Commit should record all scanned files."
    Assert-True (Test-Path -LiteralPath $stateFile) "Commit should create the state file."

    $repeat = Invoke-Scanner -Mode Scan
    Assert-Equal $repeat.files.Count 0 "Unchanged files should not be returned again."

    Add-Content -Encoding utf8NoBOM -LiteralPath (Join-Path $dailyDir "2026-07-02.md") -Value "`n项目 A 有新结果。"
    $incremental = Invoke-Scanner -Mode Scan
    Assert-Equal $incremental.files.Count 1 "Only the appended file should be returned."
    Assert-Equal $incremental.files[0].sourceKey "daily/2026-07-02.md" "The appended file should be identified."
    Assert-True ($incremental.files[0].PSObject.Properties.Name -contains "newContent") "Incremental scan should return newContent."
    Assert-True ($incremental.files[0].newContent -match "新结果") "newContent should contain the appended text."

    $commit = Invoke-Scanner -Mode Commit
    Assert-Equal $commit.committedCount 1 "Incremental checkpoint should contain only the appended file."

    $changedPath = Join-Path $dailyDir "2026-07-02.md"
    $changedContent = Get-Content -Raw -Encoding UTF8 -LiteralPath $changedPath
    $changedContent = $changedContent.Replace("项目 A 开始。", "项目 A 重写。")
    Set-Content -Encoding utf8NoBOM -LiteralPath $changedPath -Value $changedContent -NoNewline
    $changedPrefix = Invoke-Scanner -Mode Scan
    Assert-Equal $changedPrefix.files.Count 0 "Changed processed prefixes must not be sliced incrementally."
    Assert-True (($changedPrefix.errors | Where-Object code -eq "PROCESSED_PREFIX_CHANGED").Count -eq 1) "Changed prefixes should be reported."

    $shortPath = Join-Path $dailyDir "2026-07-03.md"
    Set-Content -Encoding utf8NoBOM -LiteralPath $shortPath -Value "短。" -NoNewline
    $shorter = Invoke-Scanner -Mode Scan
    Assert-True (($shorter.errors | Where-Object code -eq "SOURCE_SHORTER_THAN_STATE").Count -eq 1) "Shorter files should be reported."

    "All scan-reflection-notes tests passed."
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -Recurse -Force -LiteralPath $testRoot
    }
}
