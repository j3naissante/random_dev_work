[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PackageFolder,

    [switch]$DeviceCode
)

$ErrorActionPreference = "Stop"

# Microsoft Graph PowerShell first-party client.
$TenantId = "organizations"
$ClientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e"

function Install-IntuneWin32AppModule {
    $module = Get-Module `
        -Name IntuneWin32App `
        -ListAvailable |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $module -or $module.Version -lt [version]"1.5.0") {
        Write-Host ""
        Write-Host "Installing or updating IntuneWin32App..."

        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider `
                -Name NuGet `
                -MinimumVersion 2.8.5.201 `
                -Scope CurrentUser `
                -Force |
                Out-Null
        }

        Install-Module `
            -Name IntuneWin32App `
            -MinimumVersion 1.5.0 `
            -Scope CurrentUser `
            -Force `
            -AllowClobber `
            -AcceptLicense
    }

    Import-Module IntuneWin32App -Force
}

function Get-RequiredPropertyValue {
    param(
        [Parameter(Mandatory)]
        [object]$Object,

        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    $property = $Object.PSObject.Properties[$PropertyName]

    if (-not $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        throw "Required JSON property '$PropertyName' is missing or empty."
    }

    return $property.Value
}

function Import-IntunePackageFromJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageFolder,

        [switch]$DeviceCode
    )

    $resolvedFolder = (Resolve-Path -Path $PackageFolder -ErrorAction Stop).Path
    $configPath = Join-Path $resolvedFolder "app-config.json"

    if (-not (Test-Path $configPath -PathType Leaf)) {
        throw "app-config.json was not found in '$resolvedFolder'."
    }

    Write-Host ""
    Write-Host "Reading configuration:"
    Write-Host $configPath

    $config = Get-Content `
        -Path $configPath `
        -Raw `
        -Encoding UTF8 |
        ConvertFrom-Json

    $displayName = Get-RequiredPropertyValue -Object $config -PropertyName "displayName"
    $description = Get-RequiredPropertyValue -Object $config -PropertyName "description"
    $publisher = Get-RequiredPropertyValue -Object $config -PropertyName "publisher"
    $intuneWinFileName = Get-RequiredPropertyValue -Object $config -PropertyName "intuneWinFile"

    if (-not $config.commands) {
        throw "JSON object 'commands' is missing."
    }

    if (-not $config.detectionRule) {
        throw "JSON object 'detectionRule' is missing."
    }

    if (-not $config.requirements) {
        throw "JSON object 'requirements' is missing."
    }

    $installCommand = Get-RequiredPropertyValue `
        -Object $config.commands `
        -PropertyName "install"

    $uninstallCommand = Get-RequiredPropertyValue `
        -Object $config.commands `
        -PropertyName "uninstall"

    $detectionFileName = Get-RequiredPropertyValue `
        -Object $config.detectionRule `
        -PropertyName "scriptFile"

    $intuneWinPath = Join-Path $resolvedFolder $intuneWinFileName
    $detectionPath = Join-Path $resolvedFolder $detectionFileName

    if (-not (Test-Path $intuneWinPath -PathType Leaf)) {
        throw "IntuneWin file was not found: $intuneWinPath"
    }

    if (-not (Test-Path $detectionPath -PathType Leaf)) {
        throw "Detection script was not found: $detectionPath"
    }

    Install-IntuneWin32AppModule

    $connectParameters = @{
        TenantID = $TenantId
        ClientID = $ClientId
        Scopes   = @(
            "DeviceManagementApps.ReadWrite.All",
            "DeviceManagementRBAC.Read.All",
            "offline_access"
        )
    }

    if ($DeviceCode) {
        $connectParameters.DeviceCode = $true
    }

    Write-Host ""
    Write-Host "Opening Microsoft sign-in..."
    Connect-MSIntuneGraph @connectParameters | Out-Null

    $detectionRule = New-IntuneWin32AppDetectionRuleScript `
        -ScriptFile $detectionPath `
        -EnforceSignatureCheck ([bool]$config.detectionRule.enforceSignatureCheck) `
        -RunAs32Bit ([bool]$config.detectionRule.runAs32Bit)

    $architecture = [string]$config.requirements.architecture
    $minimumRelease = [string]$config.requirements.minimumSupportedWindowsRelease

    if ([string]::IsNullOrWhiteSpace($architecture)) {
        $architecture = "x64"
    }

    if ([string]::IsNullOrWhiteSpace($minimumRelease)) {
        $minimumRelease = "W10_1607"
    }

    $requirementParameters = @{
        Architecture                   = $architecture
        MinimumSupportedWindowsRelease = $minimumRelease
    }

    if ($null -ne $config.requirements.minimumFreeDiskSpaceInMB) {
        $requirementParameters.MinimumFreeDiskSpaceInMB = [int]$config.requirements.minimumFreeDiskSpaceInMB
    }

    if ($null -ne $config.requirements.minimumMemoryInMB) {
        $requirementParameters.MinimumMemoryInMB = [int]$config.requirements.minimumMemoryInMB
    }

    if ($null -ne $config.requirements.minimumNumberOfProcessors) {
        $requirementParameters.MinimumNumberOfProcessors = [int]$config.requirements.minimumNumberOfProcessors
    }

    if ($null -ne $config.requirements.minimumCpuSpeedInMHz) {
        $requirementParameters.MinimumCPUSpeedInMHz = [int]$config.requirements.minimumCpuSpeedInMHz
    }

    $requirementRule = New-IntuneWin32AppRequirementRule @requirementParameters

    $returnCodeObjects = @()

    foreach ($returnCode in @($config.returnCodes)) {
        $returnCodeObjects += New-IntuneWin32AppReturnCode `
            -ReturnCode ([int]$returnCode.returnCode) `
            -Type ([string]$returnCode.type)
    }

    $installExperience = "system"
    $restartBehavior = "suppress"

    if ($config.installExperience.runAsAccount) {
        $installExperience = ([string]$config.installExperience.runAsAccount).ToLowerInvariant()
    }

    if ($config.installExperience.deviceRestartBehavior) {
        $restartBehavior = [string]$config.installExperience.deviceRestartBehavior
    }

    $appParameters = @{
        FilePath             = $intuneWinPath
        DisplayName          = $displayName
        Description          = $description
        Publisher            = $publisher
        InstallCommandLine   = $installCommand
        UninstallCommandLine = $uninstallCommand
        InstallExperience    = $installExperience
        RestartBehavior      = $restartBehavior
        DetectionRule        = $detectionRule
        RequirementRule      = $requirementRule
        ReturnCode           = $returnCodeObjects
        ErrorAction          = "Stop"
        Verbose              = $true
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$config.packageVersion)) {
        $appParameters.AppVersion = [string]$config.packageVersion
    }

    if ([string]$config.informationUrl -match '^https?://') {
        $appParameters.InformationURL = [string]$config.informationUrl
    }

    Write-Host ""
    Write-Host "Uploading Win32 application:"
    Write-Host "Name:      $displayName"
    Write-Host "Publisher: $publisher"
    Write-Host "Package:   $intuneWinPath"
    Write-Host ""

    $createdApp = Add-IntuneWin32App @appParameters

    if (-not $createdApp -or -not $createdApp.id) {
        throw "The upload did not return a valid Intune application object."
    }

    Write-Host ""
    Write-Host "Application imported successfully." -ForegroundColor Green
    Write-Host "Name: $($createdApp.displayName)"
    Write-Host "ID:   $($createdApp.id)"

    if ($config.assignment -and ([string]$config.assignment.type).ToLowerInvariant() -ne "none") {
        $assignmentType = ([string]$config.assignment.type).ToLowerInvariant()
        $intent = [string]$config.assignment.intent
        $notification = [string]$config.assignment.notification

        if ([string]::IsNullOrWhiteSpace($intent)) {
            $intent = "available"
        }

        if ([string]::IsNullOrWhiteSpace($notification)) {
            $notification = "showAll"
        }

        switch ($assignmentType) {
            "allusers" {
                Add-IntuneWin32AppAssignmentAllUsers `
                    -ID $createdApp.id `
                    -Intent $intent `
                    -Notification $notification `
                    -Verbose
            }

            "alldevices" {
                Add-IntuneWin32AppAssignmentAllDevices `
                    -ID $createdApp.id `
                    -Intent $intent `
                    -Notification $notification `
                    -Verbose
            }

            "group" {
                if ([string]::IsNullOrWhiteSpace([string]$config.assignment.groupId)) {
                    throw "Assignment type is 'group', but assignment.groupId is empty."
                }

                Add-IntuneWin32AppAssignmentGroup `
                    -Include `
                    -ID $createdApp.id `
                    -GroupID ([string]$config.assignment.groupId) `
                    -Intent $intent `
                    -Notification $notification `
                    -Verbose
            }

            default {
                throw "Unsupported assignment.type '$assignmentType'."
            }
        }

        Write-Host "Assignment created successfully." -ForegroundColor Green
    }
}

Import-IntunePackageFromJson `
    -PackageFolder $PackageFolder `
    -DeviceCode:$DeviceCode