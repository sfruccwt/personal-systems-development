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

function Assert-TextAbsent {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string[]]$ForbiddenMarkers
    )

    $path = Join-Path $projectRoot $RelativePath
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $path
    foreach ($marker in $ForbiddenMarkers) {
        if ($content.Contains($marker)) {
            throw "File $RelativePath contains retired marker: $marker"
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
    "## 项目概况",
    "## 来源索引",
    "正文不复制原文",
    "用户纠正优先于旧分类",
    "included_fragment_ids:",
    '"path": "reflection/projects/stable-kebab-case-id.md"',
    "docs/reflection/project-reflection-method-v1.md",
    '只有 `commit_ready = true`'
)

Assert-PromptContract -RelativePath "README.md" -RequiredMarkers @(
    "reflection/projects/<project-id>.md",
    "-FromDate 2026-06-19"
)

Assert-TextAbsent -RelativePath "prompts/v0.1-organize-project-materials.md" -ForbiddenMarkers @(
    "reflection/projects/stable-kebab-case-id/materials.md"
)

Assert-TextAbsent -RelativePath "README.md" -ForbiddenMarkers @(
    "reflection/projects/<project-id>/materials.md"
)

"All prompt contract tests passed."
