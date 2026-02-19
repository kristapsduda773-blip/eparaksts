$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

$PackageId = 'eParaksts.eParakstitajs'

function Get-WingetPath {
    $command = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        return $command.Source
    }

    # SYSTEM context often needs the full path from WindowsApps.
    $searchPatterns = @(
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe",
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_neutral_*_8wekyb3d8bbwe\winget.exe",
        "$env:LocalAppData\Microsoft\WindowsApps\winget.exe"
    )

    foreach ($pattern in $searchPatterns) {
        $candidate = Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue |
            Sort-Object -Property FullName -Descending |
            Select-Object -First 1

        if ($candidate) {
            return $candidate.FullName
        }
    }

    throw 'winget.exe was not found. Ensure Microsoft App Installer is present on the device.'
}

$wingetPath = Get-WingetPath
$wingetArguments = @(
    'install',
    '--id', $PackageId,
    '--exact',
    '--source', 'winget',
    '--silent',
    '--scope', 'machine',
    '--accept-source-agreements',
    '--accept-package-agreements',
    '--disable-interactivity'
)

$process = Start-Process -FilePath $wingetPath `
                         -ArgumentList $wingetArguments `
                         -Wait `
                         -PassThru `
                         -NoNewWindow

if ($process.ExitCode -eq 0) {
    Write-Host "Install completed successfully for $PackageId."
} elseif ($process.ExitCode -eq 3010) {
    Write-Host "Install completed for $PackageId. Reboot required."
} else {
    Write-Host "Install failed for $PackageId with exit code $($process.ExitCode)."
}

exit $process.ExitCode
