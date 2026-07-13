Configuration GitConfiguration {
    <#
    .DESCRIPTION
    DSC Configuration for Git setup role
    #>
    
    param(
        [string]$UserEmail = "$($env:USERNAME.ToLower())@vinci-energies.net"
    )
    
    # Import the GitSetup role
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    
    Node "localhost" {
        # Execute the Git installation and configuration
        Script InstallAndConfigureGit {
            SetScript = {
                # Import the role module
                Import-Module -Name "$PSScriptRoot\..\Roles\GitSetup" -Force
                Install-GitRole -UserEmail $using:UserEmail
            }
            
            TestScript = {
                # Test if Git is installed
                $gitExists = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
                if ($gitExists) {
                    $gitConfig = git config --global user.email
                    return $gitConfig -eq $using:UserEmail
                }
                return $false
            }
            
            GetScript = {
                $gitExists = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
                if ($gitExists) {
                    $result = @{
                        GitInstalled = $true
                        UserEmail    = git config --global user.email
                        UserName     = git config --global user.name
                        Version      = git --version
                    }
                }
                else {
                    $result = @{
                        GitInstalled = $false
                    }
                }
                return $result
            }
        }
    }
}
