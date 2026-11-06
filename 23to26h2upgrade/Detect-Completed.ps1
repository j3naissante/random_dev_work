$os=Get-CimInstance Win32_OperatingSystem
$v=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion
if($v -eq '26H2' -and [int]$os.BuildNumber -ge 26300){Write-Output "Windows 11 $v build $($os.BuildNumber)";exit 0}
exit 1
