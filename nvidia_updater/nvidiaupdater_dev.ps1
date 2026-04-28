# Built by j3naissante
# Data from https://github.com/ZenitH-AT/nvidia-data/

Write-Output "Updating Nvidia Driver"


# Detect NVIDIA GPU
$gpu = Get-CimInstance Win32_VideoController |
       Where-Object { $_.Name -match "NVIDIA" } |
       Select-Object -First 1

if (-not $gpu) {
    throw "No NVIDIA GPU detected"
}

Write-Output "Detected GPU: $($gpu.Name)"


# Detect OSID
$os = Get-CimInstance Win32_OperatingSystem

if ($os.Caption -match "Windows 11") {
    $osid = 135
}
elseif ($os.Caption -match "Windows 10") {
    $osid = 57
}
else {
    throw "Unsupported OS: $($os.Caption)"
}

Write-Output "Detected OS: $($os.Caption)"
Write-Output "Using OSID: $osid"


# GPU → PFID mapping
$pfidMap = @{
"GeForce RTX 5090 D"= 1067
"GeForce RTX 5090"= 1066
"GeForce RTX 5080"= 1065
"GeForce RTX 5070 Ti"= 1068
"GeForce RTX 5070"= 1070
"GeForce RTX 5060 Ti"= 1076

"GeForce RTX 4090"= 995
"GeForce RTX 4080 SUPER"= 1041
"GeForce RTX 4080"= 999
"GeForce RTX 4070 Ti SUPER"= 1040
"GeForce RTX 4070 Ti"= 1001
"GeForce RTX 4070 SUPER"= 1039
"GeForce RTX 4070"= 1015
"GeForce RTX 4060 Ti"= 1022
"GeForce RTX 4060"= 1023

"GeForce RTX 3090 Ti"= 985
"GeForce RTX 3090"= 930
"GeForce RTX 3080 Ti"= 964
"GeForce RTX 3080"= 929
"GeForce RTX 3070 Ti"= 965
"GeForce RTX 3070"= 933
"GeForce RTX 3060 Ti"= 934
"GeForce RTX 3060"= 942
"GeForce RTX 3050"= 975

"GeForce RTX 2080 Ti"= 877
"GeForce RTX 2080 SUPER"= 904
"GeForce RTX 2080"= 879
"GeForce RTX 2070 SUPER"= 903
"GeForce RTX 2070"= 880
"GeForce RTX 2060 SUPER"= 902
"GeForce RTX 2060"= 887

"GeForce GTX 1080 Ti"= 845
"GeForce GTX 1080"= 815
"GeForce GTX 1070 Ti"= 859
"GeForce GTX 1070"= 816
}

$pfid = $null

foreach ($key in $pfidMap.Keys) {
    if ($gpu.Name -match $key) {
        $pfid = $pfidMap[$key]
        break
    }
}

if (-not $pfid) {
    throw "No PFID mapping found for GPU: $($gpu.Name)"
}

Write-Output "Using PFID: $pfid"


# Build NVIDIA URL
$ProcessUrl = "https://www.nvidia.com/Download/processFind.aspx?dtcid=1&osid=$osid&pfid=$pfid&whql=1"

$response = Invoke-WebRequest -Uri $ProcessUrl -UseBasicParsing -ErrorAction Stop
$html = $response.Content


# Extracts version numbers from aspx site
$versions = [regex]::Matches($html, "\b\d{3}\.\d{2,3}\b") |
            ForEach-Object { $_.Value } |
            Select-Object -Unique

if (-not $versions -or $versions.Count -eq 0) {
    throw "No driver versions found on NVIDIA page (PFID/OS combination may be invalid)"
}

# Picks correct version
$Version = $versions |
    Sort-Object { [version]$_ } -Descending |
    Select-Object -First 1

Write-Output "Detected latest version: $Version"


# Check currently installed driver version from registry
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}_Display.Driver"
$InstalledVersion = $null

if (Test-Path $RegPath) {
    $InstalledVersion = (Get-ItemProperty -Path $RegPath -Name "DisplayVersion" -ErrorAction SilentlyContinue).DisplayVersion
}

if ($InstalledVersion) {
    Write-Output "Currently installed driver version: $InstalledVersion"

    if ($InstalledVersion -eq $Version) {
        Write-Output "Driver version $Version is already installed. No update required. Exiting."
        exit 0
    }

    Write-Output "Installed version ($InstalledVersion) differs from latest ($Version). Proceeding with update."
}
else {
    Write-Output "No existing NVIDIA driver found in registry. Proceeding with installation."
}


# Builds download URL
$DownloadUrl = "https://us.download.nvidia.com/Windows/$Version/$Version-desktop-win10-win11-64bit-international-dch-whql.exe"

Write-Output "Download URL: $DownloadUrl"


# Validates URL format
if ($DownloadUrl -notmatch "^https://us\.download\.nvidia\.com/Windows/\d+\.\d+/") {
    throw "Invalid NVIDIA download URL generated"
}


# Downloads driver
$OutFile = "$env:TEMP\nvidia-driver-$Version.exe"

Write-Output "Downloading driver to: $OutFile"
Invoke-WebRequest -Uri $DownloadUrl -OutFile $OutFile -ErrorAction Stop
Write-Output "Download complete."


# Silent installation
# -s  = silent
# -noreboot = suppress automatic reboot (Datto RMM manages reboots)
# -noeula   = skip EULA prompt
# -clean    = clean install (removes previous driver components)
Write-Output "Starting silent installation..."

$InstallArgs = "-s -noreboot -noeula -clean"
$InstallProcess = Start-Process -FilePath $OutFile -ArgumentList $InstallArgs -Wait -PassThru

$ExitCode = $InstallProcess.ExitCode

switch ($ExitCode) {
    0       { Write-Output "Driver installed successfully (Exit code: 0)." }
    1       { throw "Installation failed — general error (Exit code: 1)." }
    2       { throw "Installation failed — invalid parameter (Exit code: 2)." }
    14      { Write-Output "Installation complete — reboot required (Exit code: 14)." }
    default { throw "Installation returned unexpected exit code: $ExitCode" }
}


# Cleanup installer
Remove-Item -Path $OutFile -Force -ErrorAction SilentlyContinue
Write-Output "Installer cleaned up."

Write-Output "NVIDIA driver update complete. Version: $Version"