# Current Month
$CurrentMonth = (Get-Date).Month
$CurrentYear = (Get-Date).Year

Write-Output "Checking Windows Update status..."

# Checking for pending updates via WUA API
try {
    $UpdateSession = New-Object -ComObject Microsoft.Update.Session
    $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
    
    $SearchResult = $UpdateSearcher.Search("IsInstalled=0 and IsHidden=0")
    $PendingCount = $SearchResult.Updates.Count
}
catch {
    Write-Warning "Could not access Windows Update API. Please check that you are running it as Administrator."
    $PendingCount = -1
}

# Check the date of the most recent KB
$LatestHotfix = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
$LastUpdateDate = $LatestHotfix.InstalledOn


$IsSameMonth = ($LastUpdateDate.Month -eq $CurrentMonth -and $LastUpdateDate.Year -eq $CurrentYear)
$IsLatest = ($PendingCount -eq 0)


# Summary Result
if ($IsLatest -or $IsSameMonth) {
    Write-Output "`nResult: Up to date $($LatestHotfix.HotfixID) installed on $($LastUpdateDate.ToShortDateString())" 
} else {
    Write-Output "`nResult: Not up to date Latest Hotfix Installed: $($LatestHotfix.HotfixID) on $($LastUpdateDate.ToShortDateString())" 
}