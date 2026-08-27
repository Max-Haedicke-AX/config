#Requires -Version 5.1
<#
.SYNOPSIS
    Fetches all Git repositories directly below a root directory.
.DESCRIPTION
    Runs git fetch --all for every direct child directory containing a .git folder.
    The script returns a non-zero exit code if any repository fetch fails.
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = 'C:\DEV'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RepositoryRoot -PathType Container)) {
    throw "Repository root does not exist: $RepositoryRoot"
}

$failedRepositories = 0
$repositories = @(Get-ChildItem -LiteralPath $RepositoryRoot -Directory)

foreach ($repository in $repositories) {
    $gitDirectory = Join-Path -Path $repository.FullName -ChildPath '.git'
    if (-not (Test-Path -LiteralPath $gitDirectory -PathType Container)) {
        continue
    }

    Write-Host "Fetching $($repository.FullName)..."
    & git -C $repository.FullName fetch --all
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "git fetch failed for $($repository.FullName) with exit code $LASTEXITCODE."
        $failedRepositories++
    }
}

if ($failedRepositories -gt 0) {
    exit 1
}
