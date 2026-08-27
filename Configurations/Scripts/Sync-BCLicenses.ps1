<#
.SYNOPSIS
    Mirrors Business Central development license files from the network share to a local folder.

.DESCRIPTION
    Invoked by the "BC-LicenseSync" scheduled task (see BCLicenseSync-Task.dsc.yaml).
    Skips silently if the network share is not reachable (e.g. off VPN/LAN).
    Wipes the local folder first so it always exactly matches the share afterwards.
#>

param(
    [string]$NetworkLicensePath = '\\S-1564-INFDRIVE\Business Central\DevelopmentLicenses',
    [string]$LocalLicensePath   = 'C:\DEV\_DevelopmentLicenses'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $NetworkLicensePath)) {
    Write-Warning "Network license share not reachable: $NetworkLicensePath"
    exit 0
}

New-Item -ItemType Directory -Force -Path $LocalLicensePath | Out-Null

Get-ChildItem -Path $LocalLicensePath -Force | Remove-Item -Recurse -Force
Copy-Item -Path (Join-Path $NetworkLicensePath '*') -Destination $LocalLicensePath -Recurse -Force

Write-Host "[OK] Synced licenses from '$NetworkLicensePath' to '$LocalLicensePath'"
