$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

function Test-EParakstitajsInstalled {
    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $entry = Get-ItemProperty -Path $uninstallPaths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -and ($_.DisplayName -match '^eParakst.*3\.0')
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
