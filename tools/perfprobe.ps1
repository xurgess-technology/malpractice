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
#
# POCKETS: `--pockets` is this script's loop, not the probe's. One Godot process measures one pocket
# kind (`--pocket=<kind>`, or `--pocket=none` for the bare hospital), and this script runs one per
# kind and stitches their tables into one. The probe used to do the loop itself, restarting the
# session per kind; tearing a level down and rebuilding it trips a Godot renderer bug ("BUG, indexing
# did not unpair geometries from light", then signal 11) and no row ever printed. Letting the renderer
# settle first does not help -- see docs/FAILING_TESTS.md. A process per kind never restarts anything.
param([string]$Extra = "", [int]$TimeoutSec = 1800)

. "$PSScriptRoot\godot_path.ps1"
$p = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# One probe process. $UserArgs go after the `--`; the log is this run's alone.
function Start-Probe([string[]] $UserArgs, [string] $LogPath) {
	$a = @("--path", "`"$p`"", "--log-file", "`"$LogPath`"", "--resolution", "1280x720",
		"res://tools/perfprobe.tscn", "--", "--no-steam") + $UserArgs
	$startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]4 }
	$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
		CommandLine = "`"$GodotGui`" " + ($a -join " "); CurrentDirectory = $p; ProcessStartupInformation = $startup }
	if ($r.ReturnValue -ne 0) { Write-Error "Couldn't start Godot (WMI code $($r.ReturnValue))."; exit 1 }
	$procId = [int] $r.ProcessId
	Write-Host "perfprobe pid $procId, log $LogPath"
	try { Wait-Process -Id $procId -Timeout $TimeoutSec -ErrorAction Stop }
	catch {
		# Kill by PID only: other work slots have their own Godot processes running.
		Write-Warning "perfprobe pid $procId passed $TimeoutSec s; killing it."
		Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
	}
}

$log = Join-Path $p ".godot\perfprobe.log"
$extraArgs = @()
if ($Extra) { $extraArgs = @($Extra.Split(" ") | Where-Object { $_ -ne "" }) }

if (-not ($extraArgs -contains "--pockets")) {
	Start-Probe $extraArgs $log
	Write-Host "done"
	exit 0
}

# POCKETS: the kinds come out of the game, so a new space joins the sweep on its own.
$rest = @($extraArgs | Where-Object { $_ -ne "--pockets" -and $_ -notlike "--pocket=*" })
$planPath = Join-Path $p "scripts\level\pockets\pocket_plan.gd"
$m = [regex]::Match((Get-Content -Raw $planPath), 'const\s+KINDS\s*:=\s*\[([^\]]*)\]')
if (-not $m.Success) { Write-Error "Couldn't read KINDS out of $planPath"; exit 1 }
$kinds = @("none") + @([regex]::Matches($m.Groups[1].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
Write-Host "pockets sweep: $($kinds -join ', ') -- one process each"

$rows = @()
$missing = @()
$logs = @()
foreach ($kind in $kinds) {
	$kindLog = Join-Path $p ".godot\perfprobe-$kind.log"
	Start-Probe (@("--pocket=$kind") + $rest) $kindLog
	$logs += $kindLog
	$got = 0
	if (Test-Path $kindLog) {
		foreach ($line in (Get-Content $kindLog)) {
			if ($line -match '^\[perfrow\] (.*)$') {
				$f = $Matches[1].Split("|")
				if ($f.Count -ge 9) { $rows += , $f; $got++ }
			}
		}
	}
	if ($got -eq 0) { $missing += $kind; Write-Warning "$kind measured nothing (see $kindLog)." }
	else { Write-Host "${kind}: $got rows" }
}

# .godot\perfprobe.log is where everyone looks, so the whole sweep ends up there too.
Set-Content -Path $log -Value ($logs | ForEach-Object {
	"===== $_ ====="
	if (Test-Path $_) { Get-Content $_ }
})

Write-Host ""
Write-Host ("[perf] " + ("=" * 100))
Write-Host ("[perf] {0,-50} {1}  {2,7}  {3,9}  {4,8}  {5,7}  {6,7}  {7,5}  {8,5}" -f `
	"scenario", "q", "avg fps", "1%low fps", "worst ms", "phys ms", "proc ms", "draws", "nodes")
foreach ($r in $rows) {
	Write-Host ("[perf] {0,-50} {1}  {2,7}  {3,9}  {4,8}  {5,7}  {6,7}  {7,5}  {8,5}" -f `
		$r[0], $r[1], $r[2], $r[3], $r[4], $r[5], $r[6], $r[7], $r[8])
}
Write-Host "done"
if ($missing.Count -gt 0) { Write-Error "no rows from: $($missing -join ', ')"; exit 1 }
exit 0
