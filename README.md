# DSC v3 Machine Setup

Dieses Repo enthält DSC v3-Konfigurationen für die vollautomatische Einrichtung eines Entwickler-PCs.

## Neuen Rechner einrichten (One-Liner)

PowerShell **als Administrator** öffnen und ausführen:

```powershell
irm https://raw.githubusercontent.com/Max-Haedicke-AX/config/main/bootstrap.ps1 | iex
```

Das Skript erledigt automatisch:

1. Winget prüfen / installieren
2. DSC v3 installieren (`Microsoft.DSC`)
3. Git installieren
4. Dieses Repo nach `C:\DEV\config` klonen
5. Alle DSC-Konfigurationen in der richtigen Reihenfolge anwenden

## Konfigurationen (Ausführungsreihenfolge)

| Datei | Inhalt |
| --- | --- |
| `System-Configuration.dsc.yaml` | Basis-System, Ordner, Execution Policy |
| `WinGet-Apps.dsc.yaml` | Apps via winget |
| `GitConfiguration.dsc.yaml` | Git-Konfiguration |
| `PowerShell-Modules.dsc.yaml` | PowerShell-Module |
| `WSL-Setup.dsc.yaml` | WSL |
| `Store-Apps.dsc.yaml` | Microsoft Store Apps |
| `BusinessCentral.dsc.yaml` | Business Central Setup |
| `AppSpace-Setup.dsc.yaml` | AppSpace Setup |
| `SQLServer2025.dsc.yaml` | SQL Server 2025 |
| `Git-Repos.dsc.yaml` | Repositories klonen |

## Voraussetzungen

- Windows 10/11
- PowerShell 5.1+ (vorinstalliert)
- Internetverbindung

## Manuelle Installation von DSC v3

```powershell
winget install --id Microsoft.DSC --exact --source winget --accept-source-agreements --accept-package-agreements
```

Version prüfen:

```powershell
dsc --version
```

## Build und Ausführen

Bei DSC v3 YAML gibt es keinen klassischen MOF-Build mehr. Stattdessen validierst und wendest du die Konfiguration direkt an.

1. Konfiguration testen (Dry Run)

```powershell
dsc config test --file .\Configurations\GitConfiguration.dsc.yaml --output-format pretty-json
```

1. Konfiguration anwenden

```powershell
dsc config set --file .\Configurations\GitConfiguration.dsc.yaml --output-format pretty-json
```

1. Aktuellen Zustand abrufen

```powershell
dsc config get --file .\Configurations\GitConfiguration.dsc.yaml --output-format pretty-json
```

## Hinweis

Die Git-Konfiguration nutzt derzeit den verfügbaren Ressourcentyp Microsoft.DSC.Transitional/RunCommandOnSet.
Die Paketinstallation erfolgt über Microsoft.WinGet/Package mit `_exist: true`.
`RunCommandOnSet` ist laut DSC-Hinweis nicht idempotent.
