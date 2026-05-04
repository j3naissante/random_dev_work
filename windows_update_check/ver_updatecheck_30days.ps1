# Get Local OS Build
$OSPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$LocalBuild = (Get-ItemProperty $OSPath).CurrentBuild
$LocalUBR   = [int](Get-ItemProperty $OSPath).UBR
$LocalFull  = "$LocalBuild.$LocalUBR"

# Define the 30-Day Window
$DaysAllowed = 30
$CutoffDate = (Get-Date).AddDays(-$DaysAllowed)

Write-Host "Windows Compliance Check"
Write-Host "Local Version: $LocalFull" -ForegroundColor Cyan
Write-Host "Checking for updates released since: $($CutoffDate.ToString('yyyy-MM-dd'))" -ForegroundColor Gray

# Scrape Microsoft Release Info
$URL = "https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information"
try {
    $UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    $WebResponse = Invoke-WebRequest -Uri $URL -UseBasicParsing -UserAgent $UA
    
    #
    # Splitting the HTML by table row ensures we map the correct date to the correct build
    $Rows = $WebResponse.Content -split "<tr"
    $UpdateList = @()

    foreach ($Row in $Rows) {
        # Look for standard YYYY-MM-DD date format inside the row
        $DateMatch = [regex]::Match($Row, "(20\d{2}-\d{2}-\d{2})")
        # Look for the Build Revision (UBR) inside the same row
        $BuildMatch = [regex]::Match($Row, "$LocalBuild\.(\d+)")
        
        if ($DateMatch.Success -and $BuildMatch.Success) {
            $UpdateList += [PSCustomObject]@{
                Date = [datetime]$DateMatch.Groups[1].Value
                UBR  = [int]$BuildMatch.Groups[1].Value
                Full = "$LocalBuild.$($BuildMatch.Groups[1].Value)"
            }
        }
    }

    # Sort the list so newest updates are at the top, and remove duplicates
    $UpdateList = $UpdateList | Sort-Object Date -Descending | Select-Object -Property * -Unique

    if ($UpdateList.Count -gt 0) {
        
        #Filter for updates released in the last 30 days
        $RecentUpdates = $UpdateList | Where-Object { $_.Date -ge $CutoffDate }

        if ($RecentUpdates.Count -gt 0) {
            Write-Host "`nFound $($RecentUpdates.Count) update(s) released in the last $DaysAllowed days:"
            $RecentUpdates | ForEach-Object { Write-Host " - $($_.Date.ToString('yyyy-MM-dd')): $($_.Full)" -ForegroundColor DarkGray }

            # The 'Floor' is the oldest update that falls within our 30-day window
            $MinimumRequiredUBR = ($RecentUpdates | Measure-Object -Minimum UBR).Minimum
            
            Write-Host "`nMinimum required version for compliance: $LocalBuild.$MinimumRequiredUBR" -ForegroundColor White

            if ($LocalUBR -ge $MinimumRequiredUBR) {
                Write-Host "System has been updated to the compliant version. You are within the 30-day patch window." -ForegroundColor Green
            } else {
                Write-Host "System has not been updated for over 30 days. Please update." -ForegroundColor Red
            }
        } 
        else {
            
            $LatestOverall = $UpdateList[0]
            Write-Host "`nNo new updates released by Microsoft in the last $DaysAllowed days." -ForegroundColor Yellow
            Write-Host "Checking against the absolute latest available: $($LatestOverall.Full)"
            
            if ($LocalUBR -ge $LatestOverall.UBR) {
                Write-Host "System is on the latest update." -ForegroundColor Green
            } else {
                Write-Host "System is not up to date. The latest version is $($LatestOverall.Full)." -ForegroundColor Red
            }
        }
    } else {
        Write-Warning "Could not parse update data for Build $LocalBuild from the Microsoft page."
    }
}
catch {
    Write-Error "Failed to reach Microsoft servers: $($_.Exception.Message)"
}