# Runs tools/perfprobe.tscn in a window that renders but never takes focus and is never in the way.
#
# perfprobe needs a REAL window: it measures frame times, and a minimized window does not render, so
# the shot tools' SW_SHOWMINNOACTIVE (7) would give numbers that mean nothing. This uses
# SW_SHOWNOACTIVATE (4): the window is created and drawn, but it is never activated and never steals
# the keyboard, so it cannot interrupt whatever Zach is typing into.
#
# It is NOT moved offscreen. Putting it at --position 6000,6000 looked like the tidy answer and is not:
# the swapchain of a fully offscreen window on this Radeon dies partway through the run ("Vulkan device
# was lost", TDR) and the probe crashes before it prints a single number. That happens on `main` too --
# it is the offscreen window, not the scenario. So the window is left where it lands, visible but
# never focused, and whoever ran it closes it when the numbers are in.
#
#   tools\perfprobe.ps1 -Extra "--pockets --quality=1"
#
# The log lands in .godot\perfprobe.log; the [perf] lines are the numbers.
param([string]$Extra = "", [int]$TimeoutSec = 1800)

. "$PSScriptRoot\godot_path.ps1"
$p = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$log = Join-Path $p ".godot\perfprobe.log"
$a = @("--path", "`"$p`"", "--log-file", "`"$log`"", "--resolution", "1280x720",
	"res://tools/perfprobe.tscn", "--", "--no-steam")
if ($Extra) { $a += $Extra.Split(" ") }
$startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]4 }
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
	CommandLine = "`"$GodotGui`" " + ($a -join " "); CurrentDirectory = $p; ProcessStartupInformation = $startup }
if ($r.ReturnValue -ne 0) { Write-Error "Couldn't start Godot (WMI code $($r.ReturnValue))."; exit 1 }
Write-Host "perfprobe pid $($r.ProcessId), log $log"
Wait-Process -Id $r.ProcessId -Timeout $TimeoutSec
Write-Host "done"
