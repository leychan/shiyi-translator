#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bundle_dir="$project_dir/build/linux/x64/release/bundle"
install_dir="${XDG_DATA_HOME:-$HOME/.local/share}/just-translator"
applications_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
icons_dir="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/64x64/apps"
if [[ ! -x "$bundle_dir/just_translator" ]]; then
  echo '请先运行 flutter build linux --release' >&2
  exit 1
fi
mkdir -p "$(dirname -- "$install_dir")" "$applications_dir" "$icons_dir"
staging_dir="$(mktemp -d "${install_dir}.stage.XXXXXX")"
cp -a "$bundle_dir/." "$staging_dir/"
python3 - "$staging_dir" "$install_dir" <<'PY'
from pathlib import Path
import os
import sys
import time
staging, destination = map(Path, sys.argv[1:])
previous = destination.with_name(f'{destination.name}.previous-{time.time_ns()}')
if destination.exists():
    destination.rename(previous)
try:
    os.replace(staging, destination)
except OSError:
    if previous.exists() and not destination.exists():
        previous.rename(destination)
    raise
PY
cp "$project_dir/assets/tray.png" "$icons_dir/dev.justtranslator.just_translator.png"
python3 - "$project_dir/packaging/dev.justtranslator.just_translator.desktop" "$applications_dir/dev.justtranslator.just_translator.desktop" "$install_dir/just_translator" <<'PY'
from pathlib import Path
import sys
source, destination, executable = sys.argv[1:]
# Desktop Entry Exec quoting differs from shell quoting.
escaped = executable.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
Path(destination).write_text(Path(source).read_text().replace('Exec=just_translator', f'Exec="{escaped}"'))
PY
if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$applications_dir"
fi
echo "已安装到 $install_dir，可从应用菜单启动拾译（Shiyi Translator）。"
