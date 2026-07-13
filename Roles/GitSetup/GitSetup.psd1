@{
    RootModule            = 'GitSetup.psm1'
    ModuleVersion         = '1.0.0'
    GUID                  = '12345678-1234-1234-1234-123456789012'
    Author                = 'Max Hädicke'
    CompanyName           = 'Vinci Energies'
    Description           = 'DSC Role for Git installation and configuration'
    PowerShellVersion     = '5.1'
    FunctionsToExport     = @('Install-GitRole')
    PrivateData           = @{
        PSData = @{
            Tags       = @('DSC', 'Git', 'Configuration')
            ProjectUri = 'https://github.com/Max-Haedicke-AX/config.git'
        }
    }
}
