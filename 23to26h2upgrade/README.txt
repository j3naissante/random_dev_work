WINDOWS 11 23H2 -> 26H2
1. Extract OFFICIAL Windows 11 26H2 x64 ISO contents to Media (Media\setup.exe must exist). Match device language and OS edition. Confirm correct image indexes using DISM /Get-WimInfo.
2. Package whole directory with IntuneWinAppUtil.exe -c <folder> -s Install.ps1 -o <output> -q.
3. Install command: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
4. Run as SYSTEM, 64-bit process; device restart behavior: No specific action; timeout 120 minutes or longer based on pilot results.
5. Custom detection script: Detect-Staged.ps1. Note: this reports Installed after Setup exits 0, NOT after 26H2 is actually installed. Treat as STAGED only.
6. For post-reboot completion, deploy Detect-Completed.ps1 separately as an Intune remediation/detection reporting workflow; DO NOT attach it as the app's install detection (would cause retry before reboot).
7. DO NOT assign to broad production groups without pilot tests. Check Setup logs at C:\$WINDOWS.~BT\Sources\Panther and C:\Windows\Panther and state/log under ProgramData.
8. Never call shutdown.exe, Restart-Computer, or Setup /Finalize in this package. /NoReboot only suppresses Setup's first restart. Other management policies can still restart.
9. This is a pilot implementation, not a proven production-ready zero-reboot guarantee. Setup success is provisional, and staged detection does not prove offline upgrade will succeed.
