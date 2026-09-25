# Z-fighting hunt in a pocket space (tools/zfightshot.gd): a window that is minimized and never
# activated (the same WMI trick as review.ps1), so it can't take focus. Shots land in
# tools/game_shots/zf_*, the log in .godot/zfightshot.log.
#   tools\zfightshot.ps1 laundromat
#   tools\zfightshot.ps1 natatorium --tag=after --step=0 --no-torch-shadow
param([Parameter(Mandatory = $true, Position = 0)][string]$Pocket,
	[Parameter(ValueFromRemainingArguments = $true)][string[]]$Extra = @())

. "$PSScriptRoot\godot_path.ps1"
$p = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$log = Join-Path $p ".godot\zfightshot.log"
$a = @("--path", "`"$p`"", "--log-file", "`"$log`"", "--resolution", "1280x720",
	"res://tools/zfightshot.tscn", "--", "--no-steam", "`"--pocket=$Pocket`"")
foreach ($e in $Extra) { $a += "`"$e`"" }
$startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]7 }
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
	CommandLine = "`"$GodotGui`" " + ($a -join " "); CurrentDirectory = $p; ProcessStartupInformation = $startup }
if ($r.ReturnValue -ne 0) { Write-Error "Couldn't start Godot (WMI code $($r.ReturnValue))."; exit 1 }
Write-Host "zfightshot pid $($r.ProcessId), log $log"
Wait-Process -Id $r.ProcessId -Timeout 600
Write-Host "done"
