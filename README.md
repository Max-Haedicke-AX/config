# DSC v3 Minimalprojekt

Dieses Repo enthält eine minimale DSC-v3-Konfiguration für Git.

## Datei

- Config: ./Configurations/GitConfiguration.dsc.yaml

## Voraussetzungen

- Windows 10/11
- winget
- DSC v3 CLI

Installation der DSC CLI:

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
