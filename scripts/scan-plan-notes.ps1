[CmdletBinding()]
param(
    [ValidateSet("Scan", "Commit")]
    [string]$Mode = "Scan",

    [string]$DailyDir = "C:/codex working space/随手记/daily/",

    [string]$LongTermTodoFile = "C:/codex working space/日常工作计划/工作计划/长期待办.md",

    [string]$FromDate = "2026-07-02",

    [string]$StateFile = "",

    [string]$CheckpointFile = "",

    [switch]$ForceFullScan
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $StateFile) {
    $StateFile = Join-Path $projectRoot "plan/runtime/scan-state.json"
}
if (-not $CheckpointFile) {
    $CheckpointFile = Join-Path $projectRoot "plan/runtime/scan-checkpoint.json"
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).Replace('\', '/')
}

function Get-TextHash {
    param([AllowEmptyString()][string]$Text)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [System.Convert]::ToHexString($hash).ToLowerInvariant()
}

function Read-JsonHashtable {
    param([Parameter(Mandatory)][string]$Path)

    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json -AsHashtable
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $temporaryPath = "$Path.tmp.$PID"
    try {
        $Value | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8NoBOM -LiteralPath $temporaryPath
        Move-Item -Force -LiteralPath $temporaryPath -Destination $Path
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -Force -LiteralPath $temporaryPath
        }
    }
}

function New-EmptyState {
    param(
        [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$TodoFile,
        [Parameter(Mandatory)][string]$StartDate
    )

    return [ordered]@{
        schemaVersion = 1
        dailyDirectory = $SourceDirectory
        longTermTodoFile = $TodoFile
        fromDate = $StartDate
        updatedAt = $null
        processed = [ordered]@{}
    }
}

function Assert-StateContract {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$TodoFile,
        [Parameter(Mandatory)][string]$StartDate,
        [Parameter(Mandatory)][string]$Path
    )

    if ($State.schemaVersion -ne 1) {
        throw "Unsupported scan state schema in ${Path}: $($State.schemaVersion)"
    }
    if ($State.dailyDirectory -ne $SourceDirectory) {
        throw "Scan state daily directory does not match: $($State.dailyDirectory)"
    }
    if ($State.longTermTodoFile -ne $TodoFile) {
        throw "Scan state long-term todo file does not match: $($State.longTermTodoFile)"
    }
    if ($State.fromDate -ne $StartDate) {
        throw "Scan state fromDate does not match: $($State.fromDate)"
    }
    if (-not $State.Contains("processed")) {
        $State.processed = [ordered]@{}
    }
}

if ($FromDate -notmatch '^\d{4}-\d{2}-\d{2}$') {
    throw "FromDate must use YYYY-MM-DD format."
}

$normalizedDailyDir = Get-NormalizedFullPath -Path $DailyDir
$normalizedLongTermTodoFile = Get-NormalizedFullPath -Path $LongTermTodoFile
$StateFile = [System.IO.Path]::GetFullPath($StateFile)
$CheckpointFile = [System.IO.Path]::GetFullPath($CheckpointFile)

if ($Mode -eq "Commit") {
    if (-not (Test-Path -LiteralPath $CheckpointFile -PathType Leaf)) {
        throw "Checkpoint file does not exist: $CheckpointFile"
    }

    $checkpoint = Read-JsonHashtable -Path $CheckpointFile
    if ($checkpoint.schemaVersion -ne 1) {
        throw "Unsupported checkpoint schema: $($checkpoint.schemaVersion)"
    }
    if (
        $checkpoint.dailyDirectory -ne $normalizedDailyDir -or
        $checkpoint.longTermTodoFile -ne $normalizedLongTermTodoFile -or
        $checkpoint.fromDate -ne $FromDate
    ) {
        throw "Checkpoint does not match the requested sources and FromDate."
    }

    if (Test-Path -LiteralPath $StateFile -PathType Leaf) {
        $state = Read-JsonHashtable -Path $StateFile
        Assert-StateContract `
            -State $state `
            -SourceDirectory $normalizedDailyDir `
            -TodoFile $normalizedLongTermTodoFile `
            -StartDate $FromDate `
            -Path $StateFile
    }
    else {
        $state = New-EmptyState `
            -SourceDirectory $normalizedDailyDir `
            -TodoFile $normalizedLongTermTodoFile `
            -StartDate $FromDate
    }

    foreach ($sourceKey in $checkpoint.processed.Keys) {
        $state.processed[$sourceKey] = $checkpoint.processed[$sourceKey]
    }
    $state.updatedAt = (Get-Date).ToUniversalTime().ToString("o")
    Write-JsonAtomic -Path $StateFile -Value $state

    [ordered]@{
        schemaVersion = 1
        status = "committed"
        committedCount = $checkpoint.processed.Count
        stateFile = (Get-NormalizedFullPath -Path $StateFile)
        checkpointFile = (Get-NormalizedFullPath -Path $CheckpointFile)
    } | ConvertTo-Json -Depth 5
    return
}

