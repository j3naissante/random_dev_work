[CmdletBinding()]
param(
    [string]$OutputRoot = "$PSScriptRoot\WingetPackages",
    [string]$ToolRoot   = "$PSScriptRoot\Tools"
)

$ErrorActionPreference = "Stop"

function New-SafeFolderName {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    foreach ($char in [IO.Path]::GetInvalidFileNameChars()) {
        $Name = $Name.Replace($char, "_")
    }

    $Name = $Name -replace '\s+', '_'

    return $Name
}

function Get-SoftwareShortName {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId
    )

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
    param(
        [Parameter(Mandatory)]
        [string]$ToolRoot
    )

    Write-Host ""
    Write-Host "Checking for IntuneWinAppUtil.exe..."

    $searchRoots = @()

    if ($PSScriptRoot) {
        $searchRoots += $PSScriptRoot
    }

    if ($ToolRoot) {
        $searchRoots += $ToolRoot
    }

    $existingTool = Get-ChildItem `
        -Path $searchRoots `
        -Filter "IntuneWinAppUtil.exe" `
        -Recurse `
        -File `
        -ErrorAction SilentlyContinue |
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
        Invoke-WebRequest `
            -Uri $downloadUrl `
            -OutFile $toolPath `
            -UseBasicParsing
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

function Get-WingetPackageMetadata {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId
    )

    $metadata = [ordered]@{
        Name        = $PackageId
        Publisher   = "Unknown"
        Version     = ""
        Description = "Application installed using WinGet package $PackageId."
        Homepage    = ""
    }

    Write-Host ""
    Write-Host "Reading package metadata..."

    try {
        $showOutput = @(
            & winget.exe show `
                --id "$PackageId" `
                --exact `
                --source winget `
                --accept-source-agreements `
                --disable-interactivity 2>&1
        )

        if ($LASTEXITCODE -ne 0) {
            Write-Host "Could not read package metadata. Default values will be used." -ForegroundColor Yellow
            return [PSCustomObject]$metadata
        }

        $descriptionLines = [System.Collections.Generic.List[string]]::new()
        $insideDescription = $false

        foreach ($lineObject in $showOutput) {
            $line = [string]$lineObject
            $trimmedLine = $line.Trim()

            if ($trimmedLine -match '^Found\s+(.+?)\s+\[') {
                $metadata.Name = $matches[1].Trim()
                continue
            }

            if ($trimmedLine -match '^Publisher:\s*(.+)$') {
                $metadata.Publisher = $matches[1].Trim()
                $insideDescription = $false
                continue
            }

            if ($trimmedLine -match '^Version:\s*(.+)$') {
                $metadata.Version = $matches[1].Trim()
                $insideDescription = $false
                continue
            }

            if ($trimmedLine -match '^Homepage:\s*(.+)$') {
                $metadata.Homepage = $matches[1].Trim()
                $insideDescription = $false
                continue
            }

            if ($trimmedLine -match '^Description:\s*(.*)$') {
                $insideDescription = $true

                if (-not [string]::IsNullOrWhiteSpace($matches[1])) {
                    $descriptionLines.Add($matches[1].Trim())
                }

                continue
            }

            if ($insideDescription) {
                if (
                    $trimmedLine -match '^[A-Za-z][A-Za-z ]+:\s*' -or
                    $trimmedLine -match '^Installer:' -or
                    $trimmedLine -match '^Tags:' -or
                    $trimmedLine -match '^License:'
                ) {
                    $insideDescription = $false
                    continue
                }

                if (-not [string]::IsNullOrWhiteSpace($trimmedLine)) {
                    $descriptionLines.Add($trimmedLine)
                }
            }
        }

        if ($descriptionLines.Count -gt 0) {
            $metadata.Description = $descriptionLines -join " "
        }
    }
    catch {
        Write-Host "Could not parse package metadata. Default values will be used." -ForegroundColor Yellow
        Write-Host $_.Exception.Message
    }

    return [PSCustomObject]$metadata
}

function New-InstallScript {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId
    )

@"
# Auto-generated winget install script
# Winget ID: $PackageId

`$ErrorActionPreference = "Stop"
`$PackageId = "$PackageId"

function Get-WingetPath {
    `$command = Get-Command winget.exe -ErrorAction SilentlyContinue

    if (`$command) {
        return `$command.Source
    }

    `$windowsAppsPath = "C:\Program Files\WindowsApps"

    if (Test-Path `$windowsAppsPath) {
        `$winget = Get-ChildItem ``
            -Path `$windowsAppsPath ``
            -Filter "winget.exe" ``
            -Recurse ``
            -File ``
            -ErrorAction SilentlyContinue |
            Where-Object {
                `$_.FullName -like "*Microsoft.DesktopAppInstaller*"
            } |
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

    Invoke-WebRequest ``
        -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" ``
        -OutFile `$vcLibs ``
        -UseBasicParsing

    Invoke-WebRequest ``
        -Uri "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.7/Microsoft.UI.Xaml.2.8.x64.appx" ``
        -OutFile `$uiXaml ``
        -UseBasicParsing

    Invoke-WebRequest ``
        -Uri "https://aka.ms/getwinget" ``
        -OutFile `$appInstaller ``
        -UseBasicParsing

    Write-Host "Installing dependencies..."

    try {
        Add-AppxPackage -Path `$vcLibs -ErrorAction SilentlyContinue
    }
    catch {
    }

    try {
        Add-AppxPackage -Path `$uiXaml -ErrorAction SilentlyContinue
    }
    catch {
    }

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

    Add-AppxProvisionedPackage ``
        -Online ``
        -PackagePath `$appInstaller ``
        -DependencyPackagePath `$dependencyPackages ``
        -SkipLicense ``
        -ErrorAction Stop |
        Out-Null

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
    Write-Error "winget.exe is still not available after the App Installer install attempt."
    exit 1
}

Write-Host "Using winget:"
Write-Host `$wingetPath

Write-Host "Installing `$PackageId using machine scope..."

`$installArguments = @(
    "install"
    "--id", "`$PackageId"
    "--exact"
    "--source", "winget"
    "--scope", "machine"
    "--silent"
    "--accept-package-agreements"
    "--accept-source-agreements"
    "--disable-interactivity"
)

& `$wingetPath @installArguments

`$installExitCode = `$LASTEXITCODE

Write-Host "winget install exit code: `$installExitCode"

Write-Host "Verifying installation with winget list..."

Start-Sleep -Seconds 5

`$listResult = @(
    & `$wingetPath list --id "`$PackageId" --exact --accept-source-agreements --disable-interactivity 2>`$null
)

`$listExitCode = `$LASTEXITCODE

if (
    `$listExitCode -eq 0 -and
    (`$listResult -match [regex]::Escape(`$PackageId))
) {
    Write-Host "Installation verified successfully."
    exit 0
}

