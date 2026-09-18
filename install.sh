#!/usr/bin/env bash
# Install this fork into Transport Fever 2's local mods folder as timetables_plus_1.
# Override the destination root with TPF2_LOCAL_MODS=/path/to/local/mods.
#
# The Workshop copy of Timetables (2408373260) MUST be disabled: it registers the
# same module paths (res/scripts/celmi/timetables/*) and the same game_script name.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODS="${TPF2_LOCAL_MODS:-$HOME/.local/share/Steam/userdata/204184616/1066780/local/mods}"
DEST="$MODS/timetables_plus_1"
mkdir -p "$DEST"
rsync -a --delete \
  --exclude .git --exclude .github --exclude docs --exclude tests \
  --exclude .superpowers --exclude install.sh \
  --exclude README.md --exclude documentation.md --exclude description.txt \
  --exclude .gitignore --exclude .luacheckrc \
  --exclude workshop_preview.jpg --exclude github_button.png \
  "$SRC/" "$DEST/"
echo "installed to $DEST"
