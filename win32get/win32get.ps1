[CmdletBinding()]
param(
    [string]$OutputRoot = "$PSScriptRoot\WingetPackages",
    [string]$ToolRoot = "$PSScriptRoot\Tools"
)

function New-SafeFolderName {
    param([string]$Name)

    foreach ($char in [IO.Path]::GetInvalidFileNameChars()) {
        $Name = $Name.Replace($char, "_")
    }

    $Name = $Name -replace '\s+', '_'
    return $Name
}

function Get-SoftwareShortName {
    param([string]$PackageId)


    $firstPart = ($PackageId -split '\.')[0]
    $safeName = $firstPart.ToLower()

    foreach ($char in [IO.Path]::GetInvalidFileNameChars()) {
        $safeName = $safeName.Replace($char, "_")
    }

    $safeName = $safeName -replace '\s+', '_'
    $safeName = $safeName -replace '-', '_'

    return $safeName
}

function Get-IntuneWinAppUtil {
    param([string]$ToolRoot)

    Write-Host ""
    Write-Host "Checking for IntuneWinAppUtil.exe..."

    $searchRoots = @()

    if ($PSScriptRoot) {
        $searchRoots += $PSScriptRoot
    }

    if ($ToolRoot) {
        $searchRoots += $ToolRoot
    }

    $existingTool = Get-ChildItem -Path $searchRoots -Filter "IntuneWinAppUtil.exe" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($existingTool) {
        Write-Host "Found: $($existingTool.FullName)"
        return $existingTool.FullName
    }

    if (-not (Test-Path $ToolRoot)) {
        New-Item -Path $ToolRoot -ItemType Directory -Force | Out-Null
    }

    $toolPath = Join-Path $ToolRoot "IntuneWinAppUtil.exe"

    Write-Host "IntuneWinAppUtil.exe not found."
    Write-Host "Downloading from Microsoft GitHub..."

    $downloadUrl = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $toolPath -UseBasicParsing
    }
    catch {
        Write-Host "ERROR: Failed to download IntuneWinAppUtil.exe." -ForegroundColor Red
        Write-Host $_.Exception.Message
        exit 1
    }

    if (-not (Test-Path $toolPath)) {
        Write-Host "ERROR: Download finished but IntuneWinAppUtil.exe was not found." -ForegroundColor Red
        exit 1
    }

    Write-Host "Downloaded: $toolPath"
    return $toolPath
}

function New-InstallScript {
    param([string]$PackageId)

@"
# Auto-generated winget install script
# Winget ID: $PackageId

`$ErrorActionPreference = "Stop"

`$PackageId = "$PackageId"

function Get-WingetPath {
    `$cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (`$cmd) {
        return `$cmd.Source
    }

    `$windowsAppsPath = "C:\Program Files\WindowsApps"

    if (Test-Path `$windowsAppsPath) {
        `$winget = Get-ChildItem -Path `$windowsAppsPath -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { `$_.FullName -like "*Microsoft.DesktopAppInstaller*" } |
            Sort-Object FullName -Descending |
            Select-Object -First 1

        if (`$winget) {
            return `$winget.FullName
        }
    }

    return `$null
}

function Install-WingetBootstrap {
    `$bootstrapRoot = Join-Path `$env:TEMP "WingetBootstrap"

    if (-not (Test-Path `$bootstrapRoot)) {
        New-Item -Path `$bootstrapRoot -ItemType Directory -Force | Out-Null
    }

    `$appInstaller = Join-Path `$bootstrapRoot "Microsoft.DesktopAppInstaller.msixbundle"
    `$vcLibs       = Join-Path `$bootstrapRoot "Microsoft.VCLibs.x64.14.00.Desktop.appx"
    `$uiXaml       = Join-Path `$bootstrapRoot "Microsoft.UI.Xaml.2.8.x64.appx"

    Write-Host "Downloading winget/App Installer..."

    Invoke-WebRequest -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -OutFile `$vcLibs -UseBasicParsing
    Invoke-WebRequest -Uri "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.7/Microsoft.UI.Xaml.2.8.x64.appx" -OutFile `$uiXaml -UseBasicParsing
    Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile `$appInstaller -UseBasicParsing

    Write-Host "Installing dependencies..."

    try {
        Add-AppxPackage -Path `$vcLibs -ErrorAction SilentlyContinue
    }
    catch {}

    try {
        Add-AppxPackage -Path `$uiXaml -ErrorAction SilentlyContinue
    }
    catch {}

    Write-Host "Installing App Installer / winget..."

    try {
        Add-AppxPackage -Path `$appInstaller -ErrorAction Stop
        Write-Host "App Installer installed with Add-AppxPackage."
        return
    }
    catch {
        Write-Host "Add-AppxPackage failed:"
        Write-Host `$_.Exception.Message
        Write-Host "Trying Add-AppxProvisionedPackage..."
    }

    `$dependencyPackages = @()

    if (Test-Path `$vcLibs) {
        `$dependencyPackages += `$vcLibs
    }

    if (Test-Path `$uiXaml) {
        `$dependencyPackages += `$uiXaml
    }

    Add-AppxProvisionedPackage -Online -PackagePath `$appInstaller -DependencyPackagePath `$dependencyPackages -SkipLicense -ErrorAction Stop | Out-Null

    Write-Host "App Installer provisioned successfully."
}

Write-Host "Checking winget..."

`$wingetPath = Get-WingetPath

if (-not `$wingetPath) {
    Write-Host "winget.exe was not found in PATH or WindowsApps."
    Write-Host "Attempting to install winget/App Installer..."

    Install-WingetBootstrap

    Start-Sleep -Seconds 10

    `$wingetPath = Get-WingetPath
}

if (-not `$wingetPath) {
    Write-Error "winget.exe is still not available after App Installer install attempt."
    exit 1
}

Write-Host "Using winget:"
Write-Host `$wingetPath

Write-Host "Installing `$PackageId with winget source and machine scope..."

& `$wingetPath install --id "`$PackageId" --exact --source winget --scope machine --silent --accept-package-agreements --accept-source-agreements --disable-interactivity

`$installExitCode = `$LASTEXITCODE

Write-Host "winget install exit code: `$installExitCode"

Write-Host "Verifying install with winget list..."

Start-Sleep -Seconds 5

`$listResult = & `$wingetPath list --id "`$PackageId" --exact --accept-source-agreements --disable-interactivity 2>`$null
`$listExitCode = `$LASTEXITCODE

if (`$listExitCode -eq 0 -and (`$listResult -match [regex]::Escape(`$PackageId))) {
    Write-Host "Install verified successfully."
    exit 0
}

