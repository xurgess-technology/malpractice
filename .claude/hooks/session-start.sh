#!/bin/bash
# Claude Code on the web: runs tools/setup_cloud.sh so godot4/blender/node are present and the
# Godot project is imported (builds .godot/global_script_class_cache.cfg -- without it, global
# class_name symbols like C in scripts/consts.gd don't resolve and headless --script runs such
# as tools/mapcheck.gd fail with spurious "Identifier ... not declared" parse errors).
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

"$CLAUDE_PROJECT_DIR/tools/setup_cloud.sh"
