# ONLOOKER smoke look: the Onlooker's shadow and its poof in each pocket space (tools/gameshot.gd
# --pocket=<kind> --only=onlooker), one never-activated window per space, one at a time, parked off
# the edge of the desktop (SW_SHOWNOACTIVATE, as perfprobe.ps1 does). NOT minimized: a minimized
# Godot window stops drawing, and the particles in these shots simply were not there. It takes no
# focus and closes itself. Shots land in tools/game_shots/p_<kind>_o*.png, the logs in
# .godot/onlookershot_<kind>.log.
param([string[]]$Kinds = @("natatorium", "chapel", "factory", "laundromat", "restaurant"))

. "$PSScriptRoot\godot_path.ps1"
$p = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
foreach ($k in ($Kinds -join ",").Split(",")) {
	$log = Join-Path $p ".godot\onlookershot_$k.log"
	$a = @("--path", "`"$p`"", "--log-file", "`"$log`"", "--resolution", "1280x720", "--position", "-4000,-4000",
		"res://tools/gameshot.tscn", "--", "--no-steam", "--pocket=$k", "--only=onlooker")
	$startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]4 }
	$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
		CommandLine = "`"$GodotGui`" " + ($a -join " "); CurrentDirectory = $p; ProcessStartupInformation = $startup }
	if ($r.ReturnValue -ne 0) { Write-Error "Couldn't start Godot (WMI code $($r.ReturnValue))."; exit 1 }
	Write-Host "onlookershot $k pid $($r.ProcessId), log $log"
	Wait-Process -Id $r.ProcessId -Timeout 600 -ErrorAction SilentlyContinue
	if (Get-Process -Id $r.ProcessId -ErrorAction SilentlyContinue) { Stop-Process -Id $r.ProcessId -Force }
}
Write-Host "done"