if (`$installExitCode -eq 0) {
    Write-Error "winget reported success, but verification failed. The package was not detected by winget list."
    exit 1
}

Write-Error "Installation failed with winget exit code `$installExitCode."
exit `$installExitCode
"@
}

function New-UninstallScript {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId
    )

@"
# Auto-generated winget uninstall script
# Winget ID: $PackageId

`$ErrorActionPreference = "Stop"
`$PackageId = "$PackageId"

function Get-WingetPath {
    `$command = Get-Command winget.exe -ErrorAction SilentlyContinue

    if (`$command) {
        return `$command.Source
    }

    `$windowsAppsPath = "C:\Program Files\WindowsApps"

    if (Test-Path `$windowsAppsPath) {
        `$winget = Get-ChildItem `
            -Path `$windowsAppsPath `
            -Filter "winget.exe" `
            -Recurse `
            -File `
            -ErrorAction SilentlyContinue |
            Where-Object {
                `$_.FullName -like "*Microsoft.DesktopAppInstaller*"
            } |
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

& `$wingetPath uninstall `
    --id "`$PackageId" `
    --exact `
    --source winget `
    --silent `
    --accept-source-agreements `
    --disable-interactivity

`$uninstallExitCode = `$LASTEXITCODE

Write-Host "winget uninstall exit code: `$uninstallExitCode"

Write-Host "Verifying uninstall with winget list..."

Start-Sleep -Seconds 5

`$listResult = @(
    & `$wingetPath list `
        --id "`$PackageId" `
        --exact `
        --accept-source-agreements `
        --disable-interactivity 2>`$null
)

if (`$listResult -notmatch [regex]::Escape(`$PackageId)) {
    Write-Host "Uninstall verified successfully."
    exit 0
}

if (`$uninstallExitCode -eq 0) {
    Write-Error "winget reported uninstall success, but the package is still detected by winget list."
    exit 1
}

Write-Error "Uninstall failed with winget exit code `$uninstallExitCode."
exit `$uninstallExitCode
"@
}

function New-DetectionScript {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId
    )

@"
# Auto-generated Intune detection script
# Winget ID: $PackageId

`$PackageId = "$PackageId"

