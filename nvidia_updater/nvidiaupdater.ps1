#Built by j3naissante

Write-Output "Launching NVIDIA Game Ready updater..."

$ProcessUrl = "https://www.nvidia.com/Download/processFind.aspx?dtcid=1&osid=57&pfid=930&whql=4%22"

try {
    $response = Invoke-WebRequest -Uri $ProcessUrl -UseBasicParsing -ErrorAction Stop
} catch {
    throw "Failed to load NVIDIA processFind page: $_"
}

$html = $response.Content

#Extracts version numbers from aspx site
$versions = [regex]::Matches($html, "\d+\.\d{2,3}") | ForEach-Object { $_.Value }

if (-not $versions -or $versions.Count -eq 0) {
    throw "No driver versions found on NVIDIA page"
}

#Picks correct version
$Version = $versions[0]

Write-Host "Detected version: $Version"

#Builds download URL
$DownloadUrl = "https://us.download.nvidia.com/Windows/$Version/$Version-desktop-win10-win11-64bit-international-dch-whql.exe"

Write-Output "Download URL: $DownloadUrl"

#Validates URL format
if ($DownloadUrl -notmatch "^https://us\.download\.nvidia\.com/Windows/\d+\.\d+/") {
    throw "Invalid NVIDIA download URL generated"
}

#Downloading
$OutFile = "$env:TEMP\nvidia-driver-$Version.exe"

try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $OutFile -ErrorAction Stop
    Write-Output "Download complete: $OutFile"
} catch {
    throw "Download failed: $_"
}