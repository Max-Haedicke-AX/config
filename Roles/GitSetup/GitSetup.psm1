function Install-GitRole {
    <#
    .SYNOPSIS
    Installs and configures Git with global settings.
    
    .DESCRIPTION
    Installs Git via WinGet and configures global user settings.
    
    .PARAMETER UserEmail
    Email address for Git configuration. Defaults to $env:USERNAME@company.com
    
    .PARAMETER AdditionalConfig
    Optional hashtable with additional Git configurations
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$UserEmail = "$($env:USERNAME.ToLower())@vinci-energies.net",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$AdditionalConfig = @{
            'core.autocrlf'        = 'true'
            'init.defaultBranch'   = 'main'
            'pull.rebase'          = 'false'
        }
    )

    Write-Host "=== Installing and Configuring Git ===" -ForegroundColor Cyan
    
    # Generate user name from environment
    $textInfo = (Get-Culture).TextInfo
    $UserName = $textInfo.ToTitleCase(($env:USERNAME -replace '\.', ' ').ToLower())
    
    Write-Host "Email: $UserEmail | Name: $UserName" -ForegroundColor Cyan
    Write-Host ""

    # Check if Git is already installed
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitVersion = git --version
        Write-Host "[OK] Git already installed: $gitVersion" -ForegroundColor Green
    }
    else {
        # Install Git via WinGet
        Write-Host "Installing Git via WinGet..." -ForegroundColor Yellow
        try {
            & winget install --id Git.Git -e --silent
            Write-Host "[OK] Git installed successfully" -ForegroundColor Green
            
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        }
        catch {
            Write-Host "[ERROR] Failed to install Git: $_" -ForegroundColor Red
            throw "Git installation failed"
        }
    }
    Write-Host ""

    # Configure Git global settings
    Write-Host "Configuring Git global settings..." -ForegroundColor Yellow
    
    git config --global user.name $UserName
    Write-Host "[OK] User name: $UserName" -ForegroundColor Green
    
    git config --global user.email $UserEmail
    Write-Host "[OK] User email: $UserEmail" -ForegroundColor Green
    
    # Apply additional configurations
    foreach ($key in $AdditionalConfig.Keys) {
        git config --global $key $AdditionalConfig[$key]
        Write-Host "[OK] Set $key = $($AdditionalConfig[$key])" -ForegroundColor Green
    }
    Write-Host ""

    # Display current configuration
    Write-Host "=== Current Git Configuration ===" -ForegroundColor Cyan
    git config --global --list | Where-Object { $_ -like "user.*" -or $_ -like "core.*" -or $_ -like "init.*" -or $_ -like "pull.*" }
    Write-Host ""
    
    Write-Host "=== Git Configuration Complete ===" -ForegroundColor Green
}

# Export function
Export-ModuleMember -Function Install-GitRole
