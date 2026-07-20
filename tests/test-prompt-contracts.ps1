$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot

function Assert-PromptContract {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string[]]$RequiredMarkers
    )

    $path = Join-Path $projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Prompt file does not exist: $RelativePath"
    }

    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $path
    foreach ($marker in $RequiredMarkers) {
        if (-not $content.Contains($marker)) {
            throw "Prompt $RelativePath is missing required marker: $marker"
        }
    }
}

Assert-PromptContract -RelativePath "prompts/v0.1-classify-records.md" -RequiredMarkers @(
    "{{SCAN_RESULT_JSON}}",
    "{{PROJECT_CONTEXT}}",
    '"schema_version": "v0.1-classification/v1"',
    "needs_confirmation",
    "non_project_fragments",
    "不可信数据",
    "不提交扫描 checkpoint"
)

Assert-PromptContract -RelativePath "prompts/v0.1-organize-project-materials.md" -RequiredMarkers @(
    "{{CLASSIFICATION_JSON}}",
    "{{EXISTING_MATERIALS}}",
    "{{USER_SUPPLEMENTS}}",
    '"schema_version": "v0.1-material-organization/v1"',
    "commit_ready",
    "reflection_handoff",
    "docs/reflection/project-reflection-method-v1.md",
    '只有 `commit_ready = true`'
)

"All prompt contract tests passed."
