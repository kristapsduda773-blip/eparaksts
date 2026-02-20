$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

$PackageId = 'eParaksts.eParakstitajs'
$WingetNoApplicableInstallerCode = -1978335216

function Test-IsElevatedOrSystem {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($identity.Name -eq 'NT AUTHORITY\SYSTEM') {
        return $true
    }

    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

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

function Get-OsArchitecture {
    # RuntimeInformation.OSArchitecture is unavailable on some older .NET/PowerShell combinations.
    $runtimeType = [System.Runtime.InteropServices.RuntimeInformation]
    $osArchProperty = $runtimeType.GetProperty('OSArchitecture', [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static)
    if ($osArchProperty) {
        try {
            $runtimeArchitecture = $runtimeType::OSArchitecture.ToString().ToLowerInvariant()
            if ($runtimeArchitecture) {
                return $runtimeArchitecture
            }
        } catch {
            # Ignore and continue to environment-based fallback.
        }
    }

    $archCandidates = @(
        $env:PROCESSOR_ARCHITECTURE,
        $env:PROCESSOR_ARCHITEW6432
    ) | Where-Object { $_ }

    foreach ($candidate in $archCandidates) {
        $arch = $candidate.ToLowerInvariant()
        if ($arch -eq 'arm64') {
            return 'arm64'
        }

        if ($arch -eq 'amd64' -or $arch -eq 'x64') {
            return 'x64'
        }

        if ($arch -eq 'x86' -or $arch -eq 'i386' -or $arch -eq 'i686') {
            return 'x86'
        }
    }

    if ([Environment]::Is64BitOperatingSystem) {
        return 'x64'
    }

    return 'x86'
}

if (-not (Test-IsElevatedOrSystem)) {
    Write-Host 'Install must run elevated or in SYSTEM context (Intune install behavior: System).'
    exit 1
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
$osArchitecture = Get-OsArchitecture
Write-Host "Detected OS architecture: $osArchitecture"
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
    Write-Host "Install failed for ${PackageId}: no applicable Winget installer for this device."
    Write-Host 'Tip: package currently publishes x86/x64 installers; verify device architecture support and App Installer version.'
} else {
    Write-Host "Install failed for $PackageId with exit code $finalExitCode."
}

exit $finalExitCode
