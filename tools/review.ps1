# Opens a game window from a work slot for Zach to look at. It starts minimized and flashes in the
# taskbar (it never takes focus). The window's title, and a yellow bar at the top of the screen,
# say what it's for. See RULES.md, "Reviews".
#
#   tools\review.bat 2 "HIVE: does the lunge read?"
#   tools\review.bat 2 "OR: try the new saw" -Scene res://tools/monster_lab.tscn
#   tools\review.bat 3 "NET: join and shove me" -Count 2          (two windows, for co-op)
#   tools\review.bat main "FAX: new stamp timing"                 (this checkout instead of a slot)
#   tools\review.bat 4 "ICONS: pick things up" --setup=icons      (skips the menu: a solo shift with the
#                                                                  named setup from scripts/review_setups.gd staged)
#   tools\review.bat 3 "PANEL: from an onlooker's spot" --setup=pack_wrap -Count 2
#                                                                 (the same setup as a connected pair: window 1
#                                                                  hosts and stages it, window 2 joins and stands
#                                                                  beside window 1. One world, no menu clicking.)
#
# -Count with a --setup wires the windows together: window 1 gets --setup-role=host, the rest get
# --setup-role=join, and they share --setup-port (7810 + the slot number, so two slots can each have
# a pair up). -CoopPort picks another. Without a --setup, -Count still just opens N loose windows.
#
# -Front opens it in front, focused and ready for clicks (Zach is waiting for it); without it the
# window waits minimized in the taskbar and its clicks go nowhere until he gives it focus.
#
# A review window plays at 10% of the saved volume, so it doesn't shout over what Zach is doing.
# -Volume 0.5 (or 1 for full) picks another level.
#
# Anything after the named options goes to the game as user args (after "--"), e.g. --seed=3.
# Steam is off (--no-steam) unless you pass --steam. Logs go to <slot>\.godot\review-<n>.log.

param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Slot,
    [Parameter(Mandatory = $true, Position = 1)][string]$Say,
    [string]$Scene = "",
    [int]$Count = 1,
    [double]$Volume = -1,
    [int]$CoopPort = 0,
    [switch]$Front,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$GameArgs = @()
)

. "$PSScriptRoot\godot_path.ps1"
$Main = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ($Slot -eq "main") {
    $p = $Main
} elseif ($Slot -match '^[1-4]$') {
    # Run from inside a slot, $Main is already ...\Malpractice-slots\wt-N: don't add the folder twice.
    $Up = Split-Path $Main -Parent
    $SlotsDir = if ((Split-Path $Up -Leaf) -eq "Malpractice-slots") { $Up } else { Join-Path $Up "Malpractice-slots" }
    $p = Join-Path $SlotsDir "wt-$Slot"
} else {
    $p = $Slot
}
if (-not (Test-Path (Join-Path $p "project.godot"))) { Write-Error "No project at $p"; exit 1 }

# Stale import cache = black screen and "nil" errors (see play.bat); this is quick when current.
& $GodotConsole --headless --path $p --import 2>&1 | Out-File -Encoding utf8 (Join-Path $p ".godot\import.log")

# A staged setup across more than one window becomes a connected pair (scripts/review_setups.gd):
# window 1 hosts and stages, the rest join it, so they share one world instead of playing alone
# side by side. The lock file is how the joiners learn the host is listening; a stale one from a
# killed pair would send them at a port nobody is on, so it goes before anything starts.
$Coop = ($Count -gt 1) -and ($GameArgs | Where-Object { $_ -like "--setup=*" })
if ($Coop) {
    $Port = if ($CoopPort -gt 0) { $CoopPort } elseif ($Slot -match '^[1-4]$') { 7810 + [int]$Slot } else { 7810 }
    $Lock = Join-Path $p ".godot\review-host-$Port.lock"
    if (Test-Path $Lock) { Remove-Item $Lock -Force }
    Write-Host "Co-op review: window 1 hosts on 127.0.0.1:$Port, $($Count - 1) joining."
}

for ($i = 1; $i -le $Count; $i++) {
    $title = if ($Coop -and $i -eq 1) { "$Say (host)" } elseif ($Coop) { "$Say (onlooker $($i - 1))" } elseif ($Count -gt 1) { "$Say ($i)" } else { $Say }
    $log = Join-Path $p ".godot\review-$i.log"
    $a = @("--path", "`"$p`"", "--log-file", "`"$log`"")
    if ($Count -gt 1) { $a += @("--position", ("{0},{1}" -f (60 + ($i - 1) * 820), 80), "--resolution", "800x450") }
    if ($Scene) { $a += $Scene }
    $a += @("--", "`"--review=$title`"", "--no-steam")
    if ($Volume -ge 0) { $a += "`"--volume=$Volume`"" }
    foreach ($g in $GameArgs) { $a += "`"$g`"" }
    if ($Coop) {
        $a += @("`"--setup-role=$(if ($i -eq 1) { 'host' } else { 'join' })`"", "`"--setup-port=$Port`"")
        if ($i -eq 1) { $a += "`"--setup-peers=$($Count - 1)`"" }
    }
    # Minimized and never activated (SW_SHOWMINNOACTIVE): it waits in the taskbar, flashing, until
    # Zach opens it, and doesn't take keyboard focus. Start-Process's "Minimized" still activates the
    # window, and a child of this shell may take the foreground, so WMI starts it instead.
    # -Front: Zach is sitting there waiting for it, so show it normally and let it take focus. A
    # minimized window ignores his clicks until he gives it focus, which reads as a dead window.
    $show = if ($Front) { [uint16]1 } else { [uint16]7 }
    $startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = $show }
    $cmd = "`"$GodotGui`" " + ($a -join " ")
    $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine = $cmd; CurrentDirectory = $p; ProcessStartupInformation = $startup }
    if ($r.ReturnValue -ne 0) { Write-Error "Couldn't start Godot (WMI code $($r.ReturnValue))."; exit 1 }
    Write-Host "Opened: $title  (pid $($r.ProcessId), log: $log)"
}
