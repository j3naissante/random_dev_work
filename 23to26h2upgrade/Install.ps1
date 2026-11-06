$ErrorActionPreference = 'Stop'

# Paths
$root  = 'C:\ProgramData\Win11-26H2-Upgrade'
$log   = Join-Path $root 'Upgrade.log'
$state = Join-Path $root 'state.json'

New-Item -ItemType Directory -Path $root -Force | Out-Null

# Logging
function Log($s) {
    "$(Get-Date -Format o) $s" |
        Out-File $log -Append -Encoding utf8

    Write-Output $s
}

# Save upgrade state
function Save-State($s, $code) {
    @{
        Status   = $s
        Code     = $code
        Time     = (Get-Date).ToString('o')
        BootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('o')
    } |
        ConvertTo-Json |
        Set-Content $state -Encoding UTF8
}

# Run Windows Setup and convert exit code
function Run-Setup([string[]]$a) {
    $p = Start-Process `
        -FilePath $setup `
        -ArgumentList $a `
        -PassThru `
        -Wait

    $ExitCode = [BitConverter]::ToUInt32(
        [BitConverter]::GetBytes([int]$p.ExitCode), 0
    )

    return $ExitCode
}

try {
    # Check operating system
    $os = Get-CimInstance Win32_OperatingSystem
    $build = [int]$os.BuildNumber

    $display = (
        Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    ).DisplayVersion

    if ($display -eq '26H2') {
        Log '26H2 already installed'
        exit 0
    }

    if ($build -ne 22631 -or $display -ne '23H2') {
        throw "Unexpected OS: $display build $build"
    }

    # Architecture check
    if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        throw 'This package is for x64 only'
    }

    # Installation media
    $setup = Join-Path $PSScriptRoot 'Media\setup.exe'

    if (-not (Test-Path $setup)) {
        throw 'Missing Media\setup.exe'
    }

    # Free disk space check
    if ((Get-PSDrive C).Free -lt 35GB) {
        throw 'Less than 35 GB free on C:'
    }

    # Check previous upgrade state
    if (Test-Path $state) {
        $prior = Get-Content $state -Raw | ConvertFrom-Json

        if (
            $prior.Status -eq 'Staged' -and
            $prior.BootTime -eq $os.LastBootUpTime.ToString('o')
        ) {
            Log 'Previously staged, awaiting restart'
            exit 0
        }
    }

    # Compatibility scan
    Log 'Running compatibility scan'

    $scan = Run-Setup @(
        '/Auto'
        'Upgrade'
        '/Quiet'
        '/EULA'
        'Accept'
        '/Compat'
        'ScanOnly'
        '/DynamicUpdate'
        'Disable'
    )

    Log ('Compatibility exit: 0x{0:X8}' -f $scan)

    $ScanHex = '0x{0:X8}' -f $scan
Log "Compatibility exit: $ScanHex"

if ($ScanHex -ne '0xC1900210') {
    Save-State 'CompatibilityFailed' $ScanHex
    exit 1
}

Log 'Compatibility scan PASSED. Proceeding with upgrade.'

    # Start Windows upgrade
    Log 'Running upgrade online phase; Setup first restart suppressed'

    $rc = Run-Setup @(
        '/Auto'
        'Upgrade'
        '/Quiet'
        '/EULA'
        'Accept'
        '/NoReboot'
        '/DynamicUpdate'
        'Disable'
        '/CopyLogs'
        "`"$root`""
    )

    Log ('Setup exit: 0x{0:X8}' -f $rc)

    if ($rc -ne 0) {
        Save-State 'SetupFailed' ('0x{0:X8}' -f $rc)
        exit 1
    }

    # Provisional staging state
    Save-State 'Staged' '0x00000000'

    Log 'Online phase returned success.'
    Log 'Pending independent verification and controlled restart.'

    exit 0
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Save-State 'Failed' $_.Exception.Message
    exit 1
}
