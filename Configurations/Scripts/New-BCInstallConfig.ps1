<#
.SYNOPSIS
    Generates a Business Central installation configuration XML from the template.
.DESCRIPTION
    Reads bc-install.xml as a template and writes a bc-install-current.xml with all
    instance-specific parameters applied. Called by BusinessCentral.dsc.yaml.
.EXAMPLE
    .\New-BCInstallConfig.ps1 `
        -InstanceName "BC290" `
        -TargetPath "C:\Program Files\Microsoft Dynamics 365 Business Central\290" `
        -ServiceAccount "NT AUTHORITY\NetworkService" `
        -SqlServer "localhost" `
        -SqlDatabaseName "BC290"
#>
[CmdletBinding()]
param (
    # BC instance name, e.g. BC290
    [Parameter(Mandatory)]
    [string] $InstanceName,

    # Full installation target path, e.g. C:\Program Files\Microsoft Dynamics 365 Business Central\290
    [Parameter(Mandatory)]
    [string] $TargetPath,

    # Windows service account for the BC service tier
    [string] $ServiceAccount      = 'NT AUTHORITY\NetworkService',

    # Windows service account for the BC web client application pool
    [string] $WebClientAppPool    = 'NT AUTHORITY\NetworkService',

    # SQL Server hostname or IP
    [string] $SqlServer           = 'localhost',

    # SQL Server instance name (empty = default instance)
    [string] $SqlInstanceName     = '',

    # SQL Server database name
    [string] $SqlDatabaseName     = $InstanceName,

    # Authentication mode: Windows | NavUserPassword | UserName | AccessControlService
    [string] $AuthenticationMode  = 'Windows',

    # NST management service port
    [int]    $ManagementPort      = 7045,

    # NST client services port
    [int]    $ClientServicesPort  = 7085,

    # OData / SOAP web service port
    [int]    $WebServicePort      = 7047,
    [string] $WebServiceEnabled   = 'false',

    # OData v4 / REST data service port
    [int]    $DataServicePort     = 7048,
    [string] $DataServiceEnabled  = 'false',

    # AL developer service port
    [int]    $DeveloperServicePort   = 7049,
    [string] $DeveloperServiceEnabled = 'false',

    # Snapshot debugger port
    [int]    $SnapshotPort        = 7083,
    [string] $SnapshotEnabled     = 'false',

    # IIS Web Client port
    [int]    $WebServerPort       = 7140,

    # Path to the bc-install.xml template
    [string] $TemplateFile        = (Join-Path $PSScriptRoot 'bc-install.xml'),

    # Output path for the generated config
    [string] $OutputFile          = (Join-Path $PSScriptRoot 'bc-install-current.xml'),

    # Set to $true to delay BC service startup after installation
    [string] $PostponeServerStartup = 'false'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Load template ────────────────────────────────────────────────────────────
if (-not (Test-Path $TemplateFile)) {
    Write-Error "Template file not found: $TemplateFile"
    exit 1
}

[xml] $xml = Get-Content -Path $TemplateFile -Encoding UTF8

# ── Helper: update a <Parameter Id="..."> Value attribute ────────────────────
function Set-BcParam {
    param ([string] $Id, [string] $Value)
    $node = $xml.SelectSingleNode("//Parameter[@Id='$Id']")
    if ($null -ne $node) {
        $node.Value = $Value
    } else {
        Write-Warning "Parameter '$Id' not found in template – skipping."
    }
}

# ── Apply parameters ──────────────────────────────────────────────────────────
Set-BcParam 'TargetPath'                        $TargetPath
Set-BcParam 'TargetPathX64'                     $TargetPath
Set-BcParam 'NavServiceServerName'              'localhost'
Set-BcParam 'NavServiceInstanceName'            $InstanceName
Set-BcParam 'NavServiceAccount'                 $ServiceAccount
Set-BcParam 'ManagementServiceServerPort'       $ManagementPort.ToString()
Set-BcParam 'NavServiceClientServicesPort'      $ClientServicesPort.ToString()
Set-BcParam 'WebServiceServerPort'              $WebServicePort.ToString()
Set-BcParam 'WebServiceServerEnabled'           $WebServiceEnabled
Set-BcParam 'DataServiceServerPort'             $DataServicePort.ToString()
Set-BcParam 'DataServiceServerEnabled'          $DataServiceEnabled
Set-BcParam 'DeveloperServiceServerPort'        $DeveloperServicePort.ToString()
Set-BcParam 'DeveloperServiceServerEnabled'     $DeveloperServiceEnabled
Set-BcParam 'SnapshotDebuggerServiceServerPort' $SnapshotPort.ToString()
Set-BcParam 'SnapshotDebuggerEnabled'           $SnapshotEnabled
Set-BcParam 'CredentialTypeOption'              $AuthenticationMode
Set-BcParam 'SQLServer'                         $SqlServer
Set-BcParam 'SQLInstanceName'                   $SqlInstanceName
Set-BcParam 'SQLDatabaseName'                   $SqlDatabaseName
Set-BcParam 'PostponeServerStartup'             $PostponeServerStartup
Set-BcParam 'WebServerPort'                     $WebServerPort.ToString()

# ── Write output ──────────────────────────────────────────────────────────────
$xml.Save($OutputFile)

Write-Host "[OK] BC install config written to: $OutputFile" -ForegroundColor Green
Write-Host "     Instance : $InstanceName" -ForegroundColor Gray
Write-Host "     Target   : $TargetPath"   -ForegroundColor Gray
Write-Host "     SQL      : $SqlServer$(if ($SqlInstanceName) { '\' + $SqlInstanceName })\$SqlDatabaseName" -ForegroundColor Gray
