<#
.SYNOPSIS
    Cleans up local Git branches whose remote branch was merged and deleted (e.g. via PR in Azure DevOps).

.DESCRIPTION
    Detection strategy: a local branch is a deletion candidate when it HAD a remote tracking branch
    (i.e. it was pushed) and that remote branch is now gone. Git reports this as "[gone]".

    Because a deleted remote branch does NOT prove the local commits were integrated (an abandoned PR
    or a manual remote delete also produce "[gone]"), every "[gone]" branch is verified with
    "git cherry <base> <branch>" against the repository's integration base branch (origin/HEAD, else
    origin/main / origin/master / origin/develop). Only branches whose commits are all patch-present
    in the base are deleted; this correctly recognises squash-, rebase- and merge-commit integrations.

    Branches whose commits are NOT in the base are kept and reported for manual review (unless -Force),
    so unmerged work is never silently lost.

    Branches that were NEVER pushed (no upstream tracking) are kept by default. Use -IncludeNeverPushed
    to remove them too.

    Protected branches (main, master, develop, release/*, and the current branch) are never deleted.

.PARAMETER RepoPath
    Path to the git repository. Defaults to the current directory.

.PARAMETER WhatIf
    Only show what would be deleted, without deleting anything.

.PARAMETER Force
    Also delete "[gone]" branches whose commits are NOT in the base branch (unmerged work), and
    force-delete never-pushed branches. Use with care.

.PARAMETER IncludeNeverPushed
    Also delete local branches that never had a remote tracking branch. Riskier - off by default.

.PARAMETER Yes
    Skip the confirmation prompt and delete immediately.

.EXAMPLE
    .\Remove-MergedBranches.ps1 -WhatIf

.EXAMPLE
    .\Remove-MergedBranches.ps1 -RepoPath "C:\DEV\MyRepo"
#>
param(
    [string]$RepoPath = (Get-Location).Path,
    [switch]$WhatIf,
    [switch]$Force,
    [switch]$IncludeNeverPushed,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

# PowerShell 7.3+ turns any non-zero native-command exit into a terminating error
# when ErrorActionPreference is 'Stop'. Git writes progress to stderr and returns
# non-zero for expected conditions (dead remote, unmerged branch), so disable this
# and rely on explicit $LASTEXITCODE checks instead.
$PSNativeCommandUseErrorActionPreference = $false

# Branches that must never be deleted
$protectedExact = @('main', 'master', 'develop', 'development')

function Get-IntegrationBase {
    # The branch that "merged" work should end up on. Prefer the remote's default branch.
    $head = (git symbolic-ref --quiet refs/remotes/origin/HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $head) {
        return ($head -replace '^refs/remotes/', '').Trim()
    }
    foreach ($candidate in @('origin/main', 'origin/master', 'origin/develop', 'main', 'master', 'develop')) {
        git rev-parse --verify --quiet $candidate > $null 2>&1
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }
    return $null
}

function Test-BranchIntegrated {
    param(
        [string]$Branch,
        [string]$Base
    )
    if (-not $Base) { return $false }
    # "git cherry <base> <branch>" lists commits on <branch> relative to <base>:
    #   "- <sha>" the commit is already applied (patch-equivalent) in <base>
    #   "+ <sha>" the commit is NOT in <base>
    # No "+" lines => all of the branch's work is integrated (handles squash / rebase / merge).
    $cherry = git cherry $Base $Branch 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    $notInBase = @($cherry | Where-Object { $_ -match '^\+' })
    return ($notInBase.Count -eq 0)
}

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
    git fetch --prune --quiet 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not fetch from remote (remote may be gone or unreachable). Results may be stale."
    }

    $baseRef = Get-IntegrationBase
    if ($baseRef) {
        Write-Host "  Integration base: $baseRef" -ForegroundColor Gray
    } else {
        Write-Warning "Could not determine an integration base branch. '[gone]' branches will be kept for manual review."
    }

    # Collect branch info in one pass.
    # Format: shortname <TAB> upstream <TAB> track-status
    $raw = git for-each-ref --format="%(refname:short)`t%(upstream:short)`t%(upstream:track)" refs/heads

    $mergedVerified = @()  # [gone] and all commits present in base -> safe to delete
    $unmerged       = @()  # [gone] but has commits not in base -> keep for review
    $neverPushed    = @()  # no upstream ever
    $active         = @()  # remote still exists

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
            if (Test-BranchIntegrated -Branch $name -Base $baseRef) {
                $info.Reason = 'merged'
                $mergedVerified += $info
            } else {
                $info.Reason = 'unmerged'
                $unmerged += $info
            }
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
        } else {
            Write-Host "  -> Kept (use -IncludeNeverPushed to remove these too)" -ForegroundColor DarkGray
        }
    }

    # Report: remote gone but work NOT integrated into base -> unsafe
    Write-Host ""
    if ($baseRef) {
        Write-Host "Remote deleted but NOT merged into $baseRef - review manually:" -ForegroundColor Magenta
    } else {
        Write-Host "Remote deleted but merge status unknown (no base) - review manually:" -ForegroundColor Magenta
    }
    if ($unmerged.Count -eq 0) {
        Write-Host "  (none)" -ForegroundColor DarkGray
    } else {
        foreach ($b in $unmerged) {
            $sha = (git rev-parse --short $b.Name 2>$null).Trim()
            Write-Host "  - $($b.Name)  [$($b.LastDate)]  tip $sha" -ForegroundColor Gray
        }
        if ($Force) {
            Write-Host "  -> Included for deletion (-Force set)" -ForegroundColor Yellow
        } else {
            Write-Host "  -> Kept. Delete with -Force only if the unmerged commits are not needed." -ForegroundColor DarkGray
        }
    }

    # Assemble the deletion set
    $toDelete = @()
    $toDelete += $mergedVerified
    if ($IncludeNeverPushed) { $toDelete += $neverPushed }
    if ($Force)              { $toDelete += $unmerged }

    # Report: candidates for deletion
    Write-Host ""
    Write-Host "Merged (verified integrated into base) - candidates for deletion:" -ForegroundColor Green
    if ($mergedVerified.Count -eq 0) {
        Write-Host "  (none)" -ForegroundColor DarkGray
    } else {
        foreach ($b in $mergedVerified) { Write-Host "  - $($b.Name)  [$($b.LastDate)]" -ForegroundColor White }
    }

    if ($toDelete.Count -eq 0) {
        Write-Host ""
        Write-Host "Nothing to delete." -ForegroundColor Green
        return
    }

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
        # "merged"      -> cherry-verified integrated into base: safe hard delete.
        # "unmerged"    -> only present when -Force: caller accepted the risk.
        # "neverpushed" -> use safe -d unless -Force.
        $deleteFlag = if ($b.Reason -eq 'neverpushed' -and -not $Force) { '-d' } else { '-D' }

        $commitSha = (git rev-parse $b.Name 2>$null).Trim()
        $output = git branch $deleteFlag $b.Name 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  deleted: $($b.Name) [$commitSha]" -ForegroundColor Green
            $deleted++
        } else {
            Write-Host "  FAILED : $($b.Name)" -ForegroundColor Red
            Write-Host "           $output" -ForegroundColor DarkRed
            Write-Host "           Commit retained: $commitSha (recover via 'git branch <name> $commitSha')" -ForegroundColor DarkGray
            $failed++
        }
    }

    Write-Host ""
    Write-Host "Done. Deleted: $deleted, Failed: $failed, Kept for review: $($unmerged.Count)" -ForegroundColor Cyan
}
finally {
    Pop-Location
}