if (`$installExitCode -eq 0) {
    Write-Error "winget reported success, but verification failed. Package was not detected by winget list."
    exit 1
}

Write-Error "Install failed with winget exit code `$installExitCode."
exit `$installExitCode
"@
}

function New-UninstallScript {
    param([string]$PackageId)

@"
# Auto-generated winget uninstall script
# Winget ID: $PackageId

`$ErrorActionPreference = "Stop"

`$PackageId = "$PackageId"

function Get-WingetPath {
    `$cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (`$cmd) {
        return `$cmd.Source
    }

    `$windowsAppsPath = "C:\Program Files\WindowsApps"

    if (Test-Path `$windowsAppsPath) {
        `$winget = Get-ChildItem -Path `$windowsAppsPath -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { `$_.FullName -like "*Microsoft.DesktopAppInstaller*" } |
            Sort-Object FullName -Descending |
            Select-Object -First 1

        if (`$winget) {
            return `$winget.FullName
        }
    }

    return `$null
}

Write-Host "Checking winget..."

`$wingetPath = Get-WingetPath

if (-not `$wingetPath) {
    Write-Error "winget.exe was not found in PATH or WindowsApps."
    exit 1
}

Write-Host "Using winget:"
Write-Host `$wingetPath

Write-Host "Uninstalling `$PackageId..."

& `$wingetPath uninstall --id "`$PackageId" --exact --source winget --silent --accept-source-agreements --disable-interactivity

`$uninstallExitCode = `$LASTEXITCODE

Write-Host "winget uninstall exit code: `$uninstallExitCode"

Write-Host "Verifying uninstall with winget list..."

Start-Sleep -Seconds 5

`$listResult = & `$wingetPath list --id "`$PackageId" --exact --accept-source-agreements --disable-interactivity 2>`$null
`$listExitCode = `$LASTEXITCODE

if (`$listResult -notmatch [regex]::Escape(`$PackageId)) {
    Write-Host "Uninstall verified successfully."
    exit 0
}

if (`$uninstallExitCode -eq 0) {
    Write-Error "winget reported uninstall success, but package is still detected by winget list."
    exit 1
}

Write-Error "Uninstall failed with winget exit code `$uninstallExitCode."
exit `$uninstallExitCode
"@
}

function New-DetectionScript {
    param([string]$PackageId)

@"
# Auto-generated Intune detection script
# Winget ID: $PackageId

`$PackageId = "$PackageId"

function Get-WingetPath {
    `$cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (`$cmd) {
        return `$cmd.Source
    }

    `$windowsAppsPath = "C:\Program Files\WindowsApps"

    if (Test-Path `$windowsAppsPath) {
        `$winget = Get-ChildItem -Path `$windowsAppsPath -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { `$_.FullName -like "*Microsoft.DesktopAppInstaller*" } |
            Sort-Object FullName -Descending |
            Select-Object -First 1

        if (`$winget) {
            return `$winget.FullName
        }
    }

    return `$null
}

`$wingetPath = Get-WingetPath

