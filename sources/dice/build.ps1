param([string]$Godot = $env:GODOT_BIN, [switch]$RebakeDice)
& "$PSScriptRoot/../../tools/build.ps1" -Widget dice -Godot $Godot -RebakeDice:$RebakeDice
