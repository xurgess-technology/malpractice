# TAB SHEET smoke look: runs tools/sheetshot.tscn in a window that is minimized and never
# activated (the same WMI trick as review.ps1), so it can't take focus while Zach is working.
# Shots land in tools/game_shots/sheet_*.png, the log in .godot\sheetshot.log.
. "$PSScriptRoot\godot_path.ps1"
$p = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$log = Join-Path $p ".godot\sheetshot.log"
$a = @("--path", "`"$p`"", "--log-file", "`"$log`"", "--resolution", "1280x720",
	"res://tools/sheetshot.tscn", "--", "--no-steam", "--setup=sheet")
$startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]7 }
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
	CommandLine = "`"$GodotGui`" " + ($a -join " "); CurrentDirectory = $p; ProcessStartupInformation = $startup }
if ($r.ReturnValue -ne 0) { Write-Error "Couldn't start Godot (WMI code $($r.ReturnValue))."; exit 1 }
Write-Host "sheetshot pid $($r.ProcessId), log $log"
Wait-Process -Id $r.ProcessId -Timeout 600
Write-Host "done"