if (-not `$wingetPath) {
    exit 1
}

`$result = & `$wingetPath list --id "`$PackageId" --exact --accept-source-agreements --disable-interactivity 2>`$null

if (`$LASTEXITCODE -eq 0 -and (`$result -match [regex]::Escape(`$PackageId))) {
    Write-Output "Installed"
    exit 0
}

exit 1
"@
}

function New-UpdateScript {
    param(
        [string]$PackageId,
        [string]$UpdateFileName
    )

@"
# Auto-generated winget update script
# Winget ID: $PackageId
#
# Usage:
# .\$UpdateFileName -Upgrade

[CmdletBinding()]
param(
    [switch]`$Upgrade
)

`$ErrorActionPreference = "Stop"

`$PackageId = "$PackageId"

function Get-WingetPath {
    `$cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (`$cmd) {
        return `$cmd.Source
    }

    `$windowsAppsPath = "C:\Program Files\WindowsApps"

    if (Test-Path `$windowsAppsPath) {
        `$winget = Get-ChildItem -Path `$windowsAppsPath -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { `$_.FullName -like "*Microsoft.DesktopAppInstaller*" } |
            Sort-Object FullName -Descending |
            Select-Object -First 1

        if (`$winget) {
            return `$winget.FullName
        }
    }

    return `$null
}

if (-not `$Upgrade) {
    Write-Host "No action taken."
    Write-Host "Run this script with -Upgrade to update `$PackageId."
    Write-Host "Example:"
    Write-Host ".\$UpdateFileName -Upgrade"
    exit 0
}

Write-Host "Checking winget..."

`$wingetPath = Get-WingetPath

if (-not `$wingetPath) {
    Write-Error "winget.exe was not found in PATH or WindowsApps."
    exit 1
}

Write-Host "Using winget:"
Write-Host `$wingetPath

Write-Host "Checking available upgrade for `$PackageId..."
& `$wingetPath upgrade --id "`$PackageId" --exact --source winget --accept-source-agreements --disable-interactivity

Write-Host ""
Write-Host "Upgrading `$PackageId with winget source and machine scope..."

& `$wingetPath upgrade --id "`$PackageId" --exact --source winget --scope machine --silent --accept-package-agreements --accept-source-agreements --disable-interactivity

`$upgradeExitCode = `$LASTEXITCODE

Write-Host "winget upgrade exit code: `$upgradeExitCode"

