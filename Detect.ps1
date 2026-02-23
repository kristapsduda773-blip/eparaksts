$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

if (-not ('NativeMethods.Msi' -as [type])) {
    Add-Type -Namespace NativeMethods -Name Msi -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("msi.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int MsiQueryProductState(string szProduct);
"@
}

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

function Get-ProductCodeFromEntry {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Entry
    )

    $childName = Get-SafeStringPropertyValue -Object $Entry -PropertyName 'PSChildName'
    if ($childName -and ($childName -match '^\{[0-9A-Fa-f\-]{36}\}$')) {
        return $childName
    }

    $uninstallString = Get-SafeStringPropertyValue -Object $Entry -PropertyName 'UninstallString'
    if ($uninstallString -and ($uninstallString -match '\{[0-9A-Fa-f\-]{36}\}')) {
        return $Matches[0]
    }

    return $null
}

function Test-MsiProductInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProductCode
    )

    if ($ProductCode -notmatch '^\{[0-9A-Fa-f\-]{36}\}$') {
        return $false
    }

    $state = [NativeMethods.Msi]::MsiQueryProductState($ProductCode)
    return ($state -eq 5 -or $state -eq 4 -or $state -eq 3 -or $state -eq 1)
}

function Test-DirectoryContainsExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $exe = Get-ChildItem -Path $Path -Filter '*.exe' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    return [bool]$exe
}

function Test-ShortcutTargetExists {
    $shortcutCandidates = Get-ChildItem -Path 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\eParakst*3.0\*.lnk' `
                                        -File `
                                        -ErrorAction SilentlyContinue
    if (-not $shortcutCandidates) {
        return $false
    }

    try {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($shortcut in $shortcutCandidates) {
            $targetPath = $shell.CreateShortcut($shortcut.FullName).TargetPath
            if ($targetPath -and (Test-Path -LiteralPath $targetPath)) {
                return $true
            }
        }
    } catch {
        # If shortcut target cannot be resolved, treat shortcut-only state as not installed.
    }

    return $false
}

function Test-EParakstitajsInstalled {
    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $entries = Get-ItemProperty -Path $uninstallPaths -ErrorAction SilentlyContinue |
        Where-Object {
            $displayName = Get-SafeStringPropertyValue -Object $_ -PropertyName 'DisplayName'
            $displayName -and ($displayName -match '^eParakst') -and ($displayName -match '3\.0')
        }

    foreach ($entry in $entries) {
        $productCode = Get-ProductCodeFromEntry -Entry $entry
        if ($productCode -and (Test-MsiProductInstalled -ProductCode $productCode)) {
            return $true
        }

        $installLocation = Get-SafeStringPropertyValue -Object $entry -PropertyName 'InstallLocation'
        if ($installLocation -and (Test-DirectoryContainsExecutable -Path $installLocation)) {
            return $true
        }
    }

    return (Test-ShortcutTargetExists)
}

if (Test-EParakstitajsInstalled) {
    Write-Host 'eParakstitajs 3.0 is installed.'
    exit 0
}

Write-Host 'eParakstitajs 3.0 not detected.'
exit 1
