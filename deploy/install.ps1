#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

$FractalAiHome = if ($env:FRACTAL_AI_HOME) { $env:FRACTAL_AI_HOME } else { Join-Path $HOME '.fractal-ai' }
$PiMcpBridgeCommit = '879cf3d9dd51f5315e98958a7d0ea55e1314da4a'

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

function Ensure-DirectoryTarget {
    param([string]$Target)

    if (Test-Path -Path $Target -PathType Any) {
        $item = Get-Item -Path $Target -Force
        if ($item.LinkType -eq 'SymbolicLink') {
            Write-Host "  cleanup: replacing directory symlink $Target with a real directory"
            Remove-Item -Path $Target
        } elseif (-not $item.PSIsContainer) {
            $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $backup = "${Target}.bak-${timestamp}"
            Write-Warning "  BACKUP: displacing non-directory $Target -> $backup (review before deleting)"
            Move-Item -Path $Target -Destination $backup
        }
    }

    if (-not (Test-Path -Path $Target -PathType Container)) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
    }
}

function Link-DirectoryChildren {
    param(
        [string]$Source,
        [string]$Target
    )

    Ensure-DirectoryTarget -Target $Target
    Get-ChildItem -Path $Source -Force:$false | ForEach-Object {
        Link-FractalItem -Source $_.FullName -Target (Join-Path $Target $_.Name)
    }
}

function Restore-AgentsSystemSkills {
    param([string]$Target)

    if (Test-Path -Path (Join-Path $Target '.system') -PathType Any) { return }

    $parent = Split-Path -Path $Target -Parent
    $name = Split-Path -Path $Target -Leaf
    $latest = Get-ChildItem -Path $parent -Directory -Filter "${name}.bak-*" -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -Path (Join-Path $_.FullName '.system') -PathType Container } |
        Sort-Object -Property Name -Descending |
        Select-Object -First 1

    if ($null -eq $latest) { return }

    Write-Host "  restore: copying Codex-managed system skills from $(Join-Path $latest.FullName '.system')"
    Copy-Item -Path (Join-Path $latest.FullName '.system') -Destination (Join-Path $Target '.system') -Recurse
}

function Remove-LegacySkillLink {
    param(
        [string]$Target,
        [string]$Source
    )

    if (-not (Test-Path -Path $Target -PathType Any)) { return }

    $item = Get-Item -Path $Target -Force
    $sharedTarget = Join-Path (Join-Path $HOME '.agents') 'skills'
    if ($item.LinkType -eq 'SymbolicLink') {
        $current = if ($null -eq $item.Target) { '' } else { ($item.Target -join '') }
        if ($current -eq $Source -or $current -eq $sharedTarget) {
            Write-Host "  cleanup: removing legacy skill symlink $Target"
            Remove-Item -Path $Target
            return
        }
        Write-Warning "leaving non-fractal legacy skill symlink $Target -> $current"
        return
    }

    Write-Warning "leaving real legacy skill directory $Target; move it aside manually if it causes duplicates"
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

function Ensure-PiMcpBridgeCache {
    $cache = Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $HOME '.pi') 'agent') 'git') 'github.com') (Join-Path 'fractaal' 'pi-extension')

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warning 'git not found; cannot install or verify cached Pi MCP bridge package'
        return
    }

    if (-not (Test-Path -Path (Join-Path $cache '.git') -PathType Container)) {
        if (Test-Path -Path $cache -PathType Any) {
            Write-Warning "$cache exists but is not a git checkout; cannot install Pi MCP bridge package cache"
            return
        }
        Write-Warning "Installing cached Pi MCP bridge package at $cache"
        $parent = Split-Path -Path $cache -Parent
        if (-not (Test-Path -Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        & git clone https://github.com/fractaal/pi-extension.git $cache
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'failed to clone Pi MCP bridge package; Pi may install it on first startup'
            return
        }
    }

    $rawCurrent = & git -C $cache rev-parse HEAD 2>$null
    $current = if ($LASTEXITCODE -eq 0 -and $null -ne $rawCurrent) { ($rawCurrent -join "`n").Trim() } else { '' }
    if ($current -eq $PiMcpBridgeCommit) { return }

    Write-Warning "Updating cached Pi MCP bridge package to $PiMcpBridgeCommit"
    & git -C $cache fetch origin async-mcp-startup
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "failed to fetch Pi MCP bridge package; Pi may keep using cached commit $current"
        return
    }

    & git -C $cache checkout --detach $PiMcpBridgeCommit
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "failed to checkout Pi MCP bridge package commit $PiMcpBridgeCommit"
        return
    }

    if (Test-Path -Path (Join-Path $cache 'package.json') -PathType Leaf) {
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            Push-Location $cache
            try {
                & npm install --omit=dev
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning 'failed to install Pi MCP bridge package dependencies'
                }
            }
            finally {
                Pop-Location
            }
        } else {
            Write-Warning 'npm not found; Pi MCP bridge package dependencies may install on first Pi startup'
        }
    }
}