if (`$upgradeExitCode -eq 0) {
    Write-Host "Upgrade completed successfully."
    exit 0
}

Write-Error "Upgrade failed with winget exit code `$upgradeExitCode."
exit `$upgradeExitCode
"@
}

function New-Readme {
    param(
        [string]$PackageId,
        [string]$InstallFileName,
        [string]$UninstallFileName,
        [string]$DetectionFileName,
        [string]$UpdateFileName,
        [string]$IntuneWinFileName
    )

@"
Winget IntuneWin package
========================

Winget ID:
$PackageId

Generated files
---------------

$InstallFileName
    Installs the package silently using winget.

$UninstallFileName
    Uninstalls the package silently using winget.

$DetectionFileName
    Intune custom detection script.

$UpdateFileName
    Updates this specific winget package.
    This file is created after .intunewin packaging, so it is not included inside the .intunewin.

README.txt
    This file.

Generated IntuneWin
-------------------

$IntuneWinFileName

Intune setup
------------

App type:

Windows app (Win32)

Upload:

$IntuneWinFileName

Install command:

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\$InstallFileName

Uninstall command:

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\$UninstallFileName

Update command:

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\$UpdateFileName -Upgrade

Install behavior:

System

Device restart behavior:

No specific action

Detection rule
--------------

Rules format:

Use a custom detection script.

Detection script file:

$DetectionFileName

Run script as 32-bit process:

No

Enforce script signature check:

No

Important notes
---------------

Install and update commands use:

--source winget
--scope machine

This is important for Intune / SYSTEM installs.

Winget is usually here when running under SYSTEM:

C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe

The generated scripts check that location automatically.

If winget is missing, the install script attempts to install App Installer / winget.

Manual detection test:

winget list --id "$PackageId" --exact --accept-source-agreements --disable-interactivity
"@
}

Clear-Host
Write-Host "Winget IntuneWin generator"
Write-Host "--------------------------"

foreach ($folder in @($OutputRoot, $ToolRoot)) {
    if (-not (Test-Path $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }
}

$wingetForGenerator = Get-Command winget.exe -ErrorAction SilentlyContinue

if (-not $wingetForGenerator) {
    Write-Host "ERROR: winget.exe is not available on this admin machine, so search cannot run." -ForegroundColor Red
    Write-Host "Install/update App Installer on this machine first."
    exit 1
}

do {
    $searchTerm = Read-Host "What do you want to search in winget?"
} while ([string]::IsNullOrWhiteSpace($searchTerm))

Write-Host ""
Write-Host "Searching winget for: $searchTerm"
Write-Host ""

& winget.exe search --query "$searchTerm" --source winget --accept-source-agreements --disable-interactivity

Write-Host ""
Write-Host "Copy the exact Id from above."
Write-Host "Example: Brave.Brave"
Write-Host ""

do {
    $packageId = Read-Host "Enter Winget ID"
} while ([string]::IsNullOrWhiteSpace($packageId))

Write-Host ""
Write-Host "Checking selected package..."
Write-Host ""

& winget.exe show --id "$packageId" --exact --source winget --accept-source-agreements --disable-interactivity

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Could not verify this Winget ID. Check spelling and try again." -ForegroundColor Red
    exit 1
}

$folderName = New-SafeFolderName -Name $packageId
$softwareShortName = Get-SoftwareShortName -PackageId $packageId

$packageFolder = Join-Path $OutputRoot $folderName

if (-not (Test-Path $packageFolder)) {
    New-Item -Path $packageFolder -ItemType Directory -Force | Out-Null
}

$installFileName = "${softwareShortName}_install.ps1"
$uninstallFileName = "${softwareShortName}_uninstall.ps1"
$detectionFileName = "${softwareShortName}_detection.ps1"
$updateFileName = "${softwareShortName}_update.ps1"
$intuneWinFileName = "${softwareShortName}_install.intunewin"
$readmeFileName = "README.txt"

$installPath = Join-Path $packageFolder $installFileName
$uninstallPath = Join-Path $packageFolder $uninstallFileName
$detectionPath = Join-Path $packageFolder $detectionFileName
$updatePath = Join-Path $packageFolder $updateFileName
$readmePath = Join-Path $packageFolder $readmeFileName

# Remove old IntuneWin and old update script before packaging.
# Update script must NOT be included inside the .intunewin.
Get-ChildItem -Path $packageFolder -Filter "*.intunewin" -ErrorAction SilentlyContinue |
    Remove-Item -Force

if (Test-Path $updatePath) {
    Remove-Item -Path $updatePath -Force
}

New-InstallScript -PackageId $packageId |
    Set-Content -Path $installPath -Encoding UTF8

New-UninstallScript -PackageId $packageId |
    Set-Content -Path $uninstallPath -Encoding UTF8

New-DetectionScript -PackageId $packageId |
    Set-Content -Path $detectionPath -Encoding UTF8

# README is created before packaging, so it is included in the .intunewin.
# It mentions the update script, even though the update script itself is created after packaging.
New-Readme `
    -PackageId $packageId `
    -InstallFileName $installFileName `
    -UninstallFileName $uninstallFileName `
    -DetectionFileName $detectionFileName `
    -UpdateFileName $updateFileName `
    -IntuneWinFileName $intuneWinFileName |
    Set-Content -Path $readmePath -Encoding UTF8

Write-Host ""
Write-Host "Created package folder:"
Write-Host $packageFolder
Write-Host ""
Write-Host "Created source files:"
Write-Host $installFileName
Write-Host $uninstallFileName
Write-Host $detectionFileName
Write-Host $readmeFileName

$intuneWinTool = Get-IntuneWinAppUtil -ToolRoot $ToolRoot

Write-Host ""
Write-Host "Creating .intunewin inside package folder..."
Write-Host ""

& $intuneWinTool -c "$packageFolder" -s "$installFileName" -o "$packageFolder" -q

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: IntuneWinAppUtil.exe failed with exit code $LASTEXITCODE." -ForegroundColor Red
    exit $LASTEXITCODE
}

$createdIntuneWin = Get-ChildItem -Path $packageFolder -Filter "*.intunewin" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

# Create update script AFTER packaging so it is NOT included in .intunewin.
New-UpdateScript -PackageId $packageId -UpdateFileName $updateFileName |
    Set-Content -Path $updatePath -Encoding UTF8

Write-Host ""
Write-Host "Created update script outside IntuneWin:"
Write-Host $updateFileName

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host ""
Write-Host "Package folder:"
Write-Host $packageFolder

if ($createdIntuneWin) {
    Write-Host ""
    Write-Host "Created IntuneWin file:"
    Write-Host $createdIntuneWin.FullName
}


Write-Host ""
Write-Host "Detection script:"
Write-Host $detectionFileName

Write-Host ""
Write-Host "Install command:"
Write-Host "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\$installFileName"

Write-Host ""
Write-Host "Update command:"
Write-Host "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\$updateFileName -Upgrade"

Write-Host ""

Start-Process explorer.exe $packageFolder