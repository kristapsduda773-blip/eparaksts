$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

$PackageId = 'eParaksts.eParakstitajs'
$WingetNoApplicableInstallerCode = -1978335216

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

function Invoke-Winget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WingetPath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $process = Start-Process -FilePath $WingetPath `
                             -ArgumentList $Arguments `
                             -Wait `
                             -PassThru `
                             -NoNewWindow
    return $process.ExitCode
}

$wingetPath = Get-WingetPath
$baseArguments = @(
    'install',
    '--id', $PackageId,
    '--exact',
    '--source', 'winget',
    '--silent',
    '--accept-source-agreements',
    '--accept-package-agreements',
    '--disable-interactivity'
)

$attempts = @()
$attempts += ,@{
    Name = 'default'
    Args = $baseArguments
}

# Explicit architecture retries help when Winget cannot auto-select a compatible installer.
$osArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
if ($osArchitecture -eq 'arm64' -or $osArchitecture -eq 'x64') {
    $attempts += ,@{
        Name = 'x64'
        Args = $baseArguments + @('--architecture', 'x64')
    }
    $attempts += ,@{
        Name = 'x86'
        Args = $baseArguments + @('--architecture', 'x86')
    }
} elseif ($osArchitecture -eq 'x86') {
    $attempts += ,@{
        Name = 'x86'
        Args = $baseArguments + @('--architecture', 'x86')
    }
}

$sourceUpdated = $false
$finalExitCode = 1

foreach ($attempt in $attempts) {
    Write-Host "Running Winget install attempt: $($attempt.Name)"
    $finalExitCode = Invoke-Winget -WingetPath $wingetPath -Arguments $attempt.Args

    if ($finalExitCode -eq 0) {
        Write-Host "Install completed successfully for $PackageId."
        exit 0
    }

    if ($finalExitCode -eq 3010) {
        Write-Host "Install completed for $PackageId. Reboot required."
        exit 3010
    }

    if ($finalExitCode -eq $WingetNoApplicableInstallerCode -and -not $sourceUpdated) {
        Write-Host 'No applicable installer found. Updating Winget source and retrying current attempt once.'
        [void](Invoke-Winget -WingetPath $wingetPath -Arguments @('source', 'update', 'winget'))
        $sourceUpdated = $true

        $finalExitCode = Invoke-Winget -WingetPath $wingetPath -Arguments $attempt.Args
        if ($finalExitCode -eq 0) {
            Write-Host "Install completed successfully for $PackageId."
            exit 0
        }

        if ($finalExitCode -eq 3010) {
            Write-Host "Install completed for $PackageId. Reboot required."
            exit 3010
        }
    }

    if ($finalExitCode -ne $WingetNoApplicableInstallerCode) {
        break
    }
}

if ($finalExitCode -eq $WingetNoApplicableInstallerCode) {
    Write-Host "Install failed for $PackageId: no applicable Winget installer for this device."
    Write-Host 'Tip: package currently publishes x86/x64 installers; verify device architecture support and App Installer version.'
} else {
    Write-Host "Install failed for $PackageId with exit code $finalExitCode."
}

exit $finalExitCode
