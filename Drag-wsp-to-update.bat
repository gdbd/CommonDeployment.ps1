echo off
cls

"%SYSTEMROOT%\system32\windowspowershell\v1.0\powershell.exe" -Command Start-Process "$PSHOME\powershell.exe" -Verb RunAs -ArgumentList "'-NoExit -ExecutionPolicy Bypass %~dp0\CommonDeployment.ps1 -Update -Solution %1 -RestartTimer'"
