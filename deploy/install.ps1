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

$agentsSource = Join-Path $FractalAiHome 'AGENTS.md'
$skillsSource = Join-Path $FractalAiHome 'skills'

if (Test-Path -Path $agentsSource -PathType Leaf) {
    Link-FractalItem -Source $agentsSource -Target (Join-Path (Join-Path $HOME '.codex') 'AGENTS.md')
    Link-FractalItem -Source $agentsSource -Target (Join-Path (Join-Path $HOME '.opencode') 'AGENTS.md')
    Link-FractalItem -Source $agentsSource -Target (Join-Path (Join-Path $HOME '.claude') 'CLAUDE.md')
}

if (Test-Path -Path $skillsSource -PathType Container) {
    Link-FractalItem -Source $skillsSource -Target (Join-Path (Join-Path $HOME '.codex') 'skills')
    Link-FractalItem -Source $skillsSource -Target (Join-Path (Join-Path $HOME '.opencode') 'skills')
}
