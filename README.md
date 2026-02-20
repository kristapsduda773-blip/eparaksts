# eParakstitajs 3.0 Intune Win32 (Winget)

This package installs and uninstalls **eParakstitajs** through Winget in **SYSTEM context**.

## Files

- `Install.ps1` - Installs latest `eParaksts.eParakstitajs` and retries with explicit architectures when needed.
- `Uninstall.ps1` - Uninstalls with Winget, then MSI fallback cleanup.
- `Detect.ps1` - Detects installation from HKLM uninstall entries (version-agnostic).

## Intune configuration (recommended)

### Program

- **Install command**
  - `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1`
- **Uninstall command**
  - `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1`
- **Install behavior**
  - `System`  **(important)**

> Do not use `cmd.exe /c start ...` for Win32 install/uninstall commands.  
> `start` can return before the script finishes, causing false success/failure in Intune.
> Scripts require elevated/SYSTEM context.

### Detection rules

- **Use a custom detection script**
  - Script file: `Detect.ps1`
- **Run script as 32-bit process on 64-bit clients**
  - `No`
- **Enforce script signature check and run script silently**
  - `No`

### Requirements

- Architecture: `x64` (recommended)
- Minimum OS: your target baseline (example: Windows 11 24H2)

## Notes

- Winget package ID used: `eParaksts.eParakstitajs`
- Script installs **latest available version** from Winget.
- The package currently publishes `x86`/`x64` installers in Winget; use `arm64` only after pilot validation.
- During install/uninstall, Windows Explorer may briefly restart because of shell integration changes made by the vendor MSI.
