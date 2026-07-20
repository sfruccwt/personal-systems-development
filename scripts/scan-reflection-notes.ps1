[CmdletBinding()]
param(
    [ValidateSet("Scan", "Commit")]
    [string]$Mode = "Scan",

    [string]$DailyDir = "C:/codex working space/随手记/daily/",

    [string]$FromDate = "2026-07-02",

    [string]$StateFile = "",

    [string]$CheckpointFile = ""
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $StateFile) {
    $StateFile = Join-Path $projectRoot "reflection/runtime/scan-state.json"
}
if (-not $CheckpointFile) {
    $CheckpointFile = Join-Path $projectRoot "reflection/runtime/scan-checkpoint.json"
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
        [Parameter(Mandatory)][string]$StartDate
    )

    return [ordered]@{
        schemaVersion = 1
        sourceDirectory = $SourceDirectory
        fromDate = $StartDate
        updatedAt = $null
        processed = [ordered]@{}
    }
}

function Assert-StateContract {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$StartDate,
        [Parameter(Mandatory)][string]$Path
    )

    if ($State.schemaVersion -ne 1) {
        throw "Unsupported scan state schema in ${Path}: $($State.schemaVersion)"
    }
    if ($State.sourceDirectory -ne $SourceDirectory) {
        throw "Scan state source directory does not match: $($State.sourceDirectory)"
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
    if ($checkpoint.sourceDirectory -ne $normalizedDailyDir -or $checkpoint.fromDate -ne $FromDate) {
        throw "Checkpoint does not match the requested source directory and FromDate."
    }

    if (Test-Path -LiteralPath $StateFile -PathType Leaf) {
        $state = Read-JsonHashtable -Path $StateFile
        Assert-StateContract -State $state -SourceDirectory $normalizedDailyDir -StartDate $FromDate -Path $StateFile
    }
    else {
        $state = New-EmptyState -SourceDirectory $normalizedDailyDir -StartDate $FromDate
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

if (Test-Path -LiteralPath $StateFile -PathType Leaf) {
    $state = Read-JsonHashtable -Path $StateFile
    Assert-StateContract -State $state -SourceDirectory $normalizedDailyDir -StartDate $FromDate -Path $StateFile
}
else {
    $state = New-EmptyState -SourceDirectory $normalizedDailyDir -StartDate $FromDate
}

$files = @()
$errors = @()
$checkpointProcessed = [ordered]@{}
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

        if ($previouslyProcessed) {
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
            path = (Get-NormalizedFullPath -Path $file.FullName)
            date = $file.BaseName
            previouslyProcessed = $previouslyProcessed
            charCount = $charCount
        }
        $entry[$candidateField] = $candidateContent
        $files += $entry

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
    sourceDirectory = $normalizedDailyDir
    fromDate = $FromDate
    processed = $checkpointProcessed
}
Write-JsonAtomic -Path $CheckpointFile -Value $checkpoint

[ordered]@{
    schemaVersion = 1
    status = "scanned"
    sourceDirectory = $normalizedDailyDir
    fromDate = $FromDate
    stateFile = (Get-NormalizedFullPath -Path $StateFile)
    checkpointFile = (Get-NormalizedFullPath -Path $CheckpointFile)
    files = $files
    errors = $errors
} | ConvertTo-Json -Depth 8