# Shared sources (portable across all AI tools)
$deployedInstructionsSource = Join-Path $FractalAiHome 'DEPLOYED-INSTRUCTIONS.md'
$skillsSource = Join-Path $FractalAiHome 'skills'

# Claude-specific sources
$claudeSettingsSource = Join-Path $FractalAiHome 'claude/settings.json'
$claudeHooksSource = Join-Path $FractalAiHome 'claude/hooks'
$claudeStatuslineSource = Join-Path $FractalAiHome 'claude/statusline-command.sh'

# Pi-specific sources
$piSettingsSource = Join-Path $FractalAiHome 'pi/settings.json'
$piExtensionsSource = Join-Path $FractalAiHome 'pi/extensions'
$piBinSource = Join-Path $FractalAiHome 'pi/bin'

# Shared: deploy DEPLOYED-INSTRUCTIONS.md as AGENTS.md / CLAUDE.md
if (Test-Path -Path $deployedInstructionsSource -PathType Leaf) {
    Link-FractalItem -Source $deployedInstructionsSource -Target (Join-Path (Join-Path $HOME '.codex') 'AGENTS.md')
    Link-FractalItem -Source $deployedInstructionsSource -Target (Join-Path (Join-Path $HOME '.opencode') 'AGENTS.md')
    Link-FractalItem -Source $deployedInstructionsSource -Target (Join-Path (Join-Path $HOME '.claude') 'CLAUDE.md')
    Link-FractalItem -Source $deployedInstructionsSource -Target (Join-Path (Join-Path (Join-Path $HOME '.pi') 'agent') 'AGENTS.md')
    Link-FractalItem -Source $deployedInstructionsSource -Target (Join-Path (Join-Path $HOME '.gemini') 'AGENTS.md')
    Link-FractalItem -Source $deployedInstructionsSource -Target (Join-Path (Join-Path $HOME '.gemini') 'CLAUDE.md')
    Link-FractalItem -Source $deployedInstructionsSource -Target (Join-Path (Join-Path $HOME '.augment') 'AGENTS.md')
}

# Shared: deploy skills/ to supported skill roots
if (Test-Path -Path $skillsSource -PathType Container) {
    # Codex Desktop and Pi both scan ~/.agents/skills. Keep that shared root as a
    # real directory because Codex also places managed .system skills there; install
    # fractal-ai skills as per-skill symlinks instead of owning the whole root.
    $agentsSkillsTarget = Join-Path (Join-Path $HOME '.agents') 'skills'
    Link-DirectoryChildren -Source $skillsSource -Target $agentsSkillsTarget
    Restore-AgentsSystemSkills -Target $agentsSkillsTarget
    Remove-LegacySkillLink -Target (Join-Path (Join-Path $HOME '.codex') 'skills') -Source $skillsSource
    Remove-LegacySkillLink -Target (Join-Path (Join-Path (Join-Path $HOME '.pi') 'agent') 'skills') -Source $skillsSource

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

# Pi-only: settings.json, extensions, helper bin scripts
if (Test-Path -Path $piSettingsSource -PathType Leaf) {
    Link-FractalItem -Source $piSettingsSource -Target (Join-Path (Join-Path (Join-Path $HOME '.pi') 'agent') 'settings.json')
    Ensure-PiMcpBridgeCache
}

if (Test-Path -Path $piExtensionsSource -PathType Container) {
    Link-FractalItem -Source $piExtensionsSource -Target (Join-Path (Join-Path (Join-Path $HOME '.pi') 'agent') 'extensions')
}

if (Test-Path -Path $piBinSource -PathType Container) {
    Link-DirectoryChildren -Source $piBinSource -Target (Join-Path (Join-Path $HOME '.local') 'bin')
}

Warn-StaleSettingsLocal
