# Runs tools/perfprobe.tscn in a real window that is minimized and never activated (the same WMI
# trick as review.ps1 / vatshot.ps1), so honest frame times can be measured without the window ever
# taking focus while Zach is working. perfprobe needs a real window: a --headless run renders
# nothing and its numbers mean nothing.
#
#   tools\perfprobe.ps1 -Extra "--pockets"
#   tools\perfprobe.ps1 -Extra "--pockets --seed=7 --quality=1"
#
# The log (which is where the numbers are) lands in .godot\perfprobe.log.
param([string]$Extra = "", [string]$Resolution = "1280x720", [int]$TimeoutSeconds = 1800)

. "$PSScriptRoot\godot_path.ps1"
$p = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$log = Join-Path $p ".godot\perfprobe.log"
$a = @("--path", "`"$p`"", "--log-file", "`"$log`"", "--resolution", $Resolution,
	"res://tools/perfprobe.tscn", "--", "--no-steam")
if ($Extra) { $a += $Extra.Split(" ") | Where-Object { $_ -ne "" } }
$startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]7 }
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
	CommandLine = "`"$GodotGui`" " + ($a -join " "); CurrentDirectory = $p; ProcessStartupInformation = $startup }
if ($r.ReturnValue -ne 0) { Write-Error "Couldn't start Godot (WMI code $($r.ReturnValue))."; exit 1 }
Write-Host "perfprobe pid $($r.ProcessId), log $log"
Wait-Process -Id $r.ProcessId -Timeout $TimeoutSeconds
Write-Host "done"
