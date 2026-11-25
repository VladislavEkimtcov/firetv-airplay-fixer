# Installs the AirPlay sweeper as a Windows Scheduled Task running as SYSTEM.
# Run from an elevated Administrator PowerShell prompt:
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Tv <tv-ip>:5555
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Undo
param(
    [switch]$Undo,
    [string]$Tv
)
$ErrorActionPreference = 'Stop'
$Root = Join-Path $env:ProgramData 'FireTvAirPlayFixer'
$Task = 'Fire TV AirPlay Fixer'

if (Get-ScheduledTask -TaskName $Task -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $Task -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $Task -Confirm:$false
}

Get-Process adb -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$Root*" } | Stop-Process -Force

if ($Undo) {
    Write-Output "Successfully removed scheduled task '$Task'"
    return
}

if (-not $Tv) {
    throw 'Please specify your TV address: -Tv <tv-ip>:5555'
}
if ($Tv -notmatch ':\d+$') {
    $Tv = "$Tv`:5555"
}

New-Item -ItemType Directory -Force -Path $Root | Out-Null
$adb = Join-Path $Root 'platform-tools\adb.exe'

if (-not (Test-Path $adb)) {
    Write-Output "Downloading Android platform-tools from Google..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $zip = Join-Path $env:TEMP 'platform-tools-latest-windows.zip'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $Root -Force
    Remove-Item $zip
}

Copy-Item -Force (Join-Path $PSScriptRoot 'sweep.ps1') (Join-Path $Root 'sweep.ps1')

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Root\sweep.ps1`" -Tv $Tv"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $Task -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
Start-ScheduledTask -TaskName $Task
Start-Sleep -Seconds 3

Write-Output "Installed and started '$Task'."
Write-Output "Log file: $(Join-Path $Root 'firetv-airplay-fixer.log')"
