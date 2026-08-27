#Requires -Version 5.1
<#
.SYNOPSIS
    Backs up all databases of the configured SQL Server instances, verifies each
    backup, moves it to a final location and applies a calendar-based retention
    policy.
.DESCRIPTION
    Uses Windows authentication. The SqlServer module must be installed once via
    'Install-Module -Name SqlServer -Scope CurrentUser'. The script returns a
    non-zero exit code if any backup, verify or move step fails.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # SQL instances to back up. Each entry needs InstanceName, BackupPath and FinalBackupPath.
    [array]$SqlInstances = @(
        @{ InstanceName = "localhost\sql2025"; BackupPath = "C:\temp\SQLBackups\sql2025"; FinalBackupPath = "C:\Users\max.haedicke\OneDrive - VINCI Energies\Dokumente\_DBs\Backup\sql2025" }
    ),

    # Databases that are never backed up.
    [string[]]$ExcludedDatabases = @("master", "model", "msdb", "tempdb", "ExcludedDB", "Demo Database BC (24-0)"),

    # Keep every daily backup for this many days.
    [int]$DailyRetentionDays = 7,

    # Additionally keep one backup per calendar week for this many days.
    [int]$WeeklyRetentionDays = 28,

    # Additionally keep one backup per calendar month for this many months.
    [int]$MonthlyRetentionMonths = 5,

    [string]$LogFilePath = "C:\Users\max.haedicke\OneDrive - VINCI Energies\Dokumente\_DBs\Backup\SqlBackupLog.txt",

    # Roll the log file over once it grows past this size (bytes).
    [int]$MaxLogSizeBytes = 5MB
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Expose configuration to the helper functions via script scope.
$script:LogFilePath = $LogFilePath
$script:MaxLogSizeBytes = $MaxLogSizeBytes
$script:ExcludedDatabases = $ExcludedDatabases
$script:DailyRetentionDays = $DailyRetentionDays
$script:WeeklyRetentionDays = $WeeklyRetentionDays
$script:MonthlyRetentionMonths = $MonthlyRetentionMonths

# Metrics for the closing run summary.
$script:BackupErrorCount = 0
$script:BackupSuccessCount = 0
$script:RunStart = Get-Date

# Fail fast with a clear message instead of silently installing in a scheduled run.
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    throw "SqlServer module not found. Install it once with: Install-Module -Name SqlServer -Scope CurrentUser"
}
Import-Module SqlServer -ErrorAction Stop

# SqlServer module v22+ defaults to Encrypt=Mandatory; trust the server certificate
# on local/self-signed instances, but only if the installed module supports it.
$script:SqlcmdExtra = @{}
if ((Get-Command Invoke-Sqlcmd).Parameters.ContainsKey('TrustServerCertificate')) {
    $script:SqlcmdExtra['TrustServerCertificate'] = $true
}
$script:BackupExtra = @{}
if ((Get-Command Backup-SqlDatabase).Parameters.ContainsKey('TrustServerCertificate')) {
    $script:BackupExtra['TrustServerCertificate'] = $true
}

