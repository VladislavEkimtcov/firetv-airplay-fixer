# Checks the status of the Fire TV AirPlay Fixer scheduled task and shows recent logs.
$Root = Join-Path $env:ProgramData 'FireTvAirPlayFixer'
$Task = 'Fire TV AirPlay Fixer'

Write-Output "==> Scheduled Task Status:"
Get-ScheduledTask -TaskName $Task -ErrorAction SilentlyContinue | Format-List TaskName, State

$log = Join-Path $Root 'firetv-airplay-fixer.log'
Write-Output "==> Recent Logs ($log):"
if (Test-Path $log) {
    Get-Content $log -Tail 20
} else {
    Write-Output "No log file found at $log"
}
