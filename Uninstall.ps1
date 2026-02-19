$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

$PackageId = 'eParaksts.eParakstitajs'
$rebootRequired = $false
$WingetNoInstalledPackageCode = -1978335212

function Get-SafeStringPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    $property = $Object.PSObject.Properties[$PropertyName]
    if (-not $property -or $null -eq $property.Value) {
        return $null
    }

    return [string]$property.Value
}

function Get-WingetPath {
    $command = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        return $command.Source
    }

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

    throw 'winget.exe was not found.'
}

function Get-EParakstitajsEntries {
    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    return Get-ItemProperty -Path $uninstallPaths -ErrorAction SilentlyContinue |
        Where-Object {
            $displayName = Get-SafeStringPropertyValue -Object $_ -PropertyName 'DisplayName'
            $displayName -and ($displayName -match '^eParakst') -and ($displayName -match '3\.0')
        }
}

function Test-EParakstitajsInstalled {
    $entries = Get-EParakstitajsEntries
    if ($entries) {
        return $true
    }

    $shortcutCandidates = Get-ChildItem -Path 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\eParakst*3.0\*.lnk' `
                                        -File `
                                        -ErrorAction SilentlyContinue
    return [bool]$shortcutCandidates
}

function Get-InstalledProductCodes {
    $entries = Get-EParakstitajsEntries

    $codes = foreach ($entry in $entries) {
        $childName = Get-SafeStringPropertyValue -Object $entry -PropertyName 'PSChildName'
        if ($childName -and ($childName -match '^\{[0-9A-Fa-f\-]{36}\}$')) {
            $childName
            continue
        }

        $uninstallString = Get-SafeStringPropertyValue -Object $entry -PropertyName 'UninstallString'
        if ($uninstallString -and ($uninstallString -match '\{[0-9A-Fa-f\-]{36}\}')) {
            $Matches[0]
        }
    }

    return $codes | Sort-Object -Unique
}

try {
    $wingetPath = Get-WingetPath
    $wingetArguments = @(
        'uninstall',
        '--id', $PackageId,
        '--exact',
        '--source', 'winget',
        '--silent',
        '--disable-interactivity'
    )

    $wingetProcess = Start-Process -FilePath $wingetPath `
                                   -ArgumentList $wingetArguments `
                                   -Wait `
                                   -PassThru `
                                   -NoNewWindow
    Write-Host "Winget uninstall exit code: $($wingetProcess.ExitCode)"
    if ($wingetProcess.ExitCode -eq $WingetNoInstalledPackageCode) {
        Write-Host 'Winget did not find an installed package for this ID. Continuing with MSI fallback checks.'
    }
} catch {
    Write-Host "Winget uninstall step skipped: $($_.Exception.Message)"
}

if (Test-EParakstitajsInstalled) {
    $productCodes = Get-InstalledProductCodes

    foreach ($productCode in $productCodes) {
        $msiProcess = Start-Process -FilePath 'msiexec.exe' `
                                    -ArgumentList @('/x', $productCode, '/qn', '/norestart') `
                                    -Wait `
                                    -PassThru `
                                    -NoNewWindow

        switch ($msiProcess.ExitCode) {
            0 { Write-Host "Removed MSI product $productCode." }
            1605 { Write-Host "MSI product not installed: $productCode." }
            1614 { Write-Host "MSI product already removed: $productCode." }
            3010 {
                Write-Host "Removed MSI product $productCode. Reboot required."
                $rebootRequired = $true
            }
            1641 {
                Write-Host "Removed MSI product $productCode. Reboot initiated."
                $rebootRequired = $true
            }
            default {
                throw "MSI uninstall failed for $productCode with exit code $($msiProcess.ExitCode)."
            }
        }
    }
}

$shortcutFolders = Get-ChildItem -Path 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\eParakst*3.0' `
                                 -Directory `
                                 -ErrorAction SilentlyContinue
foreach ($folder in $shortcutFolders) {
    Remove-Item -LiteralPath $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-EParakstitajsInstalled) {
    Write-Host 'Uninstall failed: eParakstitajs 3.0 still detected.'
    exit 1
}

Write-Host 'Uninstall complete.'
if ($rebootRequired) {
    exit 3010
}

exit 0
