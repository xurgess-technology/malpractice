# POCKETS 2: tools/perfprobe.tscn against the pocket spaces, in a window that is minimized and
# never activated (the same WMI trick as review.ps1 and mirrorshot.ps1), so it cannot take focus
# while Zach is working. perfprobe needs a REAL window -- a headless run renders nothing and its
# frame times are a lie -- but it does not need to be in front, and a minimized window still
# renders. The log is in .godot\pocketperf.log.
#
#   tools\pocketperf.ps1                  every kind, one session each  (see the warning below)
#   tools\pocketperf.ps1 -Kind chapel     one kind, in a single session
#
# WARNING: with no -Kind this runs perfprobe --pockets, which restarts the session once per kind,
# and the first restart lands straight after the warmup and trips a renderer bug that kills the
# process before it measures anything. That is pre-existing; see docs/FAILING_TESTS.md section 3.
# -Kind uses --pocket=<kind>, which forces the kind before the one and only start_session and works.
param([string]$Kind = "", [string]$Extra = "")

. "$PSScriptRoot\godot_path.ps1"
$p = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$log = Join-Path $p ".godot\pocketperf.log"
$mode = if ($Kind) { "--pocket=$Kind" } else { "--pockets" }
$a = @("--path", "`"$p`"", "--log-file", "`"$log`"", "--resolution", "1920x1080",
	"res://tools/perfprobe.tscn", "--", "--no-steam", $mode)
if ($Extra) { $a += "`"$Extra`"" }
$startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]7 }
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
	CommandLine = "`"$GodotGui`" " + ($a -join " "); CurrentDirectory = $p; ProcessStartupInformation = $startup }
if ($r.ReturnValue -ne 0) { Write-Error "Couldn't start Godot (WMI code $($r.ReturnValue))."; exit 1 }
Write-Host "pocketperf pid $($r.ProcessId), log $log"
Wait-Process -Id $r.ProcessId -Timeout 1800
Write-Host "done"
