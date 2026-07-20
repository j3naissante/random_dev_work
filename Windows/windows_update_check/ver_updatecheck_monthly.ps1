# Get Local OS Build and UBR
$OSPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$LocalBuild = (Get-ItemProperty $OSPath).CurrentBuild
$LocalUBR   = [int](Get-ItemProperty $OSPath).UBR

# Get Current Month and Year for the search
$CurrentMonthName = (Get-Date).ToString("MMMM") # e.g., "May"
$CurrentYear = (Get-Date).Year

Write-Host "Local Version: $LocalBuild.$LocalUBR" -ForegroundColor Cyan
Write-Host "Target Month: $CurrentMonthName $CurrentYear" -ForegroundColor Gray

# Scrape Microsoft Release Info
$URL = "https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information"
try {
    $UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    $WebResponse = Invoke-WebRequest -Uri $URL -UseBasicParsing -UserAgent $UA
    $Content = $WebResponse.Content

    # Logic to find UBRs for the Current Month
    $RegexPattern = "$CurrentMonthName\s+\d{1,2},\s+$CurrentYear.*?$LocalBuild\.(\d+)"
    $Matches = [regex]::Matches($Content, $RegexPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

    if ($Matches.Count -gt 0) {
        # Extract all revision numbers found for this month
        $MonthlyUBRs = foreach ($m in $Matches) { [int]$m.Groups[1].Value }
        
        # The 'First' update of the month is usually the lowest UBR released in that month
        $MinimumRequiredUBR = ($MonthlyUBRs | Measure-Object -Minimum).Minimum
        
        Write-Host "First available update for $CurrentMonthName starts at revision: .$MinimumRequiredUBR" -ForegroundColor White

        # Final Comparison
        if ($LocalUBR -ge $MinimumRequiredUBR) {
            Write-Host "You have installed at least the first $CurrentMonthName update." -ForegroundColor Green
            $Status = "Compliant"
        } else {
            Write-Host "You are still on a previous month's update." -ForegroundColor Red
            $Status = "Out of Date"
        }
    } else {
        
        Write-Host "No updates found for $CurrentMonthName $CurrentYear yet. Checking against last month..." -ForegroundColor Yellow
        
    }
}
catch {
    Write-Error "Could not reach Microsoft servers: $($_.Exception.Message)"
}