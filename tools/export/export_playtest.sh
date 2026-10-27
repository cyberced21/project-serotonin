#!/bin/sh
## Builds the Windows playtest zip for friends: build/ProjectSerotonin-playtest.zip
## (the exe with the game packed inside, the Terrain3D DLL it needs, and PLAYTEST.txt).
## The "Windows Playtest" preset (export_presets.cfg) is a release build with the "playtest"
## feature, which keeps the debug menu and F-key cheats on.
##   sh tools/export/export_playtest.sh
## Needs Godot 4.7.2's export templates (Editor > Manage Export Templates).
set -e
GODOT="${GODOT:-/e/Godot/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
cd "$(dirname "$0")/../.."
rm -rf build/windows build/ProjectSerotonin-playtest.zip
mkdir -p build/windows
"$GODOT" --headless --path . --export-release "Windows Playtest" build/windows/ProjectSerotonin.exe
cp tools/export/PLAYTEST.txt build/windows/
powershell -NoProfile -Command "Compress-Archive -Path build/windows/* -DestinationPath build/ProjectSerotonin-playtest.zip"
ls -la build/ProjectSerotonin-playtest.zip
