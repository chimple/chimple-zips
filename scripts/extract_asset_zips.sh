# ------------------------- Extract only changed zip files (For CI/CD efficiency)

# # !/bin/bash
# set -e

# OUT_DIR="public"

# rm -rf "$OUT_DIR"
# mkdir -p "$OUT_DIR"

# echo "🔍 Detecting changed zip files..."

# CHANGED_ZIPS=$(git diff --name-only HEAD~1 HEAD -- '*.zip' || true)

# if [ -z "$CHANGED_ZIPS" ]; then
#   echo "ℹ️ No zip files changed. Skipping extraction."
#   exit 0
# fi

# for zipfile in $CHANGED_ZIPS; do
#   if [ ! -f "$zipfile" ]; then
#     echo "⚠️ Skipping missing file: $zipfile"
#     continue
#   fi

#   name=$(basename "$zipfile" .zip)
#   target="$OUT_DIR/$name"

#   mkdir -p "$target"
#   echo "📦 Unzipping $zipfile → $target"
#   unzip -o "$zipfile" -d "$target"
# done

# echo "✅ Extraction complete"


# ------------------------- Full repo root extraction (For Syncing All Zips currently present in REpo)

#!/bin/bash
set -e

OUT_DIR="public"

# Clean previous output
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Loop through all zip files in root
for zipfile in *.zip; do
  [ -e "$zipfile" ] || continue

  name=$(basename "$zipfile" .zip)
  target="$OUT_DIR/$name"

  mkdir -p "$target"
  echo "Unzipping $zipfile -> $target"
  unzip -o "$zipfile" -d "$target" || true
done
