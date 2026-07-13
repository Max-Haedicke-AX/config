# DSC Configuration Project

Desired State Configuration (DSC) project for infrastructure and application configuration management.

## Project Structure

```
.
├── Roles/                 # DSC Roles
│   └── GitSetup/         # Git installation and configuration
│       ├── GitSetup.psm1 # Role module implementation
│       └── GitSetup.psd1 # Role manifest
├── Configurations/        # DSC Configurations
│   └── GitConfiguration.ps1
└── README.md
```

## Roles

### GitSetup
Installs Git via WinGet and configures global Git settings including:
- User name (from Windows username)
- User email
- core.autocrlf = true
- init.defaultBranch = main
- pull.rebase = false

## Quick Start

### Clone and Apply Git Configuration (One-Liner)

```powershell
git clone https://github.com/Max-Haedicke-AX/config.git c:\dsc-config; cd c:\dsc-config; powershell -ExecutionPolicy Bypass -Command "Import-Module '.\Roles\GitSetup\GitSetup.psm1' -Force; Install-GitRole"
```

### Manual Setup

1. **Clone the repository:**
```powershell
git clone https://github.com/Max-Haedicke-AX/config.git c:\dsc-config
cd c:\dsc-config
```

2. **Apply Git role:**
```powershell
Import-Module '.\Roles\GitSetup\GitSetup.psm1' -Force
Install-GitRole -UserEmail "your.email@company.com"
```

3. **Or use DSC configuration:**
```powershell
cd c:\dsc-config
. .\Configurations\GitConfiguration.ps1
GitConfiguration -OutputPath "C:\DscOutput"
Start-DscConfiguration -Path "C:\DscOutput" -Wait -Verbose
```

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- WinGet (Windows Package Manager)
- Administrator privileges for DSC application

## Configuration

Edit `Roles\GitSetup\GitSetup.psm1` to customize:
- Default email domain
- Additional Git configuration options

## Contributing

When adding new roles:
1. Create a new directory under `Roles/`
2. Include `RoleName.psm1` and `RoleName.psd1`
3. Add configuration examples in `Configurations/`
4. Update this README

## License

Internal Use Only
