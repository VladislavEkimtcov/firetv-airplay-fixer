# Event-driven clean-up for Fire TV AirPlay bug on Windows.
# Watches TV event log over network ADB; when the player process dies, purges leftover tasks.
param(
    [Parameter(Mandatory = $true)][string]$Tv,
    [string]$Root = (Join-Path $env:ProgramData 'FireTvAirPlayFixer')
)
$ErrorActionPreference = 'Continue'
$Adb = Join-Path $Root 'platform-tools\adb.exe'
$Log = Join-Path $Root 'firetv-airplay-fixer.log'
$Player = 'com.apple.airplay.amazon.airplay'

# Fixed ADB user home to ensure persistent authorization
$env:ANDROID_USER_HOME = Join-Path $Root 'android'
New-Item -ItemType Directory -Force -Path $env:ANDROID_USER_HOME | Out-Null

function Note([string]$msg) {
    Add-Content -Path $Log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
}

function Adb([string[]]$adbArgs, [int]$timeoutMs = 15000) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Adb
    $psi.Arguments = ($adbArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync()
    if (-not $p.WaitForExit($timeoutMs)) {
        try { $p.Kill() } catch {}
        return @{ Code = -1; Out = '' }
    }
    return @{ Code = $p.ExitCode; Out = $out.Result }
}

function Connected {
    if ((Adb @('-s', $Tv, 'get-state')).Out.Trim() -eq 'device') { return $true }
    Adb @('connect', $Tv) | Out-Null
    return ((Adb @('-s', $Tv, 'get-state')).Out.Trim() -eq 'device')
}

function Sweep([string]$why) {
    if ((Adb @('-s', $Tv, 'shell', 'pidof', $Player)).Code -eq 0) { return }
    $res = Adb @('-s', $Tv, 'shell', 'am', 'stack', 'list')
    if ($res.Code -ne 0) { return }
    $regex = [regex]"taskId=([0-9]+): [^ ]*$([regex]::Escape($Player))[^ ]* .* visible=false"
    foreach ($m in $regex.Matches($res.Out)) {
        $id = $m.Groups[1].Value
        $rm = Adb @('-s', $Tv, 'shell', 'am', 'stack', 'remove', $id)
        if ($rm.Code -eq 0) {
            Note "removed dead AirPlay task $id ($why)"
        }
    }
}

Note "sweeper started for $Tv"

while ($true) {
    if (Connected) {
        Sweep "connect"
        # Stream event log lines
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Adb
        $psi.Arguments = "-s $Tv logcat -v brief -b events -T 1"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        while (-not $proc.StandardOutput.EndOfStream) {
            $line = $proc.StandardOutput.ReadLine()
            if ($line -match "am_proc_died.*$Player") {
                Sweep "player died"
            }
        }
        $proc.WaitForExit()
    }
    Start-Sleep -Seconds 10
}