if (-not (Test-Path -LiteralPath $DailyDir -PathType Container)) {
    throw "Daily notes directory does not exist: $DailyDir"
}
if (-not (Test-Path -LiteralPath $LongTermTodoFile -PathType Leaf)) {
    throw "Long-term todo file does not exist: $LongTermTodoFile"
}

if (Test-Path -LiteralPath $StateFile -PathType Leaf) {
    $state = Read-JsonHashtable -Path $StateFile
    Assert-StateContract `
        -State $state `
        -SourceDirectory $normalizedDailyDir `
        -TodoFile $normalizedLongTermTodoFile `
        -StartDate $FromDate `
        -Path $StateFile
}
else {
    $state = New-EmptyState `
        -SourceDirectory $normalizedDailyDir `
        -TodoFile $normalizedLongTermTodoFile `
        -StartDate $FromDate
}

$sources = @()
$errors = @()
$checkpointProcessed = [ordered]@{}

try {
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $LongTermTodoFile
    if ($null -eq $content) { $content = "" }

    $sourceKey = "long-term-todo"
    $contentHash = Get-TextHash -Text $content
    $previouslyProcessed = $state.processed.Contains($sourceKey)
    $changed = -not $previouslyProcessed
    if ($previouslyProcessed) {
        $changed = $state.processed[$sourceKey].contentSha256 -ne $contentHash
    }

    if ($ForceFullScan -or $changed) {
        $sources += [ordered]@{
            sourceKey = $sourceKey
            sourceType = "longTermTodo"
            path = $normalizedLongTermTodoFile
            previouslyProcessed = $previouslyProcessed
            charCount = $content.Length
            content = $content
        }
        $checkpointProcessed[$sourceKey] = [ordered]@{
            charCount = $content.Length
            contentSha256 = $contentHash
        }
    }
}
catch {
    $errors += [ordered]@{
        sourceKey = "long-term-todo"
        code = "READ_FAILED"
        message = $_.Exception.Message
    }
}

$datePattern = '^\d{4}-\d{2}-\d{2}$'
foreach ($file in Get-ChildItem -LiteralPath $DailyDir -Filter "*.md" -File | Sort-Object BaseName) {
    if ($file.BaseName -notmatch $datePattern -or $file.BaseName -lt $FromDate) { continue }

    $sourceKey = "daily/$($file.Name)"
    try {
        $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName
        if ($null -eq $content) { $content = "" }

        $charCount = $content.Length
        $previouslyProcessed = $state.processed.Contains($sourceKey)
        $candidateContent = $content
        $candidateField = "content"
        $blocked = $false

        if ($previouslyProcessed -and -not $ForceFullScan) {
            $previous = $state.processed[$sourceKey]
            $previousCharCount = [int]$previous.charCount

            if ($charCount -lt $previousCharCount) {
                $errors += [ordered]@{
                    sourceKey = $sourceKey
                    code = "SOURCE_SHORTER_THAN_STATE"
                    message = "Current file is shorter than the processed prefix ($charCount < $previousCharCount)."
                }
                $blocked = $true
            }
            else {
                $currentPrefix = $content.Substring(0, $previousCharCount)
                if ((Get-TextHash -Text $currentPrefix) -ne $previous.prefixSha256) {
                    $errors += [ordered]@{
                        sourceKey = $sourceKey
                        code = "PROCESSED_PREFIX_CHANGED"
                        message = "Previously processed content changed in place; automatic incremental slicing is unsafe."
                    }
                    $blocked = $true
                }
                elseif ($charCount -eq $previousCharCount) {
                    continue
                }
                else {
                    $candidateContent = $content.Substring($previousCharCount)
                    $candidateField = "newContent"
                }
            }
        }

        if ($blocked) { continue }

        $entry = [ordered]@{
            sourceKey = $sourceKey
            sourceType = "daily"
            path = (Get-NormalizedFullPath -Path $file.FullName)
            date = $file.BaseName
            previouslyProcessed = $previouslyProcessed
            charCount = $charCount
        }
        $entry[$candidateField] = $candidateContent
        $sources += $entry

        $checkpointProcessed[$sourceKey] = [ordered]@{
            charCount = $charCount
            prefixSha256 = (Get-TextHash -Text $content)
        }
    }
    catch {
        $errors += [ordered]@{
            sourceKey = $sourceKey
            code = "READ_FAILED"
            message = $_.Exception.Message
        }
    }
}

$checkpoint = [ordered]@{
    schemaVersion = 1
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
    dailyDirectory = $normalizedDailyDir
    longTermTodoFile = $normalizedLongTermTodoFile
    fromDate = $FromDate
    forceFullScan = [bool]$ForceFullScan
    processed = $checkpointProcessed
}
Write-JsonAtomic -Path $CheckpointFile -Value $checkpoint

[ordered]@{
    schemaVersion = 1
    status = "scanned"
    dailyDirectory = $normalizedDailyDir
    longTermTodoFile = $normalizedLongTermTodoFile
    fromDate = $FromDate
    forceFullScan = [bool]$ForceFullScan
    stateFile = (Get-NormalizedFullPath -Path $StateFile)
    checkpointFile = (Get-NormalizedFullPath -Path $CheckpointFile)
    sources = $sources
    errors = $errors
} | ConvertTo-Json -Depth 8
