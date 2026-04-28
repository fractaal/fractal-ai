#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

$FractalAiHome = if ($env:FRACTAL_AI_HOME) { $env:FRACTAL_AI_HOME } else { Join-Path $HOME '.fractal-ai' }

function Link-FractalItem {
    param(
        [string]$Source,
        [string]$Target
    )

    if (Test-Path -Path $Target -PathType Any) {
        $item = Get-Item -Path $Target -Force
        if ($item.LinkType -eq 'SymbolicLink') {
            $current = $item.Target
            if ($current -eq $Source) {
                return
            }
        }
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = "${Target}.bak-${timestamp}"
        if ($item.LinkType -eq 'SymbolicLink') {
            Write-Host "  backup: replacing stale symlink $Target -> $backup"
        } else {
            Write-Warning "  BACKUP: displacing real file/dir $Target -> $backup (review before deleting)"
        }
        Move-Item -Path $Target -Destination $backup
    }

    $parent = Split-Path -Path $Target -Parent
    if (-not (Test-Path -Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Target -Value $Source -Force | Out-Null
    }
    catch {
        Write-Error (@(
            "Failed to create symlink: $Target -> $Source"
            'On Windows, symlinks require either:'
            '  1. Developer Mode enabled (Settings > Update & Security > For developers)'
            '  2. Running this script as Administrator'
        ) -join "`n")
    }
}

# Warn if ~/.claude/settings.local.json still contains keys that are now owned
# by the canonical (user-global) settings.json. The previous layout rendered
# `hooks` and `statusLine` into settings.local.json, but that file is cwd-
# ancestry-scoped (only loads when cwd is under $HOME), so those entries
# silently failed for sessions outside $HOME. Both keys now live in the
# canonical settings.json. Stale copies cause duplicate hook firing because
# Claude Code merges hook arrays across precedence scopes and the string-
# difference between `~/...` and `$HOME-substituted/...` defeats dedup.
function Warn-StaleSettingsLocal {
    $target = Join-Path (Join-Path $HOME '.claude') 'settings.local.json'
    if (-not (Test-Path -Path $target -PathType Leaf)) { return }
    if (-not (Get-Command jq -ErrorAction SilentlyContinue)) { return }

    & jq empty $target 2>$null
    if ($LASTEXITCODE -ne 0) { return }

    $raw = & jq -r '[keys[] | select(. == "hooks" or . == "statusLine")] | join(", ")' $target
    $stale = if ($null -eq $raw) { '' } else { ($raw -join "`n").Trim() }
    if ($stale) {
        Write-Warning ""
        Write-Warning "  ────────────────────────────────────────────────────────────"
        Write-Warning "  $target still contains stale top-level keys: $stale"
        Write-Warning "  These keys are now owned by the canonical settings.json (user-global)."
        Write-Warning "  Leaving them here causes duplicate hook firing on every Stop/Edit."
        Write-Warning ""
        Write-Warning "  Run this to clean them up (preserves all your other local keys):"
        Write-Warning "    `$tmp = New-TemporaryFile; jq 'del(.hooks, .statusLine)' '$target' | Set-Content `$tmp; Move-Item -Force `$tmp '$target'"
        Write-Warning "  ────────────────────────────────────────────────────────────"
        Write-Warning ""
    }
}

# Shared sources (portable across all AI tools)
$deployedInstructionsSource = Join-Path $FractalAiHome 'DEPLOYED-INSTRUCTIONS.md'
$skillsSource = Join-Path $FractalAiHome 'skills'

# Claude-specific sources
$claudeSettingsSource = Join-Path $FractalAiHome 'claude/settings.json'
$claudeHooksSource = Join-Path $FractalAiHome 'claude/hooks'
$claudeStatuslineSource = Join-Path $FractalAiHome 'claude/statusline-command.sh'

# Shared: deploy DEPLOYED-INSTRUCTIONS.md as AGENTS.md / CLAUDE.md
if (Test-Path -Path $deployedInstructionsSource -PathType Leaf) {
    Link-FractalItem -Source $deployedInstructionsSource -Target (Join-Path (Join-Path $HOME '.codex') 'AGENTS.md')
    Link-FractalItem -Source $deployedInstructionsSource -Target (Join-Path (Join-Path $HOME '.opencode') 'AGENTS.md')
    Link-FractalItem -Source $deployedInstructionsSource -Target (Join-Path (Join-Path $HOME '.claude') 'CLAUDE.md')
    Link-FractalItem -Source $deployedInstructionsSource -Target (Join-Path (Join-Path $HOME '.gemini') 'AGENTS.md')
    Link-FractalItem -Source $deployedInstructionsSource -Target (Join-Path (Join-Path $HOME '.gemini') 'CLAUDE.md')
    Link-FractalItem -Source $deployedInstructionsSource -Target (Join-Path (Join-Path $HOME '.augment') 'AGENTS.md')
}

# Shared: deploy skills/ to every supported tool
if (Test-Path -Path $skillsSource -PathType Container) {
    Link-FractalItem -Source $skillsSource -Target (Join-Path (Join-Path $HOME '.codex') 'skills')
    Link-FractalItem -Source $skillsSource -Target (Join-Path (Join-Path $HOME '.opencode') 'skills')
    Link-FractalItem -Source $skillsSource -Target (Join-Path (Join-Path $HOME '.claude') 'skills')
    Link-FractalItem -Source $skillsSource -Target (Join-Path (Join-Path $HOME '.gemini') 'skills')
    Link-FractalItem -Source $skillsSource -Target (Join-Path (Join-Path $HOME '.augment') 'skills')
}

# Claude-only: settings.json, hooks/, statusline-command.sh
if (Test-Path -Path $claudeSettingsSource -PathType Leaf) {
    Link-FractalItem -Source $claudeSettingsSource -Target (Join-Path (Join-Path $HOME '.claude') 'settings.json')
}

if (Test-Path -Path $claudeHooksSource -PathType Container) {
    Link-FractalItem -Source $claudeHooksSource -Target (Join-Path (Join-Path $HOME '.claude') 'hooks')
}

if (Test-Path -Path $claudeStatuslineSource -PathType Leaf) {
    Link-FractalItem -Source $claudeStatuslineSource -Target (Join-Path (Join-Path $HOME '.claude') 'statusline-command.sh')
}

Warn-StaleSettingsLocal
