# POCKETS 2: tools/perfprobe.tscn --pockets in a window that is minimized and never activated
# (the same WMI trick as review.ps1 and mirrorshot.ps1), so it cannot take focus while Zach is
# working. perfprobe needs a REAL window -- a headless run renders nothing and its frame times are
# a lie -- but it does not need to be in front, and a minimized window still renders.
# The log is in .godot\pocketperf.log.
param([string]$Extra = "")

. "$PSScriptRoot\godot_path.ps1"
$p = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$log = Join-Path $p ".godot\pocketperf.log"
$a = @("--path", "`"$p`"", "--log-file", "`"$log`"", "--resolution", "1920x1080",
	"res://tools/perfprobe.tscn", "--", "--no-steam", "--pockets")
if ($Extra) { $a += "`"$Extra`"" }
$startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]7 }
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
	CommandLine = "`"$GodotGui`" " + ($a -join " "); CurrentDirectory = $p; ProcessStartupInformation = $startup }
if ($r.ReturnValue -ne 0) { Write-Error "Couldn't start Godot (WMI code $($r.ReturnValue))."; exit 1 }
Write-Host "pocketperf pid $($r.ProcessId), log $log"
Wait-Process -Id $r.ProcessId -Timeout 1800
Write-Host "done"
