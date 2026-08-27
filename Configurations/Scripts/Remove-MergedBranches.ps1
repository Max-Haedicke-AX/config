<#
.SYNOPSIS
    Cleans up local Git branches whose remote branch was merged and deleted (e.g. via PR in Azure DevOps).

.DESCRIPTION
    Detection strategy: a local branch is considered "merged" when it HAD a remote tracking branch
    (i.e. it was pushed) and that remote branch is now gone. Git reports this as "[gone]".

    This is reliable across ALL merge strategies (merge commit, squash, rebase), because it relies on
    the server having deleted the source branch after the PR was completed - not on the local commit graph.

    Branches that were NEVER pushed (no upstream tracking) are kept by default, because "no remote"
    could simply mean local-only work that was never shared. Use -IncludeNeverPushed to remove them too.

    Protected branches (main, master, develop, release/*, and the current branch) are never deleted.

.PARAMETER RepoPath
    Path to the git repository. Defaults to the current directory.

.PARAMETER WhatIf
    Only show what would be deleted, without deleting anything.

.PARAMETER Force
    Use "git branch -D" (force) instead of "git branch -d". Needed for branches Git cannot verify as merged.

.PARAMETER IncludeNeverPushed
    Also delete local branches that never had a remote tracking branch. Riskier - off by default.

.PARAMETER Yes
    Skip the confirmation prompt and delete immediately.

.EXAMPLE
    .\cleanup-merged-branches.ps1 -WhatIf

.EXAMPLE
    .\cleanup-merged-branches.ps1 -RepoPath "C:\DEV\MyRepo"
#>
param(
    [string]$RepoPath = (Get-Location).Path,
    [switch]$WhatIf,
    [switch]$Force,
    [switch]$IncludeNeverPushed,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

# Branches that must never be deleted
$protectedExact = @('main', 'master', 'develop', 'development')

if (-not (Test-Path $RepoPath)) {
    Write-Error "Repository path does not exist: $RepoPath"
    exit 1
}

Push-Location $RepoPath
try {
    # Verify this is a git repository
    git rev-parse --git-dir 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Not a Git repository: $RepoPath"
        exit 1
    }

    $currentBranch = (git branch --show-current).Trim()

    Write-Host "Cleanup merged branches" -ForegroundColor Cyan
    Write-Host "  Repository: $RepoPath" -ForegroundColor Gray
    Write-Host "  Current branch: $currentBranch" -ForegroundColor Gray
    Write-Host ""

    # Update remote-tracking refs and prune deleted remote branches.
    # This is what turns merged/deleted remote branches into "[gone]".
    Write-Host "Fetching from remote (git fetch --prune)..." -ForegroundColor Gray
    $fetchErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    git fetch --prune 2>$null | Out-Null
    $fetchExitCode = $LASTEXITCODE
    $ErrorActionPreference = $fetchErrorActionPreference
    if ($fetchExitCode -ne 0) {
        Write-Warning "Could not fetch from remote. Results may be stale."
    }

    # Collect branch info in one pass.
    # Format: shortname <TAB> upstream <TAB> track-status
    #   upstream empty        -> never pushed (no tracking branch)
    #   track contains [gone] -> remote branch was deleted (merged/removed on server)
    $raw = git for-each-ref --format="%(refname:short)`t%(upstream:short)`t%(upstream:track)" refs/heads

    $toDelete    = @()  # branches whose remote is gone (merged)
    $neverPushed = @()  # branches without any upstream
    $active      = @()  # branches with a live remote

    foreach ($line in $raw) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $parts    = $line -split "`t"
        $name     = $parts[0].Trim()
        $upstream = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
        $track    = if ($parts.Count -gt 2) { $parts[2].Trim() } else { '' }

        # Skip protected branches
        $isProtected = ($protectedExact -contains $name) -or
                       $name.StartsWith('release/') -or
                       ($name -eq $currentBranch)
        if ($isProtected) {
            Write-Host "  [protected] $name" -ForegroundColor DarkGray
            continue
        }

        $lastDate = (git log -1 --format='%cd' --date=short $name 2>$null)

        $info = [PSCustomObject]@{
            Name     = $name
            LastDate = $lastDate
            Reason   = ''
        }

        if ([string]::IsNullOrEmpty($upstream)) {
            $info.Reason = 'neverpushed'
            $neverPushed += $info
        }
        elseif ($track -match '\[gone\]') {
            $info.Reason = 'merged'
            $toDelete += $info
        }
        else {
            $active += $info
        }
    }

    # Report: active branches (remote still exists)
    Write-Host ""
    Write-Host "Active (remote still exists) - keeping:" -ForegroundColor Cyan
    if ($active.Count -eq 0) {
        Write-Host "  (none)" -ForegroundColor DarkGray
    } else {
        foreach ($b in $active) { Write-Host "  - $($b.Name)  [$($b.LastDate)]" -ForegroundColor Gray }
    }

    # Report: never pushed
    Write-Host ""
    Write-Host "Never pushed (no remote tracking):" -ForegroundColor Yellow
    if ($neverPushed.Count -eq 0) {
        Write-Host "  (none)" -ForegroundColor DarkGray
    } else {
        foreach ($b in $neverPushed) { Write-Host "  - $($b.Name)  [$($b.LastDate)]" -ForegroundColor Gray }
        if ($IncludeNeverPushed) {
            Write-Host "  -> Included for deletion (-IncludeNeverPushed set)" -ForegroundColor Yellow
            $toDelete += $neverPushed
        } else {
            Write-Host "  -> Kept (use -IncludeNeverPushed to remove these too)" -ForegroundColor DarkGray
        }
    }

    # Report: candidates for deletion
    Write-Host ""
    Write-Host "Merged / remote deleted - candidates for deletion:" -ForegroundColor Green
    if ($toDelete.Count -eq 0) {
        Write-Host "  (none)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Nothing to clean up." -ForegroundColor Green
        return
    }
    foreach ($b in $toDelete) { Write-Host "  - $($b.Name)  [$($b.LastDate)]" -ForegroundColor White }

    # WhatIf: stop here
    if ($WhatIf) {
        Write-Host ""
        Write-Host "WhatIf: no branches were deleted. Run without -WhatIf to delete." -ForegroundColor Cyan
        return
    }

    # Confirm once for the whole batch
    if (-not $Yes) {
        Write-Host ""
        $answer = Read-Host "Delete these $($toDelete.Count) branch(es)? (y/N)"
        if ($answer.ToLower() -notin @('y', 'yes')) {
            Write-Host "Cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Delete
    Write-Host ""
    $deleted = 0
    $failed  = 0

    foreach ($b in $toDelete) {
        # 'merged' branches are proven merged (remote deleted after PR) -> safe force delete.
        # 'neverpushed' branches use safe -d unless -Force is given.
        $deleteFlag = if ($b.Reason -eq 'merged' -or $Force) { '-D' } else { '-d' }

        $output = git branch $deleteFlag $b.Name 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  deleted: $($b.Name)" -ForegroundColor Green
            $deleted++
        } else {
            Write-Host "  FAILED : $($b.Name)" -ForegroundColor Red
            Write-Host "           $output" -ForegroundColor DarkRed
            if (-not $Force) {
                Write-Host "           Tip: re-run with -Force to force delete." -ForegroundColor DarkGray
            }
            $failed++
        }
    }

    Write-Host ""
    Write-Host "Done. Deleted: $deleted, Failed: $failed" -ForegroundColor Cyan
}
finally {
    Pop-Location
}
