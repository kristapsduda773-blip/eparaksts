$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

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

function Test-EParakstitajsInstalled {
    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $entry = Get-ItemProperty -Path $uninstallPaths -ErrorAction SilentlyContinue |
        Where-Object {
            $displayName = Get-SafeStringPropertyValue -Object $_ -PropertyName 'DisplayName'
            $displayName -and ($displayName -match '^eParakst') -and ($displayName -match '3\.0')
        } |
        Select-Object -First 1

    if ($entry) {
        return $true
    }

    $shortcutCandidates = Get-ChildItem -Path 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\eParakst*3.0\*.lnk' `
                                        -File `
                                        -ErrorAction SilentlyContinue
    return [bool]$shortcutCandidates
}

if (Test-EParakstitajsInstalled) {
    Write-Host 'eParakstitajs 3.0 is installed.'
    exit 0
}

Write-Host 'eParakstitajs 3.0 not detected.'
exit 1
