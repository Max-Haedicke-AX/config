#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap script for automated DSC v3 machine setup.

.DESCRIPTION
    Downloads and applies all DSC v3 configurations from the config repository.
    Installs DSC v3 via winget if not present, clones the repo, and runs all
    configurations in the correct order.

.EXAMPLE
    irm https://raw.githubusercontent.com/Max-Haedicke-AX/config/main/bootstrap.ps1 | iex

.NOTES
    Must be run as Administrator. The script will self-elevate if needed.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$REPO_URL    = 'https://github.com/Max-Haedicke-AX/config.git'
$REPO_PATH   = 'C:\DEV\config'
$DSC_PACKAGE = 'Microsoft.DSC'

# Execution order matters: System first, Git-Repos last (needs git installed)
$DSC_CONFIGS = @(
    'System-Configuration.dsc.yaml',
    'WinGet-Apps.dsc.yaml',
    'GitConfiguration.dsc.yaml',
    'PowerShell-Modules.dsc.yaml',
    'Git-Repos.dsc.yaml',
    'WSL-Setup.dsc.yaml',
    'Store-Apps.dsc.yaml',
    'AppSpace-Setup.dsc.yaml'
)

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "    [WARN] $Message" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Self-elevation
# ---------------------------------------------------------------------------
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host 'Restarting as Administrator...' -ForegroundColor Yellow
    $psArgs = "-NoProfile -ExecutionPolicy Bypass -Command `"irm '$REPO_URL/raw/main/bootstrap.ps1' | iex`""
    # When piped via iex there is no script file path - re-launch from the raw URL
    Start-Process -FilePath 'pwsh.exe' -ArgumentList $psArgs -Verb RunAs
    exit
}

# ---------------------------------------------------------------------------
# 1. Ensure winget is available
# ---------------------------------------------------------------------------
Write-Step 'Checking winget...'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warn 'winget not found. Installing App Installer from Microsoft Store...'
    # winget ships with App Installer; add-appxpackage is the fallback on Win10
    $installer = "$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle"
    Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile $installer -UseBasicParsing
    Add-AppxPackage -Path $installer -ErrorAction Stop
    Remove-Item $installer -Force
}
Write-Success 'winget is available.'

# ---------------------------------------------------------------------------
# 2. Ensure DSC v3 is installed
# ---------------------------------------------------------------------------
Write-Step 'Checking DSC v3...'
if (-not (Get-Command dsc -ErrorAction SilentlyContinue)) {
    Write-Warn 'DSC v3 not found. Installing via winget...'
    winget install --id $DSC_PACKAGE --exact --source winget `
        --accept-source-agreements --accept-package-agreements --silent
    # Refresh PATH for this session
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('PATH', 'User')
}
$dscVersion = dsc --version 2>&1
Write-Success "DSC version: $dscVersion"

# ---------------------------------------------------------------------------
# 3. Ensure git is available (needed for clone)
# ---------------------------------------------------------------------------
Write-Step 'Checking git...'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warn 'git not found. Installing via winget...'
    winget install --id Git.Git --exact --source winget `
        --accept-source-agreements --accept-package-agreements --silent
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('PATH', 'User')
}
Write-Success 'git is available.'

# ---------------------------------------------------------------------------
# 4. Clone / update config repository
# ---------------------------------------------------------------------------
Write-Step 'Preparing config repository...'
if (-not (Test-Path $REPO_PATH)) {
    Write-Host "    Cloning $REPO_URL to $REPO_PATH..."
    git clone $REPO_URL $REPO_PATH
} else {
    Write-Host "    $REPO_PATH already exists, pulling latest changes..."
    git -C $REPO_PATH pull --ff-only
}
Write-Success "Config repo ready at $REPO_PATH"

# ---------------------------------------------------------------------------
# 5. Apply each DSC configuration
# ---------------------------------------------------------------------------

# Ensure winget sources are accepted/updated before running WinGet DSC resources.
# Without this, Microsoft.WinGet/Package fails with 0x8A150014 in a fresh admin session.
Write-Step 'Updating winget sources...'
winget source update --accept-source-agreements
Write-Success 'Winget sources updated.'

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($configFile in $DSC_CONFIGS) {
    $configPath = Join-Path (Join-Path $REPO_PATH 'Configurations') $configFile
    Write-Step "Applying: $configFile"

    if (-not (Test-Path $configPath)) {
        Write-Warn "Config file not found, skipping: $configPath"
        $results.Add([PSCustomObject]@{ Config = $configFile; Status = 'Skipped' })
        continue
    }

    try {
        dsc config set --file $configPath --output-format pretty-json
        Write-Success "$configFile applied successfully."
        $results.Add([PSCustomObject]@{ Config = $configFile; Status = 'OK' })
    } catch {
        Write-Warn "Failed: $configFile - $_"
        $results.Add([PSCustomObject]@{ Config = $configFile; Status = "Error: $_" })
    }
}

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host '  Bootstrap Summary' -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$errors = $results | Where-Object { $_.Status -like 'Error*' }
if ($errors) {
    Write-Host "`nSome configurations failed. Check the output above." -ForegroundColor Yellow
    # exit 1
} else {
    Write-Host 'All configurations applied successfully!' -ForegroundColor Green
    # exit 0
}
