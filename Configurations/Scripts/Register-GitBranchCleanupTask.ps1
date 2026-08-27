[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TaskName,
    [Parameter(Mandatory)]
    [string]$RepositoryRoot,
    [Parameter(Mandatory)]
    [string]$CleanupScriptPath,
    [Parameter(Mandatory)]
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($path in @($CleanupScriptPath, $RepositoryRoot)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required path not found: $path"
    }
}

$actionArguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    $CleanupScriptPath + '" -Root "' + $RepositoryRoot + '" -LogPath "' + $LogPath + '" -Yes'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $actionArguments
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Thursday -At (Get-Date -Hour 12 -Minute 0 -Second 0)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal `
    -Description 'Deletes safely removable local Git branches on Mondays and Thursdays at 12:00' -Force | Out-Null

Write-Host "[OK] Scheduled task '$TaskName' registered (Mondays and Thursdays at 12:00)"
