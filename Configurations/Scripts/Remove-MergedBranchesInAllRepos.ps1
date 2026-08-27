<#
.SYNOPSIS
    Runs cleanup-merged-branches.ps1 against every local Git repository under a root folder.

.DESCRIPTION
    Discovers all Git repositories under -Root (default C:\DEV) and invokes the single-repo
    cleanup script for each one. Nested .git folders (e.g. inside another repo, submodules or
    node_modules) are skipped so each repository is processed only once.

    All relevant switches are passed through to the underlying cleanup script.

.PARAMETER Root
    Root folder to scan for repositories. Defaults to C:\DEV.

.PARAMETER WhatIf
    Only show what would be deleted in each repo, without deleting anything.

.PARAMETER Force
    Force-delete branches Git cannot verify as merged.

.PARAMETER IncludeNeverPushed
    Also delete local branches that never had a remote tracking branch.

.PARAMETER Yes
    Skip the confirmation prompt in each repo and delete immediately.

.EXAMPLE
    .\cleanup-all-repos.ps1 -WhatIf

.EXAMPLE
    .\cleanup-all-repos.ps1 -Yes
#>
param(
    [string]$Root = 'C:\DEV',
    [switch]$WhatIf,
    [switch]$Force,
    [switch]$IncludeNeverPushed,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

$cleanupScript = Join-Path $PSScriptRoot 'Remove-MergedBranches.ps1'
if (-not (Test-Path $cleanupScript)) {
    Write-Error "Cleanup script not found: $cleanupScript"
    exit 1
}

if (-not (Test-Path $Root)) {
    Write-Error "Root folder does not exist: $Root"
    exit 1
}

Write-Host "Scanning for Git repositories under $Root ..." -ForegroundColor Cyan

# Find all .git directories, then keep only top-level repos (skip nested repos/submodules).
$gitDirs = Get-ChildItem -Path $Root -Directory -Recurse -Force -Filter '.git' -ErrorAction SilentlyContinue

$repos = @()
foreach ($gitDir in $gitDirs) {
    $repoPath = $gitDir.Parent.FullName

    # Skip if this repo lives inside an already-found repo (nested/submodule).
    $isNested = $repos | Where-Object { $repoPath.StartsWith($_ + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) }
    if ($isNested) { continue }

    $repos += $repoPath
}

if ($repos.Count -eq 0) {
    Write-Host "No Git repositories found under $Root." -ForegroundColor Yellow
    return
}

Write-Host "Found $($repos.Count) repository(ies)." -ForegroundColor Gray
Write-Host ""

$processed = 0
$errored   = 0

foreach ($repo in $repos) {
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host "Repository: $repo" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor DarkCyan

    try {
        & $cleanupScript -RepoPath $repo -WhatIf:$WhatIf -Force:$Force -IncludeNeverPushed:$IncludeNeverPushed -Yes:$Yes
        $processed++
    }
    catch {
        Write-Host "  ERROR processing repo: $($_.Exception.Message)" -ForegroundColor Red
        $errored++
    }

    Write-Host ""
}

Write-Host ("=" * 70) -ForegroundColor DarkCyan
Write-Host "All done. Repositories processed: $processed, Errored: $errored" -ForegroundColor Cyan
