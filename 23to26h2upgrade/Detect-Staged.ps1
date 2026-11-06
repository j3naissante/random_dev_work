$root='C:\ProgramData\Win11-26H2-Upgrade'; $state=Join-Path $root 'state.json'
$os=Get-CimInstance Win32_OperatingSystem
$version=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion
if($version -eq '26H2' -and [int]$os.BuildNumber -ge 26100){Write-Output '26H2 installed';exit 0}
if(!(Test-Path $state)){exit 1}
try {$s=Get-Content $state -Raw | ConvertFrom-Json} catch {exit 1}
if($s.Status -eq 'Staged' -and $s.Code -eq '0x00000000' -and $s.BootTime -eq $os.LastBootUpTime.ToString('o') -and $version -eq '23H2'){
 Write-Output 'Online Setup returned success, same boot session; pending controlled restart';exit 0
}
exit 1
