#!/usr/bin/env bash
# Sets up a Linux cloud sandbox to build/run Malpractice headlessly.
# Everything else in tools/ assumes a local Windows Godot install (see
# tools/godot_path.ps1, play.bat) -- this is the Linux equivalent, meant to
# run once as a cloud environment's setup script.
#
# After this runs, use `godot4` in place of the console Godot binary the
# README's "Tools for development" table refers to, e.g.:
#   godot4 --headless --fixed-fps 60 --path . --script tools/mapcheck.gd
set -euo pipefail

GODOT_VERSION="4.7.2-stable"
INSTALL_DIR="/usr/local/bin"

if ! command -v godot4 >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  curl -fLo "$tmp/godot.zip" \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
  unzip -q "$tmp/godot.zip" -d "$tmp"
  install -m 755 "$tmp/Godot_v${GODOT_VERSION}_linux.x86_64" "$INSTALL_DIR/godot4"
  rm -rf "$tmp"
fi

# tools/gen_audio*.mjs need Node; skip if it's already provided by the image.
if ! command -v node >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y -qq nodejs npm
fi

# art/*/blender_src/*.py (hu_build.py, seal_build.py, nn_build.py, ...) run inside Blender,
# headless, to generate the character/monster models -- see art/human/README.md "Rebuild".
# Pinned to match run_all.sh's local Windows install (Blender 5.2).
BLENDER_VERSION="5.2.1"
BLENDER_SERIES="5.2"
if ! command -v blender >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  curl -fLo "$tmp/blender.tar.xz" \
    "https://download.blender.org/release/Blender${BLENDER_SERIES}/blender-${BLENDER_VERSION}-linux-x64.tar.xz"
  tar -xJf "$tmp/blender.tar.xz" -C "$tmp"
  blender_dir="$(find "$tmp" -maxdepth 1 -type d -name 'blender-*')"
  mkdir -p /opt
  mv "$blender_dir" "/opt/blender-${BLENDER_VERSION}"
  ln -sf "/opt/blender-${BLENDER_VERSION}/blender" "$INSTALL_DIR/blender"
  rm -rf "$tmp"
fi

godot4 --version
blender --version

# Global class_name symbols (C in scripts/consts.gd, MapGen, etc.) and autoloads only resolve
# once Godot has imported the project and written .godot/global_script_class_cache.cfg (gitignored,
# regenerated on import). Without this, headless --script runs like tools/mapcheck.gd fail with
# "Identifier ... not declared" parse errors that have nothing to do with the script itself.
godot4 --headless --path . --import
