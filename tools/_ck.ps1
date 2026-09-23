. "$PSScriptRoot\godot_path.ps1"
$p = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$log = Join-Path $p ".godot\chapelperf.log"
$a = @("--path", "`"$p`"", "--log-file", "`"$log`"", "--resolution", "1920x1080",
	"res://tools/perfprobe.tscn", "--", "--no-steam", "--pocketkind=chapel")
$startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]7 }
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
	CommandLine = "`"$GodotGui`" " + ($a -join " "); CurrentDirectory = $p; ProcessStartupInformation = $startup }
Write-Host "pid $($r.ProcessId)"
Wait-Process -Id $r.ProcessId -Timeout 1200
Write-Host done
