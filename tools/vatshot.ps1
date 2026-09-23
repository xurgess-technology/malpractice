# GRAFTING vat-bench smoke look: runs tools/vatshot.tscn in a window that is minimized and never activated
# (the same WMI trick as review.ps1), so it can't take focus while Zach is working.
# Shots land in tools/vat_shots/, the log in .godot/vatshot.log.
param([string]$Extra = "")

. "$PSScriptRoot\godot_path.ps1"
$p = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$log = Join-Path $p ".godot\vatshot.log"
$a = @("--path", "`"$p`"", "--log-file", "`"$log`"", "--resolution", "1280x720",
	"res://tools/vatshot.tscn", "--", "--no-steam")
if ($Extra) { $a += "`"$Extra`"" }
$startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]7 }
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
	CommandLine = "`"$GodotGui`" " + ($a -join " "); CurrentDirectory = $p; ProcessStartupInformation = $startup }
if ($r.ReturnValue -ne 0) { Write-Error "Couldn't start Godot (WMI code $($r.ReturnValue))."; exit 1 }
Write-Host "vatshot pid $($r.ProcessId), log $log"
Wait-Process -Id $r.ProcessId -Timeout 900
Write-Host "done"
