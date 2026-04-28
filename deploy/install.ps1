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

# Render claude/settings.local.json.template -> ~/.claude/settings.local.json,
# substituting $HOME (literal .Replace, no regex hazards) and deep-merging
# onto any existing file. Template wins on overlapping keys (hooks, statusLine);
# user-managed keys outside the template are preserved. NOTE: jq object-merge
# replaces arrays wholesale — custom entries inside template-managed sections
# are overwritten; add them to the template instead.
# Idempotent: no-op if merged result equals current canonical form.
# Robust: malformed existing JSON is moved to .bak-malformed-* and re-rendered
# fresh rather than aborting the installer.
# Uses jq via temp files (--slurpfile) to sidestep PowerShell's pipe-to-native
# subexpression semantics, which silently break when nested.
function Render-SettingsLocal {
    param(
        [string]$Template,
        [string]$Target
    )

    if (-not (Test-Path -Path $Template -PathType Leaf)) { return }

    if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
        Write-Warning "  jq not found; skipping $Target render"
        return
    }

    $rendered = (Get-Content -Raw -Path $Template).Replace('$HOME', $HOME)

    $tmpRendered = New-TemporaryFile
    try {
        Set-Content -Path $tmpRendered -Value $rendered -NoNewline -Encoding utf8

        $renderedCanon = & jq . $tmpRendered
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Template at $Template is not valid JSON"
            return
        }

        $writeTarget = $false
        $desired = $null

        if (Test-Path -Path $Target -PathType Leaf) {
            & jq empty $Target 2>$null
            if ($LASTEXITCODE -ne 0) {
                $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $backup = "${Target}.bak-malformed-${timestamp}"
                Move-Item -Path $Target -Destination $backup
                Write-Warning "  WARN: $Target was malformed JSON; moved to $backup, re-rendering fresh"
                $desired = $renderedCanon -join "`n"
                $writeTarget = $true
            }
            else {
                $current = (& jq . $Target) -join "`n"
                $merged = (& jq -n --slurpfile e $Target --slurpfile r $tmpRendered '$e[0] * $r[0]') -join "`n"
                if ($current -eq $merged) { return }
                $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $backup = "${Target}.bak-${timestamp}"
                Copy-Item -Path $Target -Destination $backup
                Write-Host "  re-rendered: merged $Template -> $Target (backup: $backup)"
                $desired = $merged
                $writeTarget = $true
            }
        }
        else {
            $parent = Split-Path -Path $Target -Parent
            if (-not (Test-Path -Path $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Write-Host "  rendered: $Template -> $Target"
            $desired = $renderedCanon -join "`n"
            $writeTarget = $true
        }

        if ($writeTarget) {
            Set-Content -Path $Target -Value $desired -NoNewline
            Add-Content -Path $Target -Value ''
        }
    }
    finally {
        Remove-Item -Path $tmpRendered -ErrorAction SilentlyContinue
    }
}

# Shared sources (portable across all AI tools)
$deployedInstructionsSource = Join-Path $FractalAiHome 'DEPLOYED-INSTRUCTIONS.md'
$skillsSource = Join-Path $FractalAiHome 'skills'

# Claude-specific sources
$claudeSettingsSource = Join-Path $FractalAiHome 'claude/settings.json'
$claudeSettingsLocalTemplate = Join-Path $FractalAiHome 'claude/settings.local.json.template'
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

# Claude-only: render settings.local.json from template
Render-SettingsLocal -Template $claudeSettingsLocalTemplate -Target (Join-Path (Join-Path $HOME '.claude') 'settings.local.json')