# Function to write log messages
function Write-BackupLog {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"

    switch ($Level) {
        "ERROR" { Write-Host $LogMessage -ForegroundColor Red }
        "WARNING" { Write-Host $LogMessage -ForegroundColor Yellow }
        default { Write-Host $LogMessage }
    }

    $LogDirectory = Split-Path -Path $LogFilePath -Parent
    if ($LogDirectory -and -not (Test-Path -Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    # Size-based rotation keeping a single ".1" archive.
    if ((Test-Path -Path $LogFilePath) -and (Get-Item -Path $LogFilePath).Length -gt $MaxLogSizeBytes) {
        Move-Item -Path $LogFilePath -Destination "$LogFilePath.1" -Force
    }

    Add-Content -Path $LogFilePath -Value $LogMessage -Encoding UTF8
}

# Function to move backup files from temp to final location
function Move-BackupFile {
    param (
        [string]$SourcePath,
        [string]$DestinationPath,
        # When set, only this single file is moved; otherwise all *.bak files.
        [string]$FileName
    )

    if (!(Test-Path -Path $SourcePath)) {
        Write-BackupLog -Message "Source backup path does not exist: $SourcePath" -Level "WARNING"
        return
    }

    if (!(Test-Path -Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }

    if ($FileName) {
        $BackupFiles = @(Get-ChildItem -Path (Join-Path -Path $SourcePath -ChildPath $FileName) -ErrorAction SilentlyContinue)
    }
    else {
        $BackupFiles = @(Get-ChildItem -Path $SourcePath -Filter "*.bak" -ErrorAction SilentlyContinue)
    }

    if ($BackupFiles.Count -eq 0) {
        Write-BackupLog -Message "No backup files found to move in $SourcePath" -Level "INFO"
        return
    }

    foreach ($BackupFile in $BackupFiles) {
        try {
            $DestinationFile = Join-Path -Path $DestinationPath -ChildPath $BackupFile.Name
            Write-BackupLog -Message "Moving backup file from '$($BackupFile.FullName)' to '$DestinationFile'" -Level "INFO"
            Move-Item -Path $BackupFile.FullName -Destination $DestinationFile -Force -ErrorAction Stop
            Write-BackupLog -Message "Successfully moved backup file: $($BackupFile.Name)" -Level "INFO"
        }
        catch {
            Write-BackupLog -Message "Failed to move backup file '$($BackupFile.Name)'. Error: $_" -Level "ERROR"
            $script:BackupErrorCount++
        }
    }
}

# Function to remove old backups based on a calendar-based retention policy.
# Retention no longer depends on when the script happens to run: it keeps every
# backup within the daily window, plus the newest backup of each calendar week
# and calendar month within their respective windows. Applied per database.
function Remove-OldBackup {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$BackupPath,
        [int]$DailyRetention,
        [int]$WeeklyRetention,
        [int]$MonthlyRetention
    )

    if (!(Test-Path -Path $BackupPath)) {
        Write-BackupLog -Message "Backup path does not exist: $BackupPath" -Level "WARNING"
        return
    }

    $Now = Get-Date
    $BackupFiles = @(Get-ChildItem -Path $BackupPath -Filter "*.bak" -ErrorAction SilentlyContinue)

    if ($BackupFiles.Count -eq 0) {
        Write-BackupLog -Message "No backup files found in $BackupPath" -Level "INFO"
        return
    }

    # Parse the timestamp encoded in each file name (DatabaseName_yyyyMMddHHmmss.bak).
    $Parsed = foreach ($BackupFile in $BackupFiles) {
        $DatePart = $BackupFile.BaseName.Split('_')[-1]
        $FileDate = [datetime]::MinValue
        if ($DatePart -match '^\d{14}$' -and
            [datetime]::TryParseExact($DatePart, 'yyyyMMddHHmmss', $null, [System.Globalization.DateTimeStyles]::None, [ref]$FileDate)) {
            [pscustomobject]@{
                File   = $BackupFile
                Date   = $FileDate
                DbName = $BackupFile.BaseName.Substring(0, $BackupFile.BaseName.Length - $DatePart.Length - 1)
            }
        }
        else {
            Write-BackupLog -Message "Cannot parse date from filename: $($BackupFile.Name)" -Level "WARNING"
        }
    }
    $Parsed = @($Parsed)

    if ($Parsed.Count -eq 0) {
        return
    }

    $Calendar = [System.Globalization.CultureInfo]::CurrentCulture.Calendar
    $KeepPaths = [System.Collections.Generic.HashSet[string]]::new()
    $MonthLimit = $Now.AddMonths(-$MonthlyRetention)

    foreach ($DbGroup in ($Parsed | Group-Object DbName)) {
        $Items = @($DbGroup.Group | Sort-Object Date -Descending)

        # Daily: keep every backup within the daily retention window.
        foreach ($Item in $Items | Where-Object { ($Now - $_.Date).TotalDays -le $DailyRetention }) {
            [void]$KeepPaths.Add($Item.File.FullName)
        }

        # Weekly: keep the newest backup of each calendar week within the weekly window.
        $WeekGroups = $Items |
            Where-Object { ($Now - $_.Date).TotalDays -le $WeeklyRetention } |
            Group-Object { '{0}-{1}' -f $_.Date.Year, $Calendar.GetWeekOfYear($_.Date, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [System.DayOfWeek]::Monday) }
        foreach ($Week in $WeekGroups) {
            $Newest = $Week.Group | Sort-Object Date -Descending | Select-Object -First 1
            [void]$KeepPaths.Add($Newest.File.FullName)
        }

        # Monthly: keep the newest backup of each calendar month within the monthly window.
        $MonthGroups = $Items |
            Where-Object { $_.Date -ge $MonthLimit } |
            Group-Object { '{0}-{1:D2}' -f $_.Date.Year, $_.Date.Month }
        foreach ($Month in $MonthGroups) {
            $Newest = $Month.Group | Sort-Object Date -Descending | Select-Object -First 1
            [void]$KeepPaths.Add($Newest.File.FullName)
        }
    }

    foreach ($Item in $Parsed) {
        if ($KeepPaths.Contains($Item.File.FullName)) {
            continue
        }
        try {
            Write-BackupLog -Message "Deleting old backup: $($Item.File.FullName)" -Level "WARNING"
            if ($PSCmdlet.ShouldProcess($Item.File.FullName, "Delete old backup file")) {
                Remove-Item -Path $Item.File.FullName -Force
            }
        }
        catch {
            Write-BackupLog -Message "Error deleting backup file $($Item.File.Name): $_" -Level "ERROR"
            $script:BackupErrorCount++
        }
    }
}

# Removes temp backups left behind by failed moves once they are older than a day.
function Remove-StaleTempBackup {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$BackupPath
    )

    if (!(Test-Path -Path $BackupPath)) {
        return
    }

    $StaleCutoff = (Get-Date).AddDays(-1)
    $StaleFiles = @(Get-ChildItem -Path $BackupPath -Filter "*.bak" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $StaleCutoff })

    foreach ($StaleFile in $StaleFiles) {
        try {
            Write-BackupLog -Message "Removing stale temp backup: $($StaleFile.FullName)" -Level "WARNING"
            if ($PSCmdlet.ShouldProcess($StaleFile.FullName, "Delete stale temp backup file")) {
                Remove-Item -Path $StaleFile.FullName -Force
            }
        }
        catch {
            Write-BackupLog -Message "Error removing stale temp backup $($StaleFile.Name): $_" -Level "ERROR"
            $script:BackupErrorCount++
        }
    }
}