function Get-WingetPath {
    `$command = Get-Command winget.exe -ErrorAction SilentlyContinue

    if (`$command) {
        return `$command.Source
    }

    `$windowsAppsPath = "C:\Program Files\WindowsApps"

    if (Test-Path `$windowsAppsPath) {
        `$winget = Get-ChildItem `
            -Path `$windowsAppsPath `
            -Filter "winget.exe" `
            -Recurse `
            -File `
            -ErrorAction SilentlyContinue |
            Where-Object {
                `$_.FullName -like "*Microsoft.DesktopAppInstaller*"
            } |
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

`$result = @(
    & `$wingetPath list `
        --id "`$PackageId" `
        --exact `
        --accept-source-agreements `
        --disable-interactivity 2>`$null
)

if (
    `$LASTEXITCODE -eq 0 -and
    (`$result -match [regex]::Escape(`$PackageId))
) {
    Write-Output "Installed"
    exit 0
}

exit 1
"@
}

function New-UpdateScript {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
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
    `$command = Get-Command winget.exe -ErrorAction SilentlyContinue

    if (`$command) {
        return `$command.Source
    }

    `$windowsAppsPath = "C:\Program Files\WindowsApps"

    if (Test-Path `$windowsAppsPath) {
        `$winget = Get-ChildItem `
            -Path `$windowsAppsPath `
            -Filter "winget.exe" `
            -Recurse `
            -File `
            -ErrorAction SilentlyContinue |
            Where-Object {
                `$_.FullName -like "*Microsoft.DesktopAppInstaller*"
            } |
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
    Write-Host ""
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

Write-Host "Checking for an available update for `$PackageId..."

& `$wingetPath upgrade `
    --id "`$PackageId" `
    --exact `
    --source winget `
    --accept-source-agreements `
    --disable-interactivity

Write-Host ""
Write-Host "Upgrading `$PackageId using machine scope..."

& `$wingetPath upgrade `
    --id "`$PackageId" `
    --exact `
    --source winget `
    --scope machine `
    --silent `
    --accept-package-agreements `
    --accept-source-agreements `
    --disable-interactivity

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

function New-IntuneAppConfig {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string]$Publisher,

        [Parameter(Mandatory)]
        [string]$Description,

        [string]$PackageVersion,

        [string]$Homepage,

        [Parameter(Mandatory)]
        [string]$InstallFileName,

        [Parameter(Mandatory)]
        [string]$UninstallFileName,

        [Parameter(Mandatory)]
        [string]$DetectionFileName,

        [Parameter(Mandatory)]
        [string]$UpdateFileName,

        [Parameter(Mandatory)]
        [string]$IntuneWinFileName
    )

    $config = [ordered]@{
        schemaVersion   = 1
        appType         = "Winget"
        displayName     = $DisplayName
        description     = $Description
        publisher       = $Publisher
        packageVersion  = $PackageVersion
        informationUrl  = $Homepage
        wingetPackageId = $PackageId
        intuneWinFile   = $IntuneWinFileName

        commands = [ordered]@{
            install = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\$InstallFileName"
            uninstall = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\$UninstallFileName"
            update = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\$UpdateFileName -Upgrade"
        }

        installExperience = [ordered]@{
            runAsAccount          = "system"
            deviceRestartBehavior = "suppress"
        }

        requirements = [ordered]@{
            architecture                   = "x64"
            minimumSupportedWindowsRelease = "W11_22H2"
            minimumFreeDiskSpaceInMB       = $null
            minimumMemoryInMB              = $null
            minimumNumberOfProcessors      = $null
            minimumCpuSpeedInMHz           = $null
        }

        detectionRule = [ordered]@{
            type                  = "script"
            scriptFile            = $DetectionFileName
            runAs32Bit            = $false
            enforceSignatureCheck = $false
        }

        returnCodes = @(
            [ordered]@{
                returnCode = 0
                type       = "success"
            }
            [ordered]@{
                returnCode = 1707
                type       = "success"
            }
            [ordered]@{
                returnCode = 3010
                type       = "softReboot"
            }
            [ordered]@{
                returnCode = 1641
                type       = "hardReboot"
            }
            [ordered]@{
                returnCode = 1618
                type       = "retry"
            }
        )

        assignments = [ordered]@{
            intent  = ""
            groupId = ""
        }

        metadata = [ordered]@{
            generatedBy = "Winget IntuneWin generator"
            generatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
        }
    }

    return $config | ConvertTo-Json -Depth 10
}

function New-Readme {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,

        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string]$Publisher,

        [string]$PackageVersion,

        [Parameter(Mandatory)]
        [string]$InstallFileName,

        [Parameter(Mandatory)]
        [string]$UninstallFileName,

        [Parameter(Mandatory)]
        [string]$DetectionFileName,

        [Parameter(Mandatory)]
        [string]$UpdateFileName,

        [Parameter(Mandatory)]
        [string]$IntuneWinFileName,

        [Parameter(Mandatory)]
        [string]$ConfigFileName
    )

@"
Winget IntuneWin package
========================

Application:
$DisplayName

Publisher:
$Publisher

Version:
$PackageVersion

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

    This file is created after IntuneWin packaging, so it is not
    included inside the .intunewin file.

$ConfigFileName
    Contains the generated Intune Win32 application settings in JSON.

    This file is created after IntuneWin packaging, so it is not
    included inside the .intunewin file.

README.txt
    This file.

Generated IntuneWin
-------------------

$IntuneWinFileName

Intune setup
------------

App type:

Winget

Upload:

$IntuneWinFileName

Install command:

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\$InstallFileName

Uninstall command:

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\$UninstallFileName

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

Requirements
------------

Operating system architecture:

64-bit

Minimum operating system:

Windows 10 1607

Return codes
------------

0       Success
1707    Success
3010    Soft reboot
1641    Hard reboot
1618    Retry

Update command
--------------

The update script is separate from the IntuneWin package.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\$UpdateFileName -Upgrade

Important notes
---------------

The install and update commands use:

--source winget
--scope machine

This is important for Intune and SYSTEM installations.

Winget is commonly located here when running as SYSTEM:

C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe

The generated scripts check that location automatically.

If winget is missing, the install script attempts to install
App Installer and winget.

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
    Write-Host "ERROR: winget.exe is not available on this admin machine." -ForegroundColor Red
    Write-Host "Install or update App Installer on this machine first."
    exit 1
}

do {
    $searchTerm = Read-Host "What do you want to search for in winget?"
}
while ([string]::IsNullOrWhiteSpace($searchTerm))

Write-Host ""
Write-Host "Searching winget for: $searchTerm"
Write-Host ""

& winget.exe search `
    --query "$searchTerm" `
    --source winget `
    --accept-source-agreements `
    --disable-interactivity

Write-Host ""
Write-Host "Copy the exact ID from above."
Write-Host "Example: Brave.Brave"
Write-Host ""

do {
    $packageId = Read-Host "Enter Winget ID"
}
while ([string]::IsNullOrWhiteSpace($packageId))

Write-Host ""
Write-Host "Checking selected package..."
Write-Host ""

& winget.exe show `
    --id "$packageId" `
    --exact `
    --source winget `
    --accept-source-agreements `
    --disable-interactivity

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Could not verify this Winget ID. Check the spelling and try again." -ForegroundColor Red
    exit 1
}

$packageMetadata = Get-WingetPackageMetadata -PackageId $packageId

$displayName    = $packageMetadata.Name
$publisher      = $packageMetadata.Publisher
$packageVersion = $packageMetadata.Version
$description    = $packageMetadata.Description
$homepage       = $packageMetadata.Homepage

Write-Host ""
Write-Host "Detected package information:"
Write-Host "Name:        $displayName"
Write-Host "Publisher:   $publisher"
Write-Host "Version:     $packageVersion"
Write-Host "Homepage:    $homepage"

$folderName        = New-SafeFolderName -Name $packageId
$softwareShortName = Get-SoftwareShortName -PackageId $packageId
$packageFolder     = Join-Path $OutputRoot $folderName

if (-not (Test-Path $packageFolder)) {
    New-Item -Path $packageFolder -ItemType Directory -Force | Out-Null
}

$installFileName   = "${softwareShortName}_install.ps1"
$uninstallFileName = "${softwareShortName}_uninstall.ps1"
$detectionFileName = "${softwareShortName}_detection.ps1"
$updateFileName    = "${softwareShortName}_update.ps1"
$intuneWinFileName = "${softwareShortName}_install.intunewin"
$configFileName    = "app-config.json"
$readmeFileName    = "README.txt"

$installPath   = Join-Path $packageFolder $installFileName
$uninstallPath = Join-Path $packageFolder $uninstallFileName
$detectionPath = Join-Path $packageFolder $detectionFileName
$updatePath    = Join-Path $packageFolder $updateFileName
$configPath    = Join-Path $packageFolder $configFileName
$readmePath    = Join-Path $packageFolder $readmeFileName

# Remove old generated files.
Get-ChildItem `
    -Path $packageFolder `
    -Filter "*.intunewin" `
    -File `
    -ErrorAction SilentlyContinue |
    Remove-Item -Force

foreach ($oldFile in @($updatePath, $configPath)) {
    if (Test-Path $oldFile) {
        Remove-Item -Path $oldFile -Force
    }
}

New-InstallScript -PackageId $packageId |
    Set-Content -Path $installPath -Encoding UTF8

New-UninstallScript -PackageId $packageId |
    Set-Content -Path $uninstallPath -Encoding UTF8

New-DetectionScript -PackageId $packageId |
    Set-Content -Path $detectionPath -Encoding UTF8

# README is included inside the IntuneWin file.
New-Readme `
    -PackageId $packageId `
    -DisplayName $displayName `
    -Publisher $publisher `
    -PackageVersion $packageVersion `
    -InstallFileName $installFileName `
    -UninstallFileName $uninstallFileName `
    -DetectionFileName $detectionFileName `
    -UpdateFileName $updateFileName `
    -IntuneWinFileName $intuneWinFileName `
    -ConfigFileName $configFileName |
    Set-Content -Path $readmePath -Encoding UTF8

Write-Host ""
Write-Host "Created package folder:"
Write-Host $packageFolder

Write-Host ""
Write-Host "Created IntuneWin source files:"
Write-Host $installFileName
Write-Host $uninstallFileName
Write-Host $detectionFileName
Write-Host $readmeFileName

$intuneWinTool = Get-IntuneWinAppUtil -ToolRoot $ToolRoot

Write-Host ""
Write-Host "Creating .intunewin inside package folder..."
Write-Host ""

& $intuneWinTool `
    -c "$packageFolder" `
    -s "$installFileName" `
    -o "$packageFolder" `
    -q

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: IntuneWinAppUtil.exe failed with exit code $LASTEXITCODE." -ForegroundColor Red
    exit $LASTEXITCODE
}

$createdIntuneWin = Get-ChildItem `
    -Path $packageFolder `
    -Filter "*.intunewin" `
    -File `
    -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $createdIntuneWin) {
    Write-Host ""
    Write-Host "ERROR: Packaging completed, but no .intunewin file was found." -ForegroundColor Red
    exit 1
}

if ($createdIntuneWin.Name -ne $intuneWinFileName) {
    $targetIntuneWinPath = Join-Path $packageFolder $intuneWinFileName

    if (Test-Path $targetIntuneWinPath) {
        Remove-Item -Path $targetIntuneWinPath -Force
    }

    Rename-Item `
        -Path $createdIntuneWin.FullName `
        -NewName $intuneWinFileName

    $createdIntuneWin = Get-Item $targetIntuneWinPath
}

# Create update script after packaging so it is not inside the IntuneWin.
New-UpdateScript `
    -PackageId $packageId `
    -UpdateFileName $updateFileName |
    Set-Content -Path $updatePath -Encoding UTF8

# Create JSON after packaging so it is not inside the IntuneWin.
New-IntuneAppConfig `
    -PackageId $packageId `
    -DisplayName $displayName `
    -Publisher $publisher `
    -Description $description `
    -PackageVersion $packageVersion `
    -Homepage $homepage `
    -InstallFileName $installFileName `
    -UninstallFileName $uninstallFileName `
    -DetectionFileName $detectionFileName `
    -UpdateFileName $updateFileName `
    -IntuneWinFileName $intuneWinFileName |
    Set-Content -Path $configPath -Encoding UTF8

Write-Host ""
Write-Host "Done." -ForegroundColor Green

Write-Host ""
Write-Host "Package folder:"
Write-Host $packageFolder

Write-Host ""
Write-Host "Created IntuneWin file:"
Write-Host $createdIntuneWin.FullName

Write-Host ""
Write-Host "Created update script outside IntuneWin:"
Write-Host $updatePath

Write-Host ""
Write-Host "Created Intune configuration JSON outside IntuneWin:"
Write-Host $configPath

Write-Host ""
Write-Host "Install command:"
Write-Host "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\$installFileName"

Write-Host ""
Write-Host "Uninstall command:"
Write-Host "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\$uninstallFileName"

Write-Host ""
Write-Host "Update command:"
Write-Host "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\$updateFileName -Upgrade"

Write-Host ""
Write-Host "Detection script:"
Write-Host $detectionFileName

Write-Host ""

Start-Process explorer.exe -ArgumentList "`"$packageFolder`""
