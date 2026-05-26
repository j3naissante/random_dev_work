# Initialize variables explicitly

$secureBoot = $false
$firmwareUpdated = $false
$policyConfigured = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot"

# Check Secure Boot Enabled State
try {
    $sb = Get-ItemProperty `
        -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" `
        -Name UEFISecureBootEnabled `
        -ErrorAction Stop

    $secureBoot = ($sb.UEFISecureBootEnabled -eq 1)
}
catch {
    $secureBoot = $null
}

# Direct Certificate Check 
if ($secureBoot) {
    $dbData = Get-SecureBootUEFI -Name db -ErrorAction SilentlyContinue
    if ($dbData) {
        $dbText = [System.Text.Encoding]::ASCII.GetString($dbData.Bytes)
        if ($dbText -match 'Windows UEFI CA 2023') {
            $firmwareUpdated = $true
        }
    }
}

# Strict State Engine Logic
$ca2023Status = "Unknown"

if ($secureBoot -eq $false -or $secureBoot -eq $null) {
    $ca2023Status = "Secure Boot Disabled"
}
elseif ($firmwareUpdated -eq $true) {

    $ca2023Status = "Installed"
}
elseif (-not $policyConfigured) {
    $ca2023Status = "Not Configured"
}
elseif ($policyConfigured -and -not $firmwareUpdated) {
    $ca2023Status = "In Progress"
}

# Final output
[pscustomobject]@{
    SecureBoot      = $secureBoot
    FirmwareMatched = $firmwareUpdated
    UEFICA2023      = $ca2023Status
}