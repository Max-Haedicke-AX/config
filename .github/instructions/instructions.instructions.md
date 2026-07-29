description: DSC v3 project instructions for configuration files, validation, and VS Code tasks.
applyTo: "Configurations/**/*.dsc.yaml,.vscode/tasks.json,README.md"
---

## Purpose
These instructions define how to create, edit, validate, and execute DSC v3 configurations in this repository.

## When to load
Load these instructions when a task includes one of the following:
- Creating or editing DSC v3 YAML files in `Configurations/`
- Fixing `dsc config test/set/get` failures
- Adding or changing VS Code tasks for DSC commands
- Updating run instructions in `README.md`

## Repository conventions
- Use DSC v3 YAML with this schema line:
	- `$schema: https://aka.ms/dsc/schemas/v3/bundled/config/document.json`
- Prefer one-file configs per topic under `Configurations/`.
- Keep resource names explicit and stable (for example `InstallGit`, `LenovoVantage`).

## Adding a new DSC configuration file
When creating a new `Configurations/*.dsc.yaml`, always also update these two files:
1. **`bootstrap.ps1`** — add the filename to `$DSC_CONFIGS` in the correct execution order (System first, Git-Repos last).
2. **`.vscode/tasks.json`** — add the path to the `options` array of the `dscConfigFile` pickString input.

Current execution order in `bootstrap.ps1`:
```
System-Configuration → WinGet-Apps → GitConfiguration → PowerShell-Modules
→ VSCode-Setup → Git-Repos → WSL-Setup → Store-Apps → AppSpace-Setup
```

## WinGet resource rules
- Use `Microsoft.WinGet/Package` for package/app installation.
- Use `_exist: true` instead of `ensure: Present`.
- Prefer `acceptAgreements: true` when agreements are needed.
- Keep `id` and `source` explicit (`winget` or `msstore`).

## Process/command execution rules
- Do not assume `Microsoft.Windows/Process` exists.
- On this repo/machine baseline, use `Microsoft.DSC.Transitional/RunCommandOnSet` for command execution.
- Note: `RunCommandOnSet` is not idempotent and may show warnings during test/set.

## Validation workflow (required)
After changing a DSC config, run:
1. `dsc config test --file .\\Configurations\\<file>.dsc.yaml --output-format pretty-json`
2. `dsc config set --file .\\Configurations\\<file>.dsc.yaml --output-format pretty-json`
3. `dsc config get --file .\\Configurations\\<file>.dsc.yaml --output-format pretty-json`

If schema errors occur:
- Check available resources with `dsc resource list`
- Verify resource schema with `dsc resource schema --resource <Type> --output-format yaml`
- Align YAML properties exactly to the reported schema

## VS Code task conventions
- Keep DSC tasks in `.vscode/tasks.json`.
- Prefer selectable input for file choice (pickString) over hardcoded single-file tasks.
- Default output format should be `pretty-json`.

## Editing guidelines
- Make minimal diffs and preserve existing naming style.
- Do not change unrelated configuration files.
- When documenting commands, use commands that were verified in this environment.