# Function to back up databases for a given SQL instance
function Backup-SqlInstance {
    param (
        [string]$InstanceName,
        [string]$BackupPath,
        [string]$FinalBackupPath
    )

    # Ensure the backup directories exist.
    foreach ($Path in @($BackupPath, $FinalBackupPath)) {
        if ($Path -and -not (Test-Path -Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    }

    # Local copies of the version-safe connection splats for splatting.
    $SqlcmdExtra = $script:SqlcmdExtra
    $BackupExtra = $script:BackupExtra

    # Backup compression is not supported on SQL Server Express (EngineEdition 4).
    $UseCompression = $true
    try {
        $EngineEdition = (Invoke-Sqlcmd -ServerInstance $InstanceName -Query "SELECT SERVERPROPERTY('EngineEdition') AS EngineEdition" -ErrorAction Stop @SqlcmdExtra).EngineEdition
        if ($EngineEdition -eq 4) {
            $UseCompression = $false
            Write-BackupLog -Message "Instance '$InstanceName' is Express edition; disabling backup compression." -Level "INFO"
        }
    }
    catch {
        Write-BackupLog -Message "Could not determine engine edition for '$InstanceName'; continuing without compression. Error: $_" -Level "WARNING"
        $UseCompression = $false
    }

    # Only back up databases that are online, accessible and not snapshots.
    $Databases = Get-SqlDatabase -ServerInstance $InstanceName @SqlcmdExtra | Where-Object {
        $ExcludedDatabases -notcontains $_.Name -and $_.IsAccessible -and -not $_.IsDatabaseSnapshot
    }

    foreach ($Database in $Databases) {
        $BackupFileName = "$($Database.Name)_$(Get-Date -Format 'yyyyMMddHHmmss').bak"
        $TempBackupFile = Join-Path -Path $BackupPath -ChildPath $BackupFileName

        try {
            Write-BackupLog -Message "Backing up database '$($Database.Name)' on instance '$InstanceName' to '$TempBackupFile'" -Level "INFO"

            $CompressionOption = if ($UseCompression) { 'On' } else { 'Off' }
            Backup-SqlDatabase -Database $Database.Name -ServerInstance $InstanceName -BackupFile $TempBackupFile -CompressionOption $CompressionOption -Checksum -ErrorAction Stop @BackupExtra

            # Verify the backup (including page checksums) is restorable before trusting it.
            Write-BackupLog -Message "Verifying backup '$TempBackupFile'" -Level "INFO"
            Invoke-Sqlcmd -ServerInstance $InstanceName -Query "RESTORE VERIFYONLY FROM DISK = N'$TempBackupFile' WITH CHECKSUM" -ErrorAction Stop @SqlcmdExtra | Out-Null
            Write-BackupLog -Message "Successfully backed up and verified database '$($Database.Name)'" -Level "INFO"

            # Move immediately so a later failure cannot orphan a verified backup.
            if ($FinalBackupPath) {
                Move-BackupFile -SourcePath $BackupPath -DestinationPath $FinalBackupPath -FileName $BackupFileName
            }

            $script:BackupSuccessCount++
        }
        catch {
            Write-BackupLog -Message "Failed to back up database '$($Database.Name)' on instance '$InstanceName'. Error: $_" -Level "ERROR"
            $script:BackupErrorCount++
        }
    }

    # Clean up temp backups orphaned by earlier failed moves.
    Remove-StaleTempBackup -BackupPath $BackupPath

    # Apply retention only after new backups exist in the final location.
    if ($FinalBackupPath) {
        Remove-OldBackup -BackupPath $FinalBackupPath -DailyRetention $DailyRetentionDays -WeeklyRetention $WeeklyRetentionDays -MonthlyRetention $MonthlyRetentionMonths
    }
}

# Backup databases for each instance
foreach ($SqlInstance in $SqlInstances) {
    Write-BackupLog -Message "Starting backup for instance '$($SqlInstance.InstanceName)'" -Level "INFO"
    try {
        Backup-SqlInstance -InstanceName $SqlInstance.InstanceName -BackupPath $SqlInstance.BackupPath -FinalBackupPath $SqlInstance.FinalBackupPath
    }
    catch {
        Write-BackupLog -Message "Unhandled error while backing up instance '$($SqlInstance.InstanceName)': $_" -Level "ERROR"
        $script:BackupErrorCount++
    }
    Write-BackupLog -Message "Finished backup for instance '$($SqlInstance.InstanceName)'" -Level "INFO"
}

$Duration = (Get-Date) - $script:RunStart
$Summary = "Summary: $($script:BackupSuccessCount) database(s) backed up, $($script:BackupErrorCount) error(s), duration $($Duration.ToString('hh\:mm\:ss'))."

if ($script:BackupErrorCount -gt 0) {
    Write-BackupLog -Message $Summary -Level "ERROR"
    exit 1
}

Write-BackupLog -Message $Summary -Level "INFO"
exit 0