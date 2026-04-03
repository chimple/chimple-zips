#!/bin/bash

# ------------------------- Extract only changed zip files (For CI/CD efficiency)

set -euo pipefail

OUT_DIR="public"
HEAD_REF="${HEAD_SHA:-HEAD}"
BASE_REF="${BASE_SHA:-}"
ZERO_SHA="0000000000000000000000000000000000000000"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "Detecting changed zip files..."

if [ -n "$BASE_REF" ] && [ "$BASE_REF" != "$ZERO_SHA" ] && git cat-file -e "${BASE_REF}^{commit}" 2>/dev/null; then
  DIFF_ARGS=("$BASE_REF" "$HEAD_REF")
else
  DIFF_ARGS=("${HEAD_REF}~1" "$HEAD_REF")
fi

changed_found=false
while IFS= read -r -d '' zipfile; do
  changed_found=true

  if [ ! -f "$zipfile" ]; then
    echo "Skipping missing file: $zipfile"
    continue
  fi

  name=$(basename "$zipfile" .zip)
  target="$OUT_DIR/$name"

  mkdir -p "$target"
  echo "Unzipping $zipfile -> $target"
  unzip -o "$zipfile" -d "$target"
done < <(git diff --name-only -z "${DIFF_ARGS[@]}" -- '*.zip' || true)

if [ "$changed_found" = false ]; then
  echo "No zip files changed. Skipping extraction."
  exit 0
fi

echo "Extraction complete"


# ------------------------- Full repo root extraction (For Syncing All Zips currently present in REpo)

# #!/bin/bash
# set -e
#
# OUT_DIR="public"
#
# # Clean previous output
# rm -rf "$OUT_DIR"
# mkdir -p "$OUT_DIR"
#
# # Loop through all zip files in root
# for zipfile in *.zip; do
#   [ -e "$zipfile" ] || continue
#
#   name=$(basename "$zipfile" .zip)
#   target="$OUT_DIR/$name"
#
#   mkdir -p "$target"
#   echo "Unzipping $zipfile -> $target"
#   unzip -o "$zipfile" -d "$target" || true
# done
