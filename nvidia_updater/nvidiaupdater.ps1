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
$ProcessUrl = "https://www.nvidia.com/Download/processFind.aspx?dtcid=1&osid=$osid&pfid=$pfid&whql=1%22"

$response = Invoke-WebRequest -Uri $ProcessUrl -UseBasicParsing -ErrorAction Stop
$html = $response.Content


#Extracts version numbers from aspx site
$versions = [regex]::Matches($html, "\b\d{3}\.\d{2,3}\b") |
            ForEach-Object { $_.Value } |
            Select-Object -Unique

if (-not $versions -or $versions.Count -eq 0) {
    throw "No driver versions found on NVIDIA page (PFID/OS combination may be invalid)"
}

#Picks correct version
$Version = $versions |
    Sort-Object { [version]$_ } -Descending |
    Select-Object -First 1

Write-Output "Detected latest version: $Version"


#Builds download URL
$DownloadUrl = "https://us.download.nvidia.com/Windows/$Version/$Version-desktop-win10-win11-64bit-international-dch-whql.exe"

Write-Output "Download URL: $DownloadUrl"


#Validates URL format
if ($DownloadUrl -notmatch "^https://us\.download\.nvidia\.com/Windows/\d+\.\d+/") {
    throw "Invalid NVIDIA download URL generated"
}


# Downloads driver
$OutFile = "$env:TEMP\nvidia-driver-$Version.exe"

Invoke-WebRequest -Uri $DownloadUrl -OutFile $OutFile -ErrorAction Stop

Write-Output "Download complete: $OutFile"